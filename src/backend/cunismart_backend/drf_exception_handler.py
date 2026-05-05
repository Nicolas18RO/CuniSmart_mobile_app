"""
Normalize API errors to { "detail", "code" } for consistent Flutter handling.

Preserves responses that already include both keys (e.g. login / refresh policy errors).
"""

from __future__ import annotations

from typing import Any

from rest_framework import status
from rest_framework.exceptions import (
    AuthenticationFailed,
    ErrorDetail,
    NotAuthenticated,
    NotFound,
    PermissionDenied,
    Throttled,
    ValidationError as DRFValidationError,
)
from rest_framework.views import exception_handler as drf_exception_handler


def _detail_to_str(detail: Any) -> str:
    if detail is None:
        return "An error occurred."
    if isinstance(detail, ErrorDetail):
        return str(detail)
    if isinstance(detail, list):
        if not detail:
            return "An error occurred."
        return _detail_to_str(detail[0])
    if isinstance(detail, dict):
        for v in detail.values():
            return _detail_to_str(v)
        return "Validation failed."
    return str(detail)


def _validation_detail_string(data: dict[str, Any]) -> str:
    if "detail" in data:
        return _detail_to_str(data["detail"])
    parts: list[str] = []
    for key, val in data.items():
        if key == "code":
            continue
        msg = _detail_to_str(val)
        parts.append(f"{key}: {msg}" if key != "non_field_errors" else msg)
    return "; ".join(parts) if parts else "Validation failed."


def cunismart_exception_handler(exc: Exception, context: dict) -> Any:
    response = drf_exception_handler(exc, context)
    if response is None:
        return None

    data = response.data

    if isinstance(data, dict) and "detail" in data and "code" in data:
        response.data = {
            "detail": _detail_to_str(data["detail"]),
            "code": str(data["code"]),
        }
        return response

    if isinstance(exc, NotAuthenticated):
        response.data = {
            "detail": _detail_to_str(
                getattr(exc, "detail", "Authentication credentials were not provided.")
            ),
            "code": "unauthorized",
        }
        return response

    if isinstance(exc, AuthenticationFailed):
        response.data = {
            "detail": _detail_to_str(getattr(exc, "detail", "Authentication failed.")),
            "code": "unauthorized",
        }
        return response

    if isinstance(exc, PermissionDenied):
        response.data = {
            "detail": _detail_to_str(
                getattr(exc, "detail", "You do not have permission to perform this action.")
            ),
            "code": "unauthorized",
        }
        return response

    if isinstance(exc, NotFound):
        response.data = {
            "detail": "Not found.",
            "code": "validation_error",
        }
        return response

    if isinstance(exc, Throttled):
        response.data = {
            "detail": _detail_to_str(getattr(exc, "detail", "Request was throttled.")),
            "code": "validation_error",
        }
        return response

    if isinstance(exc, DRFValidationError):
        if isinstance(data, dict):
            detail_msg = _validation_detail_string(data)
        else:
            detail_msg = _detail_to_str(data)
        response.data = {
            "detail": detail_msg,
            "code": "validation_error",
        }
        return response

    if response.status_code == status.HTTP_401_UNAUTHORIZED:
        response.data = {
            "detail": _detail_to_str(
                data.get("detail", data) if isinstance(data, dict) else data
            ),
            "code": "unauthorized",
        }
        return response

    if response.status_code == status.HTTP_403_FORBIDDEN:
        response.data = {
            "detail": _detail_to_str(
                data.get("detail", data) if isinstance(data, dict) else data
            ),
            "code": "unauthorized",
        }
        return response

    if response.status_code == status.HTTP_400_BAD_REQUEST:
        if isinstance(data, dict):
            detail_msg = _validation_detail_string(data)
        else:
            detail_msg = _detail_to_str(data)
        response.data = {
            "detail": detail_msg,
            "code": "validation_error",
        }
        return response

    if isinstance(data, dict) and "detail" in data:
        response.data = {
            "detail": _detail_to_str(data["detail"]),
            "code": "validation_error",
        }
        return response

    response.data = {
        "detail": _detail_to_str(data),
        "code": "validation_error",
    }
    return response
