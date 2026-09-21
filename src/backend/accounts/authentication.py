"""Optional JWT: never raises on invalid/expired token (used for bootstrap / public probes)."""

from __future__ import annotations

from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import AuthenticationFailed, InvalidToken, TokenError


class OptionalJWTAuthentication(JWTAuthentication):
    """Same as JWT auth, but invalid or missing tokens yield anonymous user instead of 401."""

    def authenticate(self, request):
        header = self.get_header(request)
        if header is None:
            return None
        raw = self.get_raw_token(header)
        if raw is None:
            return None
        try:
            validated = self.get_validated_token(raw)
            return self.get_user(validated), validated
        except (InvalidToken, TokenError, AuthenticationFailed):
            return None
