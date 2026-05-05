"""UserSettings get/update (no HTTP concerns)."""

from __future__ import annotations

from typing import TYPE_CHECKING

from ..models import UserSettings

if TYPE_CHECKING:
    from django.contrib.auth.base_user import AbstractBaseUser


def get_or_create_settings(user: AbstractBaseUser) -> UserSettings:
    settings, _ = UserSettings.objects.get_or_create(user=user)
    return settings


def apply_settings_update(instance: UserSettings, validated_data: dict) -> UserSettings:
    for key in ("theme", "language", "notifications_enabled", "biometric_enabled"):
        if key in validated_data:
            setattr(instance, key, validated_data[key])
    instance.save()
    return instance
