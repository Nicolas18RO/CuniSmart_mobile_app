"""Invalidate refresh tokens (SimpleJWT blacklist)."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from django.contrib.auth.base_user import AbstractBaseUser


def blacklist_all_refresh_tokens_for_user(user: AbstractBaseUser) -> None:
    """Blacklist every outstanding refresh token for this user (e.g. after password change)."""
    try:
        from rest_framework_simplejwt.token_blacklist.models import (
            BlacklistedToken,
            OutstandingToken,
        )
    except Exception:  # pragma: no cover - blacklist app optional in theory
        return

    for outstanding in OutstandingToken.objects.filter(user=user):
        BlacklistedToken.objects.get_or_create(token=outstanding)
