from django.urls import path

from .user_views import ChangePasswordAPIView, LogoutAPIView
from .views import (
    BootstrapAPIView,
    DeviceCredentialChallengeAPIView,
    DeviceCredentialEnrollAPIView,
    DeviceCredentialLoginAPIView,
    DeviceCredentialRevokeAPIView,
    LoginAPIView,
    PasswordResetConfirmAPIView,
    PasswordResetRequestAPIView,
    RegisterAPIView,
    ResendVerificationAPIView,
    SessionAPIView,
    TokenRefreshAPIView,
    VerifyEmailAPIView,
    VerifyEmailCodeAPIView,
)

urlpatterns = [
    path("register/", RegisterAPIView.as_view(), name="auth-register"),
    path("login/", LoginAPIView.as_view(), name="auth-login"),
    path("session/", SessionAPIView.as_view(), name="auth-session"),
    path("bootstrap/", BootstrapAPIView.as_view(), name="auth-bootstrap"),
    path("verify-email/", VerifyEmailAPIView.as_view(), name="auth-verify-email"),
    path(
        "verify-email-code/",
        VerifyEmailCodeAPIView.as_view(),
        name="auth-verify-email-code",
    ),
    path(
        "password-reset/request/",
        PasswordResetRequestAPIView.as_view(),
        name="auth-password-reset-request",
    ),
    path(
        "password-reset/confirm/",
        PasswordResetConfirmAPIView.as_view(),
        name="auth-password-reset-confirm",
    ),
    path(
        "resend-verification/",
        ResendVerificationAPIView.as_view(),
        name="auth-resend-verification",
    ),
    path("token/refresh/", TokenRefreshAPIView.as_view(), name="auth-token-refresh"),
    path("change-password/", ChangePasswordAPIView.as_view(), name="auth-change-password"),
    path("logout/", LogoutAPIView.as_view(), name="auth-logout"),
    path(
        "device-credentials/",
        DeviceCredentialEnrollAPIView.as_view(),
        name="auth-device-credential-enroll",
    ),
    path(
        "device-credentials/challenge/",
        DeviceCredentialChallengeAPIView.as_view(),
        name="auth-device-credential-challenge",
    ),
    path(
        "device-credentials/login/",
        DeviceCredentialLoginAPIView.as_view(),
        name="auth-device-credential-login",
    ),
    path(
        "device-credentials/<str:credential_id>/",
        DeviceCredentialRevokeAPIView.as_view(),
        name="auth-device-credential-revoke",
    ),
]
