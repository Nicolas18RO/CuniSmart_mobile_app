from django.contrib.auth import get_user_model
from rest_framework import generics, status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from .serializers import (
    CuniSmartTokenRefreshSerializer,
    DeviceCredentialChallengeSerializer,
    DeviceCredentialEnrollSerializer,
    DeviceCredentialLoginSerializer,
    LoginSerializer,
    PasswordResetConfirmSerializer,
    PasswordResetRequestSerializer,
    RegisterSerializer,
    ResendVerificationSerializer,
    UserSerializer,
    VerifyEmailCodeSerializer,
)
from .authentication import OptionalJWTAuthentication
from .services.device_credentials import (
    DeviceCredentialError,
    enroll_device_credential,
    issue_device_challenge,
    login_with_device_credential,
    revoke_device_credential,
)
from .services.email_delivery import send_user_verification_code_email
from .services.email_verification import verify_token
from .services.email_verification_code import (
    EmailVerificationError,
    confirm_email_verification_code,
    issue_email_verification_code,
)
from .services.password_reset import (
    GENERIC_CONFIRM_DETAIL,
    GENERIC_REQUEST_DETAIL,
    PasswordResetError,
    confirm_password_reset,
    request_password_reset,
)
from .services.session_service import build_bootstrap_payload, build_session_payload

User = get_user_model()


class RegisterAPIView(generics.CreateAPIView):
    """POST /api/auth/register/ — create account and send verification email."""

    serializer_class = RegisterSerializer
    permission_classes = [AllowAny]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        raw_code = issue_email_verification_code(user)
        sent = send_user_verification_code_email(user.email, raw_code)
        payload = {
            "user": UserSerializer(user).data,
            "detail": "Registration successful. Please verify your email to log in.",
            "verification_email_sent": sent,
        }
        return Response(payload, status=status.HTTP_201_CREATED)


class LoginAPIView(TokenObtainPairView):
    """POST /api/auth/login/ — JWT pair only after auth_service policy passes."""

    serializer_class = LoginSerializer
    permission_classes = [AllowAny]


class TokenRefreshAPIView(TokenRefreshView):
    """POST /api/auth/token/refresh/ — blocked for inactive / unverified users."""

    serializer_class = CuniSmartTokenRefreshSerializer
    permission_classes = [AllowAny]


class SessionAPIView(APIView):
    """GET /api/auth/session/ — unified User + UserSettings from DB (post-login bootstrap)."""

    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        return Response(build_session_payload(request.user))


class BootstrapAPIView(APIView):
    """
    GET /api/auth/bootstrap/ — splash hints. Invalid JWT is ignored (treated as logged out).
    ``biometric_available`` reflects server preference when session is valid; Flutter adds hardware checks.
    """

    authentication_classes = [OptionalJWTAuthentication]
    permission_classes = [AllowAny]

    def get(self, request, *args, **kwargs):
        session_valid = bool(request.user and request.user.is_authenticated)
        user = request.user if session_valid else None
        return Response(build_bootstrap_payload(session_valid=session_valid, user=user))


class VerifyEmailAPIView(APIView):
    """GET /api/auth/verify-email/?token=..."""

    permission_classes = [AllowAny]

    def get(self, request, *args, **kwargs):
        raw = request.query_params.get("token")
        if not raw:
            return Response(
                {
                    "detail": "Query parameter 'token' is required.",
                    "code": "validation_error",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        user = verify_token(raw)
        if user is None:
            return Response(
                {
                    "detail": "Invalid or expired verification token.",
                    "code": "validation_error",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        if user.is_verified:
            return Response(
                {"detail": "Email already verified.", "verified": True},
                status=status.HTTP_200_OK,
            )
        user.is_verified = True
        user.save(update_fields=["is_verified"])
        return Response(
            {
                "detail": "Email verified successfully.",
                "verified": True,
                "user": UserSerializer(user).data,
            },
            status=status.HTTP_200_OK,
        )


class VerifyEmailCodeAPIView(APIView):
    """POST /api/auth/verify-email-code/ — body: {\"email\", \"code\"}"""

    permission_classes = [AllowAny]

    def post(self, request, *args, **kwargs):
        serializer = VerifyEmailCodeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            confirm_email_verification_code(
                email=serializer.validated_data["email"],
                code=serializer.validated_data["code"],
            )
        except EmailVerificationError as exc:
            detail = (
                "Verification code expired."
                if exc.code == "verification_code_expired"
                else "Invalid verification code."
            )
            return Response(
                {"detail": detail, "code": exc.code},
                status=status.HTTP_400_BAD_REQUEST,
            )

        email = User.objects.normalize_email(serializer.validated_data["email"].strip())
        user = User.objects.filter(email__iexact=email).first()
        payload = {
            "detail": "Email verified successfully.",
            "verified": True,
        }
        if user is not None:
            payload["user"] = UserSerializer(user).data
        return Response(payload, status=status.HTTP_200_OK)


class ResendVerificationAPIView(APIView):
    """POST /api/auth/resend-verification/ — body: {\"email\": \"...\"}"""

    permission_classes = [AllowAny]

    def post(self, request, *args, **kwargs):
        serializer = ResendVerificationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        email = User.objects.normalize_email(serializer.validated_data["email"].strip())

        user = User.objects.filter(email__iexact=email).first()

        # Uniform response to reduce email enumeration
        generic_ok = {
            "detail": "If an account exists and requires verification, a message was sent.",
        }

        if user is None or user.is_verified:
            return Response(generic_ok, status=status.HTTP_200_OK)

        raw_code = issue_email_verification_code(user)
        send_user_verification_code_email(user.email, raw_code)
        return Response(generic_ok, status=status.HTTP_200_OK)


class PasswordResetRequestAPIView(APIView):
    """POST /api/auth/password-reset/request/ — body: {\"email\": \"...\"}"""

    permission_classes = [AllowAny]

    def post(self, request, *args, **kwargs):
        serializer = PasswordResetRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        request_password_reset(serializer.validated_data["email"])
        return Response({"detail": GENERIC_REQUEST_DETAIL}, status=status.HTTP_200_OK)


class PasswordResetConfirmAPIView(APIView):
    """POST /api/auth/password-reset/confirm/ — body: {\"email\", \"code\", \"new_password\"}"""

    permission_classes = [AllowAny]

    def post(self, request, *args, **kwargs):
        serializer = PasswordResetConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            confirm_password_reset(
                email=serializer.validated_data["email"],
                code=serializer.validated_data["code"],
                new_password=serializer.validated_data["new_password"],
            )
        except PasswordResetError as exc:
            if exc.code == "too_many_attempts":
                return Response(
                    {
                        "detail": "Too many recovery attempts.",
                        "code": "too_many_attempts",
                    },
                    status=status.HTTP_429_TOO_MANY_REQUESTS,
                )
            if exc.code == "recovery_code_expired":
                return Response(
                    {
                        "detail": "Recovery code expired.",
                        "code": "recovery_code_expired",
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            return Response(
                {
                    "detail": "Invalid recovery code.",
                    "code": "recovery_code_invalid",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        return Response({"detail": GENERIC_CONFIRM_DETAIL}, status=status.HTTP_200_OK)


def _device_credential_error_response(exc: DeviceCredentialError) -> Response:
    return Response(
        {"detail": exc.message, "code": exc.code},
        status=status.HTTP_400_BAD_REQUEST,
    )


class DeviceCredentialEnrollAPIView(APIView):
    """POST /api/auth/device-credentials/ — register a device public key."""

    permission_classes = [IsAuthenticated]

    def post(self, request, *args, **kwargs):
        serializer = DeviceCredentialEnrollSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            credential = enroll_device_credential(
                user=request.user,
                public_key=serializer.validated_data["public_key"],
                device_label=serializer.validated_data.get("device_label") or "",
            )
        except DeviceCredentialError as exc:
            return _device_credential_error_response(exc)
        return Response(
            {
                "id": str(credential.id),
                "created_at": credential.created_at.isoformat(),
            },
            status=status.HTTP_201_CREATED,
        )


class DeviceCredentialChallengeAPIView(APIView):
    """POST /api/auth/device-credentials/challenge/ — one-time nonce."""

    permission_classes = [AllowAny]

    def post(self, request, *args, **kwargs):
        serializer = DeviceCredentialChallengeSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            nonce, challenge = issue_device_challenge(
                credential_id=serializer.validated_data["credential_id"],
            )
        except DeviceCredentialError as exc:
            return _device_credential_error_response(exc)
        return Response(
            {
                "nonce": nonce,
                "expires_at": challenge.expires_at.isoformat(),
            }
        )


class DeviceCredentialLoginAPIView(APIView):
    """POST /api/auth/device-credentials/login/ — signature → same JWT pair as password login."""

    permission_classes = [AllowAny]

    def post(self, request, *args, **kwargs):
        serializer = DeviceCredentialLoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            tokens = login_with_device_credential(
                credential_id=serializer.validated_data["credential_id"],
                nonce=serializer.validated_data["nonce"],
                signature=serializer.validated_data["signature"],
            )
        except DeviceCredentialError as exc:
            return _device_credential_error_response(exc)
        return Response(tokens, status=status.HTTP_200_OK)


class DeviceCredentialRevokeAPIView(APIView):
    """DELETE /api/auth/device-credentials/<id>/ — revoke enrollment for the authenticated user."""

    permission_classes = [IsAuthenticated]

    def delete(self, request, credential_id, *args, **kwargs):
        try:
            revoke_device_credential(user=request.user, credential_id=credential_id)
        except DeviceCredentialError as exc:
            return _device_credential_error_response(exc)
        return Response(status=status.HTTP_204_NO_CONTENT)
