"""
UI-oriented JWT claims (not used for authorization). Biometric state reflects UserSettings only.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from rest_framework_simplejwt.tokens import AccessToken, RefreshToken

from .user_settings_service import get_or_create_settings

if TYPE_CHECKING:
    from django.contrib.auth.base_user import AbstractBaseUser


def _user_jwt_claims(user: AbstractBaseUser) -> dict[str, Any]:
    settings_obj = get_or_create_settings(user)
    return {
        "role": user.role,
        "email": user.email,
        "display_name": getattr(user, "display_name", "") or "",
        "biometric_enabled": bool(settings_obj.biometric_enabled),
    }


def apply_user_claims_to_token_pair(refresh: RefreshToken, user: AbstractBaseUser) -> RefreshToken:
    """Attach claims to refresh token and its access child (login / new pair)."""
    claims = _user_jwt_claims(user)
    for key, value in claims.items():
        refresh[key] = value
        refresh.access_token[key] = value
    return refresh


def apply_user_claims_to_access_token(access: AccessToken, user: AbstractBaseUser) -> None:
    """Refresh flow: enrich newly issued access token from DB (biometric flag may have changed)."""
    claims = _user_jwt_claims(user)
    for key, value in claims.items():
        access[key] = value


def apply_user_claims_to_refresh_only(refresh: RefreshToken, user: AbstractBaseUser) -> RefreshToken:
    """When refresh rotation returns a new refresh string, add UI claims without touching its access child."""
    claims = _user_jwt_claims(user)
    for key, value in claims.items():
        refresh[key] = value
    return refresh
