"""Versioned command canonicalization and durable idempotency for future R3 callers."""
import hashlib
import json
from dataclasses import dataclass
from uuid import UUID

from .genealogy_transactions import owner_write
from .models import SyncOperationReceipt


class ReceiptKeyConflict(ValueError):
    """The owner has already committed a different command under this key."""


_METHODS = {
    "PARENT_LINK": {"CREATE": "PUT", "UPDATE": "PUT", "DELETE": "DELETE", "REPLACE": "POST"},
    "REPRODUCTIVE_EVENT": {"CREATE": "POST", "UPDATE": "PATCH", "DELETE": "DELETE"},
}
_MAX_SAFE_INTEGER = 9007199254740991


def _validate_json(value):
    if value is None or type(value) in (bool, str):
        return
    if type(value) is int and abs(value) <= _MAX_SAFE_INTEGER:
        return
    if isinstance(value, list):
        for item in value:
            _validate_json(item)
        return
    if isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str):
                raise ValueError("Command keys must be strings")
            _validate_json(item)
        return
    raise ValueError("Command accepts only JSON with safe integers")


def canonical_command(*, entity_type, action, destination, payload,
                      expected_version=None, contract_version=1):
    """Hash normalized business fields. Float, network metadata and tokens are excluded."""
    method = _METHODS.get(entity_type, {}).get(action)
    if type(contract_version) is not int or contract_version not in (1, 2) or method is None:
        raise ValueError("Unsupported command contract")
    if not isinstance(destination, str) or not destination.startswith("/") or (
        not destination.isascii() or any(c.isspace() or c in "?#" for c in destination)
    ):
        raise ValueError("Expected a normalized ASCII destination path")
    if not isinstance(payload, dict):
        raise ValueError("Expected a payload object")
    if expected_version is not None and (
        type(expected_version) is not int or not 1 <= expected_version <= 2147483647
    ):
        raise ValueError("Invalid expected version")
    command = {
        "action": action, "destination": destination, "entityType": entity_type,
        "expectedVersion": expected_version, "method": method, "payload": payload,
        "version": contract_version,
    }
    _validate_json(command)
    return json.dumps(command, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":")).encode("utf-8")


@dataclass(frozen=True)
class ReceiptResult:
    status_code: int
    response_body: object = None
    body_present: bool = True
    remote_identity: dict | None = None
    remote_version: int | None = None


def execute_idempotent(*, owner, operation_uuid, effect, **command):
    """Run a database-only effect under the same owner lock as its receipt."""
    if not getattr(owner, "is_authenticated", False) or owner.pk is None:
        raise ValueError("An authenticated owner is required")
    operation_uuid = UUID(str(operation_uuid))
    canonical = canonical_command(**command)
    request_hash = hashlib.sha256(canonical).hexdigest()
    with owner_write(owner.pk):
        receipt = SyncOperationReceipt.objects.filter(
            owner_id=owner.pk, operation_uuid=operation_uuid,
        ).first()
        if receipt is not None:
            if receipt.request_hash != request_hash:
                raise ReceiptKeyConflict("Operation UUID already used for another command")
            return receipt
        result = effect()
        if not isinstance(result, ReceiptResult) or not 200 <= result.status_code < 300:
            raise ValueError("Expected a successful domain result")
        # Cooperating writers serialize on the owner. Unexpected integrity
        # errors propagate out of the atomic block and roll back the effect.
        return SyncOperationReceipt.objects.create(
            owner_id=owner.pk, operation_uuid=operation_uuid,
            entity_type=command["entity_type"], action=command["action"],
            contract_version=command.get("contract_version", 1),
            request_hash=request_hash, remote_identity=result.remote_identity,
            remote_version=result.remote_version, status_code=result.status_code,
            response_body=result.response_body, body_present=result.body_present,
        )
