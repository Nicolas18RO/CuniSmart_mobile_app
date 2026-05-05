"""
Centralized rules for API authentication (JWT login & refresh).

Django admin uses session authentication separately; these rules apply to JWT endpoints.
"""

from __future__ import annotations

from dataclasses import dataclass

from django.contrib.auth import authenticate
from django.contrib.auth import get_user_model


@dataclass(frozen=True)
class LoginValidationResult:
    """Whether an authenticated user may receive JWTs on the public API."""

    ok: bool
    code: str | None = None
    message: str | None = None


AUTH_ERRORS = {
    "invalid_credentials": "Invalid credentials.",
    "inactive_user": "User account is disabled.",
    "email_not_verified": "Email not verified",
}


def validate_user_login(user) -> LoginValidationResult:
    """
    Validate API login eligibility (active + verified).

    Call only after credentials match a user row. For missing user, callers
    should surface invalid_credentials instead.
    """
    if user is None:
        return LoginValidationResult(
            ok=False,
            code="invalid_credentials",
            message=AUTH_ERRORS["invalid_credentials"],
        )

    if not user.is_active:
        return LoginValidationResult(
            ok=False,
            code="inactive_user",
            message=AUTH_ERRORS["inactive_user"],
        )

    if not user.is_verified:
        return LoginValidationResult(
            ok=False,
            code="email_not_verified",
            message=AUTH_ERRORS["email_not_verified"],
        )

    return LoginValidationResult(ok=True)


@dataclass(frozen=True)
class ApiLoginOutcome:
    success: bool
    user: object | None = None
    code: str | None = None
    message: str | None = None


def authenticate_api_login(request, email: str, password: str) -> ApiLoginOutcome:
    """
    1) Verify password.
    2) Distinguish inactive account vs bad credentials.
    3) Apply validate_user_login (includes is_verified) before any JWT is built.

    Tokens must only be issued after this returns success=True.
    """
    User = get_user_model()
    normalized_email = User.objects.normalize_email((email or "").strip())

    user = authenticate(
        request=request,
        email=normalized_email,
        password=password,
    )

    if user is not None:
        policy = validate_user_login(user)
        if not policy.ok:
            return ApiLoginOutcome(
                success=False,
                code=policy.code,
                message=policy.message,
            )
        return ApiLoginOutcome(success=True, user=user)

    # ModelBackend returns None for inactive users; distinguish from wrong password.
    candidate = User.objects.filter(email__iexact=normalized_email).first()
    if candidate is not None and candidate.check_password(password) and not candidate.is_active:
        return ApiLoginOutcome(
            success=False,
            code="inactive_user",
            message=AUTH_ERRORS["inactive_user"],
        )

    return ApiLoginOutcome(
        success=False,
        code="invalid_credentials",
        message=AUTH_ERRORS["invalid_credentials"],
    )
