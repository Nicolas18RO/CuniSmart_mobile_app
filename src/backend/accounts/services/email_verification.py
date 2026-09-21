"""Signed, time-limited email verification tokens (no extra DB tables)."""

from __future__ import annotations

import logging

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core.signing import BadSignature, SignatureExpired, TimestampSigner

logger = logging.getLogger(__name__)

_SIGN_SALT = "accounts.email_verify"


def sign_verification_token(user) -> str:
    """Return URL-safe token encoding user PK (expires per settings)."""
    signer = TimestampSigner(salt=_SIGN_SALT)
    return signer.sign(str(user.pk))


def verify_token(token: str):
    """
    Validate token and return user if signature and age are valid.
    Does not modify the user.
    """
    User = get_user_model()
    signer = TimestampSigner(salt=_SIGN_SALT)
    max_age = getattr(settings, "EMAIL_VERIFICATION_MAX_AGE_SECONDS", 48 * 3600)
    try:
        raw = signer.unsign(token, max_age=max_age)
    except SignatureExpired:
        logger.info("Email verification token expired")
        return None
    except BadSignature:
        logger.info("Email verification token invalid signature")
        return None

    try:
        uid = int(raw)
    except ValueError:
        return None

    try:
        return User.objects.get(pk=uid)
    except User.DoesNotExist:
        return None
