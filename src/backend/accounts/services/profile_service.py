"""Profile updates, password change, and token revocation side effects."""

from __future__ import annotations

from typing import TYPE_CHECKING

from django.contrib.auth import get_user_model

from .email_delivery import send_user_verification_email
from .email_verification import sign_verification_token
from .jwt_revocation import blacklist_all_refresh_tokens_for_user

if TYPE_CHECKING:
    from django.contrib.auth.base_user import AbstractBaseUser

User = get_user_model()


def apply_me_profile_update(user: AbstractBaseUser, validated_data: dict) -> AbstractBaseUser:
    """
    Apply allowed profile fields. Email change resets verification and re-sends link;
    outstanding refresh tokens are blacklisted so the client must obtain new tokens after re-verifying.
    """
    old_email = (user.email or "").lower()
    email_changed = False
    update_fields: list[str] = []

    if "display_name" in validated_data:
        user.display_name = (validated_data.get("display_name") or "").strip()[:150]
        update_fields.append("display_name")

    if "email" in validated_data:
        normalized = User.objects.normalize_email(validated_data["email"].strip())
        if normalized.lower() != old_email:
            if User.objects.filter(email__iexact=normalized).exclude(pk=user.pk).exists():
                raise ValueError("email_taken")
            user.email = normalized
            user.is_verified = False
            update_fields.extend(["email", "is_verified"])
            email_changed = True

    if update_fields:
        user.save(update_fields=update_fields)

    if email_changed:
        blacklist_all_refresh_tokens_for_user(user)
        token = sign_verification_token(user)
        send_user_verification_email(user.email, token)

    return user


def apply_new_password(user: AbstractBaseUser, new_password: str) -> None:
    """Set password and revoke all refresh tokens (caller must verify old password if required)."""
    user.set_password(new_password)
    user.save(update_fields=["password"])
    blacklist_all_refresh_tokens_for_user(user)


def change_password(
    user: AbstractBaseUser,
    *,
    old_password: str,
    new_password: str,
) -> None:
    if not user.check_password(old_password):
        raise ValueError("invalid_old_password")
    apply_new_password(user, new_password)
