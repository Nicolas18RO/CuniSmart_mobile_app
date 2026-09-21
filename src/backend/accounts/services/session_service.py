"""Unified session payload: always reads current User + UserSettings from the database."""

from __future__ import annotations

from typing import Any, TYPE_CHECKING

from django.contrib.auth import get_user_model

from .user_settings_service import get_or_create_settings

if TYPE_CHECKING:
    from django.contrib.auth.base_user import AbstractBaseUser

User = get_user_model()


def build_session_payload(user: AbstractBaseUser) -> dict[str, Any]:
    """Single source of truth for post-login UX state (no caching)."""
    u = User.objects.get(pk=user.pk)
    s = get_or_create_settings(u)
    return {
        "user": {
            "id": u.id,
            "email": u.email,
            "display_name": u.display_name or "",
            "role": u.role,
            "is_verified": u.is_verified,
        },
        "settings": {
            "theme": s.theme,
            "language": s.language,
            "notifications_enabled": s.notifications_enabled,
            "biometric_enabled": s.biometric_enabled,
        },
    }


def build_bootstrap_payload(*, session_valid: bool, user: AbstractBaseUser | None) -> dict[str, Any]:
    """
    Minimal splash hints. ``biometric_available`` reflects server preference when logged in;
    Flutter must still combine with local_auth for hardware capability.
    """
    biometric_available = False
    if session_valid and user is not None and user.is_authenticated:
        s = get_or_create_settings(User.objects.get(pk=user.pk))
        biometric_available = bool(s.biometric_enabled)

    return {
        "auth_required": not session_valid,
        "biometric_available": biometric_available,
        "session_valid": session_valid,
    }
