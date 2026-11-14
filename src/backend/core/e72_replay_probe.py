"""One JSON request on stdin for the isolated Dart replay integration."""
import json
import os
import sys
from datetime import date
from uuid import UUID

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "cunismart_backend.settings")

import django

django.setup()

from django.contrib.auth import get_user_model
from django.db import connection

from core.genealogy import assign_or_update, public_link
from core.models import ParentLink, Rabbit, ReproductiveEvent, SyncOperationReceipt
from core.reproductive_service import ReproductiveEventService
from core.sync_receipts import ReceiptKeyConflict, ReceiptResult, execute_idempotent


def main(request):
    config = connection.settings_dict
    if (config["NAME"], config["HOST"], str(config["PORT"])) != (
        "e72_replay", "127.0.0.1", "55472",
    ):
        raise RuntimeError("The isolated E7.2 replay database is required")

    model = get_user_model()
    label = f"replay-{UUID(request['runUuid'])}@example.test"
    if request.get("setup"):
        owner, _ = model.objects.get_or_create(
            **{model.USERNAME_FIELD: label},
        )
        rabbits = {}
        for sex in ("male", "female"):
            rabbit, _ = Rabbit.objects.get_or_create(
                user=owner, name=sex,
                defaults={"sex": sex, "breed": "Rex", "birth_date": date(2025, 1, 1)},
            )
            rabbits[sex] = str(rabbit.uuid)
        return {"ownerId": owner.pk, **rabbits}

    owner = model.objects.get(**{model.USERNAME_FIELD: label})
    command = json.loads(request["command"])
    payload = command["payload"]

    def effect():
        if command["entityType"] == "PARENT_LINK":
            child = Rabbit.objects.get(user=owner, uuid=payload["child_uuid"])
            parent = Rabbit.objects.get(user=owner, uuid=payload["parent_uuid"])
            link = assign_or_update(child=child, parent=parent, role=payload["role"], version=None)
            identity = {"childUuid": str(child.uuid), "role": link.role}
            return ReceiptResult(201, public_link(link), remote_identity=identity,
                                 remote_version=link.version)
        event = ReproductiveEventService().create(
            owner_id=owner.pk, male_uuid=payload["male_uuid"], female_uuid=payload["female_uuid"],
            mating_date=date.fromisoformat(payload["mating_date"]), notes=payload.get("notes", ""),
        )
        identity = {"uuid": str(event.uuid)}
        return ReceiptResult(201, identity, remote_identity=identity, remote_version=event.version)

    try:
        receipt = execute_idempotent(
            owner=owner, operation_uuid=request["operationUuid"], effect=effect,
            entity_type=command["entityType"], action=command["action"],
            destination=command["destination"], payload=payload,
            expected_version=command["expectedVersion"], contract_version=command["version"],
        )
    except ReceiptKeyConflict:
        return {"conflict": True, "events": ReproductiveEvent.objects.filter(user=owner).count()}

    return {
        "receiptId": receipt.pk, "ownerId": receipt.owner_id,
        "operationUuid": str(receipt.operation_uuid), "requestHash": receipt.request_hash,
        "entityType": receipt.entity_type, "action": receipt.action,
        "contractVersion": receipt.contract_version, "remoteIdentity": receipt.remote_identity,
        "remoteVersion": receipt.remote_version, "statusCode": receipt.status_code,
        "bodyPresent": receipt.body_present, "responseBody": receipt.response_body,
        "confirmedAt": receipt.confirmed_at.isoformat(),
        "events": ReproductiveEvent.objects.filter(user=owner).count(),
        "links": ParentLink.objects.filter(child__user=owner).count(),
        "receipts": SyncOperationReceipt.objects.filter(owner=owner).count(),
    }


if __name__ == "__main__":
    print(json.dumps(main(json.loads(sys.stdin.buffer.read().decode("utf-8"))), ensure_ascii=True))
