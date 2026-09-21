"""One-time 6-digit password recovery codes (hashed at rest; not verification codes)."""

from __future__ import annotations

import hashlib
import logging
import secrets
from datetime import timedelta

from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils import timezone

from accounts.models import PasswordResetToken
from .email_delivery import send_password_reset_email
from .profile_service import apply_new_password

logger = logging.getLogger(__name__)

GENERIC_REQUEST_DETAIL = "If an account exists, a recovery message was sent."
GENERIC_CONFIRM_DETAIL = "Password updated. You can sign in with your new password."

User = get_user_model()


class PasswordResetError(Exception):
    """Raised when a recovery code cannot be applied."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def hash_reset_token(user_id: int, raw: str) -> str:
    """Hash with a reset-specific prefix so verification codes cannot match."""
    normalized = (raw or "").strip()
    return hashlib.sha256(f"reset:{user_id}:{normalized}".encode("utf-8")).hexdigest()


def request_password_reset(email: str) -> None:
    """
    Issue a one-time 6-digit code and email it when an active account matches.
    Always silent for unknown / inactive emails (anti-enumeration).
    """
    normalized = User.objects.normalize_email((email or "").strip())
    user = User.objects.filter(email__iexact=normalized, is_active=True).first()
    if user is None:
        return

    raw = f"{secrets.randbelow(1_000_000):06d}"
    digest = hash_reset_token(user.pk, raw)
    max_age = int(getattr(settings, "PASSWORD_RESET_MAX_AGE_SECONDS", 3600))
    now = timezone.now()

    with transaction.atomic():
        PasswordResetToken.objects.filter(user=user, used_at__isnull=True).update(
            used_at=now
        )
        PasswordResetToken.objects.create(
            user=user,
            token_hash=digest,
            expires_at=now + timedelta(seconds=max_age),
        )

    send_password_reset_email(user.email, raw)
    logger.info("Password reset email attempted for user id %s", user.pk)


def confirm_password_reset(*, email: str, code: str, new_password: str) -> None:
    normalized_email = User.objects.normalize_email((email or "").strip())
    raw_code = (code or "").strip()
    if not raw_code.isdigit() or len(raw_code) != 6:
        raise PasswordResetError("recovery_code_invalid")

    user = User.objects.filter(email__iexact=normalized_email, is_active=True).first()
    if user is None:
        raise PasswordResetError("recovery_code_invalid")

    max_attempts = int(getattr(settings, "PASSWORD_RESET_MAX_ATTEMPTS", 5))
    now = timezone.now()
    error_code = None
    with transaction.atomic():
        row = (
            PasswordResetToken.objects.select_for_update()
            .select_related("user")
            .filter(user=user, used_at__isnull=True)
            .order_by("-created_at")
            .first()
        )
        if row is None:
            error_code = "recovery_code_invalid"
        elif row.expires_at <= now:
            error_code = "recovery_code_expired"
        else:
            digest = hash_reset_token(user.pk, raw_code)
            if row.token_hash != digest:
                row.failed_attempts = int(row.failed_attempts or 0) + 1
                if row.failed_attempts >= max_attempts:
                    row.used_at = now
                    row.save(update_fields=["failed_attempts", "used_at"])
                    error_code = "too_many_attempts"
                else:
                    row.save(update_fields=["failed_attempts"])
                    error_code = "recovery_code_invalid"
            else:
                apply_new_password(row.user, new_password)
                row.used_at = now
                row.save(update_fields=["used_at"])

    if error_code:
        raise PasswordResetError(error_code)
