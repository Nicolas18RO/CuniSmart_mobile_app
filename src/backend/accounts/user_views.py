from django.contrib.auth import get_user_model
from rest_framework import generics, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.settings import api_settings as jwt_settings
from rest_framework_simplejwt.tokens import RefreshToken

from .services.user_settings_service import get_or_create_settings
from .user_serializers import (
    BiometricStatusSerializer,
    ChangePasswordSerializer,
    LogoutSerializer,
    MeProfileSerializer,
    UserSettingsSerializer,
)

User = get_user_model()


class MeProfileAPIView(generics.RetrieveUpdateAPIView):
    """GET/PUT/PATCH /api/users/me/ — authenticated user only."""

    serializer_class = MeProfileSerializer
    permission_classes = [IsAuthenticated]
    http_method_names = ["get", "put", "patch", "head", "options"]

    def get_object(self):
        return User.objects.get(pk=self.request.user.pk)

    def put(self, request, *args, **kwargs):
        return self.update(request, *args, partial=True, **kwargs)


class UserSettingsAPIView(generics.RetrieveUpdateAPIView):
    """GET/PUT/PATCH /api/users/settings/."""

    serializer_class = UserSettingsSerializer
    permission_classes = [IsAuthenticated]
    http_method_names = ["get", "put", "patch", "head", "options"]

    def get_object(self):
        return get_or_create_settings(User.objects.get(pk=self.request.user.pk))

    def put(self, request, *args, **kwargs):
        return self.update(request, *args, partial=True, **kwargs)


class BiometricStatusAPIView(generics.RetrieveUpdateAPIView):
    """GET/PUT /api/users/biometric-status/ — server flag only; device auth stays on the client."""

    serializer_class = BiometricStatusSerializer
    permission_classes = [IsAuthenticated]
    http_method_names = ["get", "put", "head", "options"]

    def get_object(self):
        return get_or_create_settings(User.objects.get(pk=self.request.user.pk))

    def put(self, request, *args, **kwargs):
        return self.update(request, *args, partial=True, **kwargs)


class ChangePasswordAPIView(APIView):
    """POST /api/auth/change-password/"""

    permission_classes = [IsAuthenticated]

    def post(self, request, *args, **kwargs):
        serializer = ChangePasswordSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(
            {"detail": "Password changed successfully.", "code": "password_changed"},
            status=status.HTTP_200_OK,
        )


class LogoutAPIView(APIView):
    """POST /api/auth/logout/ — blacklist submitted refresh token (must match access user)."""

    permission_classes = [IsAuthenticated]

    def post(self, request, *args, **kwargs):
        serializer = LogoutSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        refresh_str = serializer.validated_data["refresh"]
        try:
            token = RefreshToken(refresh_str)
        except TokenError:
            return Response(
                {"detail": "Invalid or expired refresh token.", "code": "invalid_token"},
                status=status.HTTP_400_BAD_REQUEST,
            )

        claim_uid = token[jwt_settings.USER_ID_CLAIM]
        field = jwt_settings.USER_ID_FIELD
        owner_uid = getattr(request.user, field)
        if str(owner_uid) != str(claim_uid):
            return Response(
                {"detail": "Refresh token does not belong to the current user.", "code": "token_user_mismatch"},
                status=status.HTTP_403_FORBIDDEN,
            )

        try:
            token.blacklist()
        except TokenError:
            # Idempotent: already blacklisted or invalid for blacklist
            pass

        return Response(status=status.HTTP_204_NO_CONTENT)
