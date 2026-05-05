from django.contrib.auth import get_user_model
from django.conf import settings
from rest_framework import generics, status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from .serializers import (
    CuniSmartTokenRefreshSerializer,
    LoginSerializer,
    RegisterSerializer,
    ResendVerificationSerializer,
    UserSerializer,
)
from .authentication import OptionalJWTAuthentication
from .services.email_delivery import build_verification_link, send_user_verification_email
from .services.email_verification import sign_verification_token, verify_token
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
        token = sign_verification_token(user)
        link = build_verification_link(token)
        print("Sending verification email to:", user.email)
        print("Verification link:", link)
        sent = send_user_verification_email(user.email, token)
        payload = {
            "user": UserSerializer(user).data,
            "detail": "Registration successful. Please verify your email to log in.",
            "verification_email_sent": sent,
        }
        if getattr(settings, "DEBUG", False):
            payload["debug_verification_link"] = link
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

        token = sign_verification_token(user)
        send_user_verification_email(user.email, token)
        return Response(generic_ok, status=status.HTTP_200_OK)
