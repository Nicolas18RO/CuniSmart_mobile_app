"""HTTP opt-in adapter for the existing R3 mutations."""
import base64
import json
from datetime import date
from functools import wraps
from uuid import UUID

from rest_framework.exceptions import APIException, ValidationError
from rest_framework.response import Response

from .models import ParentLink, ReproductiveEvent
from .sync_receipts import ReceiptKeyConflict, ReceiptResult, execute_idempotent


class IdempotencyKeyConflict(APIException):
    status_code = 409
    default_code = "idempotency_key_conflict"

    def __init__(self):
        super().__init__({
            "detail": "This idempotency key belongs to a different command.",
            "code": self.default_code,
        })


def _uuid(value):
    try:
        canonical = str(UUID(value))
    except (ValueError, AttributeError, TypeError):
        raise ValidationError("Expected a canonical UUID.") from None
    if value != canonical:
        raise ValidationError("Expected a canonical UUID.")
    return canonical


def _command(request, entity, action, kwargs):
    data = request.data
    if not isinstance(data, dict) or request.query_params:
        raise ValidationError("Expected JSON and no query parameters.")
    parent = entity == "PARENT_LINK"
    if parent:
        child = str(kwargs["rabbit_uuid"])
        role = kwargs["role"]
        if role not in {"FATHER", "MOTHER"}:
            raise ValidationError("Invalid parent role.")
        destination = f"/api/rabbits/{child}/parents/{role}/"
        method = "DELETE" if action == "DELETE" else "PUT"
        required = {"parent_uuid"} if action != "DELETE" else set()
        allowed = required.copy()
    else:
        destination = "/api/reproductive-events/"
        if action != "CREATE":
            destination += f"{_uuid(kwargs.get('pk'))}/"
        method = {"CREATE": "POST", "UPDATE": "PATCH", "DELETE": "DELETE"}[action]
        required = {"male_uuid", "female_uuid", "mating_date"} if action == "CREATE" else set()
        allowed = set() if action == "DELETE" else required | {"mating_date", "notes"}
    if request.method != method or request.path != destination:
        raise ValidationError("Sync action does not match the route.")
    if action != "CREATE":
        required.add("version")
        allowed.add("version")
    if not required <= data.keys() or not data.keys() <= allowed:
        raise ValidationError("Invalid sync payload fields.")
    expected = data.get("version")
    if action != "CREATE" and (type(expected) is not int or not 1 <= expected <= 2147483647):
        raise ValidationError("Invalid expected version.")
    payload = {k: v for k, v in data.items() if k != "version"}
    for key, value in payload.items():
        if key.endswith("_uuid"):
            _uuid(value)
        elif key == "mating_date":
            try:
                if date.fromisoformat(value).isoformat() != value:
                    raise ValueError
            except (ValueError, TypeError):
                raise ValidationError("Expected an ISO civil date.") from None
        elif not isinstance(value, str):
            raise ValidationError("Expected notes as a string.")
    return dict(entity_type=entity, action=action, destination=destination,
                payload=payload, expected_version=expected)


def r3_idempotent(entity, *actions):
    def decorate(view):
        @wraps(view)
        def wrapped(self, request, *args, **kwargs):
            headers = [request.headers.get(name) for name in (
                "Idempotency-Key", "X-CuniSmart-Sync-Version", "X-CuniSmart-Sync-Action",
            )]
            if all(value is None for value in headers):
                return view(self, request, *args, **kwargs)
            key, version, action = headers
            if version != "1" or action not in actions:
                raise ValidationError("Unsupported sync version or action.")
            _uuid(key)
            command = _command(request, entity, action, kwargs)

            def effect():
                response = view(self, request, *args, **kwargs)
                body = response.data
                present = response.status_code != 204
                if entity == "PARENT_LINK":
                    identity = {"childUuid": body["child_uuid"], "role": body["role"]}
                    remote_version = body["version"]
                    cycle = ParentLink.objects.get(
                        child__user=request.user, child__uuid=body["child_uuid"],
                        role=body["role"], version=remote_version,
                    )
                    if cycle.cycle_uuid is not None:
                        identity["cycleUuid"] = str(cycle.cycle_uuid)
                        identity["creationVersion"] = cycle.creation_version
                elif present:
                    identity = {"uuid": body["uuid"]}
                    remote_version = body["version"]
                else:
                    event = ReproductiveEvent.objects.get(user=request.user, uuid=kwargs["pk"])
                    identity = {"uuid": str(event.uuid)}
                    remote_version = event.version
                return ReceiptResult(response.status_code, body, present, identity, remote_version)

            try:
                receipt = execute_idempotent(
                    owner=request.user, operation_uuid=key, effect=effect, **command,
                )
            except ReceiptKeyConflict:
                raise IdempotencyKeyConflict() from None
            evidence = {
                "receiptId": receipt.pk, "ownerId": receipt.owner_id,
                "operationUuid": str(receipt.operation_uuid),
                "requestHash": receipt.request_hash, "entityType": receipt.entity_type,
                "action": receipt.action, "contractVersion": receipt.contract_version,
                "remoteIdentity": receipt.remote_identity, "remoteVersion": receipt.remote_version,
                "statusCode": receipt.status_code, "bodyPresent": receipt.body_present,
                "confirmedAt": receipt.confirmed_at.isoformat(),
            }
            header = base64.urlsafe_b64encode(json.dumps(evidence, separators=(",", ":")).encode())
            return Response(receipt.response_body, status=receipt.status_code,
                            headers={"X-CuniSmart-Sync-Receipt": header.decode("ascii")})

        return wrapped
    return decorate
