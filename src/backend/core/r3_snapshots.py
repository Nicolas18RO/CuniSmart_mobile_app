"""Owner-scoped immutable read snapshots for R3 hydration."""
from datetime import date

from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from uuid import UUID

from .genealogy_transactions import owner_write
from .models import ParentLink, ReproductiveEvent, R3ReadSnapshot


def _uuid(value):
    try:
        return str(UUID(value))
    except (TypeError, ValueError, AttributeError):
        raise ValidationError("Invalid child UUID.") from None


def _scope(data):
    if not isinstance(data, dict):
        raise ValidationError("Expected a snapshot scope.")
    entity = data.get("entity")
    size = data.get("page_size", 100)
    if type(size) is not int or not 1 <= size <= 200:
        raise ValidationError("Invalid page size.")
    if entity == "PARENT_LINK":
        children = data.get("children")
        roles = data.get("roles", ["FATHER", "MOTHER"])
        if children is not None and (not isinstance(children, list) or len(children) > 200):
            raise ValidationError("Expected up to 200 child UUIDs.")
        if not isinstance(roles, list) or not roles or any(
            role not in ("FATHER", "MOTHER") for role in roles
        ):
            raise ValidationError("Invalid parent roles.")
        return entity, size, {
            "children": sorted({_uuid(value) for value in children}) if children is not None else None,
            "roles": sorted(set(roles)),
        }
    if entity == "REPRODUCTIVE_EVENT":
        try:
            start = date.fromisoformat(data["from"]) if "from" in data else None
            end = date.fromisoformat(data["to"]) if "to" in data else None
        except (ValueError, TypeError):
            raise ValidationError("Invalid mating date range.") from None
        if start and end and start > end:
            raise ValidationError("Invalid mating date range.")
        return entity, size, {"from": start.isoformat() if start else None,
                              "to": end.isoformat() if end else None}
    raise ValidationError("Unknown R3 entity.")


def _row(row, **identity):
    return {
        **identity, "version": row.version,
        "deleted_at": row.deleted_at.isoformat() if row.deleted_at else None,
        "created_at": row.created_at.isoformat(),
        "updated_at": row.updated_at.isoformat(),
    }


def _capture(owner, entity, scope):
    if entity == "PARENT_LINK":
        links = ParentLink.objects.filter(
            child__user_id=owner, parent__user_id=owner, role__in=scope["roles"],
        ).select_related("child", "parent").order_by("child__uuid", "role", "id")
        if scope["children"] is not None:
            links = links.filter(child__uuid__in=scope["children"])
        return [_row(
            link, child_uuid=str(link.child.uuid), parent_uuid=str(link.parent.uuid),
            role=link.role, cycle_uuid=str(link.cycle_uuid) if link.cycle_uuid else None,
            creation_version=link.creation_version,
            identity_status="RESOLVED" if link.cycle_uuid else "UNRESOLVED",
        ) for link in links]
    events = ReproductiveEvent.objects.filter(
        user_id=owner, male__user_id=owner, female__user_id=owner,
    ).select_related("male", "female").order_by("uuid")
    if scope["from"]:
        events = events.filter(mating_date__gte=scope["from"])
    if scope["to"]:
        events = events.filter(mating_date__lte=scope["to"])
    return [_row(
        event, uuid=str(event.uuid), male_uuid=str(event.male.uuid),
        female_uuid=str(event.female.uuid), mating_date=event.mating_date.isoformat(),
        notes=event.notes,
    ) for event in events]


def _page(snapshot, ordinal):
    total = len(snapshot.items)
    pages = max(1, (total + snapshot.page_size - 1) // snapshot.page_size)
    if not 0 <= ordinal < pages:
        raise ValidationError("Invalid snapshot cursor.")
    offset = ordinal * snapshot.page_size
    return {
        "snapshot_uuid": str(snapshot.uuid), "owner_id": snapshot.owner_id,
        "entity": snapshot.entity, "scope": snapshot.scope,
        "cut": snapshot.created_at.isoformat(), "revision": snapshot.pk,
        "page": ordinal, "pages": pages, "total": total,
        "items": snapshot.items[offset:offset + snapshot.page_size],
        "next_cursor": ordinal + 1 if ordinal + 1 < pages else None,
    }


class R3SnapshotView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        entity, size, scope = _scope(request.data)
        owner = request.user.pk
        with owner_write(owner):
            snapshot = R3ReadSnapshot.objects.create(
                owner_id=owner, entity=entity, scope=scope, page_size=size,
                items=_capture(owner, entity, scope),
            )
        return Response(_page(snapshot, 0), status=201)


class R3SnapshotPageView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, snapshot_uuid):
        snapshot = R3ReadSnapshot.objects.filter(
            owner=request.user, uuid=snapshot_uuid,
        ).first()
        if snapshot is None:
            raise NotFound()
        cursor = request.query_params.get("cursor", "")
        if not cursor.isascii() or not cursor.isdecimal() or len(cursor) > 10:
            raise ValidationError("Invalid snapshot cursor.")
        return Response(_page(snapshot, int(cursor)))
