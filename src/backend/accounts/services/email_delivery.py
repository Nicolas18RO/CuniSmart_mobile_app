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


def send_user_verification_code_email(to_email: str, code: str) -> bool:
    """Email the 6-digit verification code. Never log the code."""
    subject = getattr(
        settings,
        "VERIFICATION_EMAIL_SUBJECT",
        "Verify your CuniSmart account",
    )
    body = (
        "Bienvenido a CuniSmart.\n\n"
        "Tu código de verificación de 6 dígitos es:\n\n"
        f"Código: {code}\n\n"
        "Caduca en 10 minutos y solo se puede usar una vez.\n"
        "Si no creaste esta cuenta, ignora este mensaje.\n"
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
        logger.exception("Failed to send verification code email to %s", to_email)
        return False


def send_password_reset_email(to_email: str, raw_token: str) -> bool:
    """Email the one-time recovery code. Never log the token."""
    subject = getattr(
        settings,
        "PASSWORD_RESET_EMAIL_SUBJECT",
        "CuniSmart password recovery",
    )
    body = (
        "Recibimos una solicitud para restablecer la contraseña de CuniSmart.\n\n"
        "Tu código de recuperación de 6 dígitos es:\n\n"
        f"Código: {raw_token}\n\n"
        "Caduca en una hora y solo se puede usar una vez.\n"
        "Si no solicitaste este cambio, ignora este mensaje.\n"
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
        return sent >= 1
    except Exception:
        logger.exception("Failed to send password reset email to %s", to_email)
        return False
