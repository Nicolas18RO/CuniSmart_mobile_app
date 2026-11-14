"""Atomic ParentLink A→B replacement for HTTP contract v2."""
from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import NotFound, ValidationError

from .genealogy import _refresh_knowledge
from .models import ParentLink, Rabbit
from .sync_receipts import ReceiptResult, execute_idempotent


def replace_parent_link(*, owner, child_uuid, role, previous_cycle_uuid,
                        expected_version, parent_uuid, operation_uuid):
    if role not in (ParentLink.Role.FATHER, ParentLink.Role.MOTHER):
        raise ValidationError("Invalid parent role.")
    if type(expected_version) is not int or expected_version < 1:
        raise ValidationError("Invalid expected version.")

    def effect():
        with transaction.atomic():
            child = Rabbit.objects.select_for_update().filter(
                user_id=owner.pk, uuid=child_uuid, deleted_at__isnull=True,
            ).first()
            if child is None:
                raise NotFound()
            old = ParentLink.objects.select_for_update().filter(
                child=child, role=role, cycle_uuid=previous_cycle_uuid,
                deleted_at__isnull=True,
            ).select_related("parent").first()
            if old is None:
                raise ValidationError({"code": "unresolved_cycle"})
            if old.version != expected_version:
                from .exceptions import VersionConflict
                raise VersionConflict(current={"version": old.version})
            parent = Rabbit.objects.filter(
                user_id=owner.pk, uuid=parent_uuid, deleted_at__isnull=True,
            ).first()
            if parent is None or parent.pk == child.pk:
                raise NotFound()
            required = Rabbit.Sex.MALE if role == ParentLink.Role.FATHER else Rabbit.Sex.FEMALE
            if parent.sex != required:
                raise ValidationError("Invalid parent sex.")
            now = timezone.now()
            old.deleted_at = now
            old.version += 1
            old.save(update_fields=["deleted_at", "version", "updated_at"])
            new = ParentLink.objects.create(
                child=child, parent=parent, role=role,
                creation_version=1, version=1,
            )
            _refresh_knowledge(child)
            body = {
                "operationUuid": str(operation_uuid), "contractVersion": 2,
                "status": "COMPLETED", "ownerId": owner.pk,
                "childUuid": str(child.uuid), "role": role,
                "previous": {"cycleUuid": str(old.cycle_uuid),
                              "version": expected_version, "deleted": True,
                              "deletedVersion": old.version,
                              "deletedAt": old.deleted_at.isoformat()},
                "replacement": {"cycleUuid": str(new.cycle_uuid),
                                 "parentUuid": str(new.parent.uuid),
                                 "creationVersion": new.creation_version,
                                 "version": new.version, "deleted": False},
            }
            return ReceiptResult(
                201, body, True,
                {"previousCycleUuid": str(old.cycle_uuid),
                 "cycleUuid": str(new.cycle_uuid),
                 "childUuid": str(child.uuid), "role": role,
                 "creationVersion": new.creation_version},
                new.version,
            )

    return execute_idempotent(
        owner=owner, operation_uuid=operation_uuid, effect=effect,
        entity_type="PARENT_LINK", action="REPLACE",
        destination=f"/api/rabbits/{child_uuid}/parents/{role}/replace/",
        payload={"previous": {"cycleUuid": str(previous_cycle_uuid),
                               "expectedVersion": expected_version},
                 "replacement": {"parent_uuid": str(parent_uuid)}},
        expected_version=expected_version, contract_version=2,
    )
