"""Transactional email sending (verification links)."""

from __future__ import annotations

import logging
from urllib.parse import quote

from django.conf import settings
from django.core.mail import send_mail

logger = logging.getLogger(__name__)


def build_verification_link(token: str) -> str:
    base = getattr(settings, "VERIFICATION_PUBLIC_BASE_URL", "http://127.0.0.1:8000").rstrip(
        "/"
    )
    safe_token = quote(token, safe="")
    return f"{base}/api/auth/verify-email/?token={safe_token}"


def send_verification_email(to_email: str, verification_link: str) -> bool:
    """
    Send verification email. Returns True if Django reports sending succeeded.
    Uses EMAIL_BACKEND from settings (console in dev, SMTP in production).
    """
    subject = getattr(
        settings,
        "VERIFICATION_EMAIL_SUBJECT",
        "Verify your CuniSmart account",
    )
    body = (
        "Welcome to CuniSmart.\n\n"
        "Please confirm your email address by opening this link:\n\n"
        f"{verification_link}\n\n"
        "If you did not register, you can ignore this message.\n"
    )
    from_email = getattr(
        settings,
        "DEFAULT_FROM_EMAIL",
        "webmaster@localhost",
    )
    try:
        sent = send_mail(
            subject,
            body,
            from_email,
            [to_email],
            fail_silently=False,
        )
        ok = sent >= 1
        if not ok:
            logger.warning("send_mail returned 0 messages for %s", to_email)
        return ok
    except Exception:
        logger.exception("Failed to send verification email to %s", to_email)
        return False


def send_user_verification_email(to_email: str, token: str) -> bool:
    """Compose verification URL and send."""
    link = build_verification_link(token)
    return send_verification_email(to_email, link)
