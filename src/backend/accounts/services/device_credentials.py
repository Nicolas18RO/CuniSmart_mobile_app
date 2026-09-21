"""Device public-key credentials for biometric login (option C)."""

from __future__ import annotations

import base64
import hashlib
import secrets
import uuid
from datetime import timedelta

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from django.conf import settings
from django.utils import timezone
from rest_framework_simplejwt.tokens import RefreshToken

from accounts.models import DeviceChallenge, DeviceCredential
from accounts.services.auth_service import validate_user_login
from accounts.services.jwt_claims import apply_user_claims_to_token_pair

CHALLENGE_TTL_SECONDS = 90


class DeviceCredentialError(Exception):
    def __init__(self, code: str, message: str | None = None):
        super().__init__(code)
        self.code = code
        self.message = message or code


def hash_nonce(credential_id, nonce: str) -> str:
    return hashlib.sha256(f"dc:{credential_id}:{nonce}".encode("utf-8")).hexdigest()


def _load_public_key(pem: str):
    try:
        key = serialization.load_pem_public_key((pem or "").encode("utf-8"))
    except Exception as exc:
        raise DeviceCredentialError("invalid_public_key", "Invalid public key.") from exc
    return key


def verify_rsa_signature(*, public_key_pem: str, nonce: str, signature: str) -> bool:
    try:
        public_key = _load_public_key(public_key_pem)
        raw = base64.b64decode(signature, validate=True)
        public_key.verify(
            raw,
            nonce.encode("utf-8"),
            padding.PKCS1v15(),
            hashes.SHA256(),
        )
        return True
    except (InvalidSignature, ValueError, TypeError, DeviceCredentialError):
        return False


def enroll_device_credential(*, user, public_key: str, device_label: str = "") -> DeviceCredential:
    _load_public_key(public_key)
    return DeviceCredential.objects.create(
        user=user,
        public_key=public_key.strip(),
        device_label=(device_label or "")[:128],
    )


def issue_device_challenge(*, credential_id: str) -> tuple[str, DeviceChallenge]:
    credential = _get_credential(credential_id)
    if credential.revoked_at is not None:
        raise DeviceCredentialError("credential_revoked", "Device credential was revoked.")
    ttl = int(getattr(settings, "DEVICE_CREDENTIAL_CHALLENGE_TTL_SECONDS", CHALLENGE_TTL_SECONDS))
    nonce = secrets.token_urlsafe(32)
    now = timezone.now()
    challenge = DeviceChallenge.objects.create(
        credential=credential,
        nonce_hash=hash_nonce(credential.pk, nonce),
        expires_at=now + timedelta(seconds=ttl),
    )
    return nonce, challenge


def revoke_device_credential(*, user, credential_id: str) -> None:
    credential = _get_credential(credential_id, required_user=user)
    if credential.revoked_at is None:
        credential.revoked_at = timezone.now()
        credential.save(update_fields=["revoked_at"])


def login_with_device_credential(*, credential_id: str, nonce: str, signature: str) -> dict[str, str]:
    credential = _get_credential(credential_id)
    if credential.revoked_at is not None:
        raise DeviceCredentialError("credential_revoked", "Device credential was revoked.")

    policy = validate_user_login(credential.user)
    if not policy.ok:
        raise DeviceCredentialError(policy.code or "invalid_credentials", policy.message)

    digest = hash_nonce(credential.pk, nonce)
    challenge = (
        DeviceChallenge.objects.filter(credential=credential, nonce_hash=digest)
        .order_by("-created_at")
        .first()
    )
    if challenge is None:
        raise DeviceCredentialError("invalid_signature", "Invalid device signature.")
    if challenge.used_at is not None:
        raise DeviceCredentialError("challenge_expired", "Challenge already used.")
    if challenge.expires_at <= timezone.now():
        raise DeviceCredentialError("challenge_expired", "Challenge expired.")
    if not verify_rsa_signature(
        public_key_pem=credential.public_key,
        nonce=nonce,
        signature=signature,
    ):
        raise DeviceCredentialError("invalid_signature", "Invalid device signature.")

    challenge.used_at = timezone.now()
    challenge.save(update_fields=["used_at"])

    refresh = apply_user_claims_to_token_pair(RefreshToken.for_user(credential.user), credential.user)
    return {
        "refresh": str(refresh),
        "access": str(refresh.access_token),
    }


def _get_credential(credential_id: str, required_user=None) -> DeviceCredential:
    try:
        pk = uuid.UUID(str(credential_id))
    except (ValueError, TypeError) as exc:
        raise DeviceCredentialError("invalid_signature", "Invalid device signature.") from exc
    try:
        credential = DeviceCredential.objects.select_related("user").get(pk=pk)
    except DeviceCredential.DoesNotExist as exc:
        raise DeviceCredentialError("invalid_signature", "Invalid device signature.") from exc
    if required_user is not None and credential.user_id != required_user.pk:
        raise DeviceCredentialError("invalid_signature", "Invalid device signature.")
    return credential
