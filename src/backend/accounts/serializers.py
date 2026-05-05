from django.contrib.auth import get_user_model
from django.contrib.auth.models import update_last_login
from rest_framework import serializers
from rest_framework_simplejwt.serializers import (
    TokenObtainPairSerializer,
    TokenRefreshSerializer,
)
from rest_framework_simplejwt.settings import api_settings as jwt_settings
from rest_framework_simplejwt.tokens import AccessToken, RefreshToken

from .services.auth_service import ApiLoginOutcome, authenticate_api_login, validate_user_login
from .services.jwt_claims import (
    apply_user_claims_to_access_token,
    apply_user_claims_to_refresh_only,
    apply_user_claims_to_token_pair,
)

User = get_user_model()


def _raise_api_auth_error(outcome: ApiLoginOutcome) -> None:
    raise serializers.ValidationError(
        {
            "detail": outcome.message,
            "code": outcome.code,
        },
        code=outcome.code,
    )


class UserSerializer(serializers.ModelSerializer):
    """Public representation of the authenticated user."""

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
        read_only_fields = fields


class RegisterSerializer(serializers.ModelSerializer):
    """Registration: email + password; role defaults to user; is_verified False."""

    password = serializers.CharField(write_only=True, min_length=8, style={"input_type": "password"})

    class Meta:
        model = User
        fields = ("email", "password")

    def validate_email(self, value: str) -> str:
        normalized = User.objects.normalize_email(value.strip())
        if User.objects.filter(email__iexact=normalized).exists():
            raise serializers.ValidationError("A user with this email already exists.")
        return normalized

    def create(self, validated_data):
        password = validated_data.pop("password")
        email = validated_data["email"]
        return User.objects.create_user(
            email=email,
            password=password,
            role=User.Role.USER,
            is_verified=False,
            is_active=True,
        )


class LoginSerializer(TokenObtainPairSerializer):
    """
    Order: authenticate → policy (active + verified) → issue JWT.
    No tokens are created until all checks pass.
    """

    def validate(self, attrs):
        request = self.context.get("request")
        email = attrs.get("email")
        password = attrs.get("password")

        outcome = authenticate_api_login(request, email, password)
        if not outcome.success:
            _raise_api_auth_error(outcome)

        user = outcome.user
        self.user = user

        refresh = self.get_token(user)
        data = {
            "refresh": str(refresh),
            "access": str(refresh.access_token),
        }

        if jwt_settings.UPDATE_LAST_LOGIN:
            update_last_login(request, user)

        return data

    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        return apply_user_claims_to_token_pair(token, user)


class CuniSmartTokenRefreshSerializer(TokenRefreshSerializer):
    """Refresh access token only if the user still passes API login policy."""

    def validate(self, attrs):
        refresh_str = attrs["refresh"]
        refresh = RefreshToken(refresh_str)

        uid = refresh[jwt_settings.USER_ID_CLAIM]

        try:
            user = User.objects.get(**{jwt_settings.USER_ID_FIELD: uid})
        except User.DoesNotExist:
            raise serializers.ValidationError(
                {
                    "detail": "Invalid credentials.",
                    "code": "invalid_credentials",
                },
                code="invalid_credentials",
            )

        policy = validate_user_login(user)
        if not policy.ok:
            raise serializers.ValidationError(
                {
                    "detail": policy.message,
                    "code": policy.code,
                },
                code=policy.code,
            )

        data = super().validate(attrs)
        access = AccessToken(data["access"])
        apply_user_claims_to_access_token(access, user)
        data["access"] = str(access)
        if "refresh" in data:
            new_refresh = RefreshToken(data["refresh"])
            apply_user_claims_to_refresh_only(new_refresh, user)
            data["refresh"] = str(new_refresh)
        return data


class ResendVerificationSerializer(serializers.Serializer):
    """Request body for resending verification email."""

    email = serializers.EmailField()
