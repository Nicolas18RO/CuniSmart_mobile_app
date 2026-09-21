"""One-time 6-digit email verification codes (hashed at rest)."""

from __future__ import annotations

import hashlib
import logging
import secrets
from datetime import timedelta

from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils import timezone

from accounts.models import EmailVerificationCode

logger = logging.getLogger(__name__)

User = get_user_model()


class EmailVerificationError(Exception):
    """Raised when a verification code cannot be applied."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def hash_verification_code(user_id: int, raw: str) -> str:
    normalized = (raw or "").strip()
    return hashlib.sha256(f"{user_id}:{normalized}".encode("utf-8")).hexdigest()


def issue_email_verification_code(user) -> str:
    """Create a fresh 6-digit code, invalidate previous unused codes, return the raw value."""
    raw = f"{secrets.randbelow(1_000_000):06d}"
    digest = hash_verification_code(user.pk, raw)
    max_age = int(getattr(settings, "EMAIL_VERIFICATION_CODE_MAX_AGE_SECONDS", 600))
    now = timezone.now()

    with transaction.atomic():
        EmailVerificationCode.objects.filter(user=user, used_at__isnull=True).update(
            used_at=now
        )
        EmailVerificationCode.objects.create(
            user=user,
            code_hash=digest,
            expires_at=now + timedelta(seconds=max_age),
        )

    logger.info("Issued email verification code for user id %s", user.pk)
    return raw


def confirm_email_verification_code(*, email: str, code: str) -> None:
    """Mark the user verified when the code is valid, unused, and unexpired."""
    normalized_email = User.objects.normalize_email((email or "").strip())
    raw_code = (code or "").strip()
    if not raw_code.isdigit() or len(raw_code) != 6:
        raise EmailVerificationError("verification_code_invalid")

    user = User.objects.filter(email__iexact=normalized_email).first()
    if user is None:
        raise EmailVerificationError("verification_code_invalid")

    digest = hash_verification_code(user.pk, raw_code)
    now = timezone.now()
    with transaction.atomic():
        row = (
            EmailVerificationCode.objects.select_for_update()
            .filter(user=user, code_hash=digest)
            .order_by("-created_at")
            .first()
        )
        if row is None or row.used_at is not None:
            raise EmailVerificationError("verification_code_invalid")
        if row.expires_at <= now:
            raise EmailVerificationError("verification_code_expired")

        user.is_verified = True
        user.save(update_fields=["is_verified"])
        row.used_at = now
        row.save(update_fields=["used_at"])
