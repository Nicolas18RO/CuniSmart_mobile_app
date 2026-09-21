from django.contrib.auth import get_user_model
from rest_framework import serializers

from .models import UserSettings
from .services.profile_service import apply_me_profile_update, apply_new_password
from .services.user_settings_service import apply_settings_update

User = get_user_model()


class MeProfileSerializer(serializers.ModelSerializer):
    """GET/PUT/PATCH /api/users/me/ — only the authenticated user's own row."""

    class Meta:
        model = User
        fields = (
            "id",
            "email",
            "display_name",
            "role",
            "is_verified",
            "is_active",
            "created_at",
        )
        read_only_fields = ("id", "role", "is_verified", "is_active", "created_at")

    def validate_email(self, value: str) -> str:
        normalized = User.objects.normalize_email(value.strip())
        request = self.context.get("request")
        user = request.user if request else None
        if user and User.objects.filter(email__iexact=normalized).exclude(pk=user.pk).exists():
            raise serializers.ValidationError("A user with this email already exists.")
        return normalized

    def update(self, instance, validated_data):
        try:
            return apply_me_profile_update(instance, validated_data)
        except ValueError as exc:
            if str(exc) == "email_taken":
                raise serializers.ValidationError(
                    {"email": "A user with this email already exists."}
                ) from exc
            raise


class UserSettingsSerializer(serializers.ModelSerializer):
    """GET/PUT/PATCH /api/users/settings/."""

    class Meta:
        model = UserSettings
        fields = (
            "theme",
            "language",
            "notifications_enabled",
            "biometric_enabled",
            "updated_at",
        )
        read_only_fields = ("updated_at",)

    def validate_language(self, value: str) -> str:
        v = (value or "").strip()[:16]
        if not v:
            raise serializers.ValidationError("Language cannot be empty.")
        return v

    def update(self, instance, validated_data):
        return apply_settings_update(instance, validated_data)


class ChangePasswordSerializer(serializers.Serializer):
    old_password = serializers.CharField(write_only=True, style={"input_type": "password"})
    new_password = serializers.CharField(
        write_only=True, min_length=8, style={"input_type": "password"}
    )

    def validate(self, attrs):
        user = self.context["request"].user
        if not user.check_password(attrs["old_password"]):
            raise serializers.ValidationError(
                {
                    "detail": "Current password is incorrect.",
                    "code": "invalid_old_password",
                },
                code="invalid_old_password",
            )
        return attrs

    def save(self, **kwargs):
        user = self.context["request"].user
        apply_new_password(user, self.validated_data["new_password"])


class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField(write_only=True)


class BiometricStatusSerializer(serializers.ModelSerializer):
    """GET/PUT /api/users/biometric-status/ — toggles only UserSettings.biometric_enabled."""

    class Meta:
        model = UserSettings
        fields = ("biometric_enabled",)

    def update(self, instance, validated_data):
        return apply_settings_update(instance, validated_data)
