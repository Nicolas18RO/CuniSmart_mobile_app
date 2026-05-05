from django.urls import path

from .user_views import ChangePasswordAPIView, LogoutAPIView
from .views import (
    BootstrapAPIView,
    LoginAPIView,
    RegisterAPIView,
    ResendVerificationAPIView,
    SessionAPIView,
    TokenRefreshAPIView,
    VerifyEmailAPIView,
)

urlpatterns = [
    path("register/", RegisterAPIView.as_view(), name="auth-register"),
    path("login/", LoginAPIView.as_view(), name="auth-login"),
    path("session/", SessionAPIView.as_view(), name="auth-session"),
    path("bootstrap/", BootstrapAPIView.as_view(), name="auth-bootstrap"),
    path("verify-email/", VerifyEmailAPIView.as_view(), name="auth-verify-email"),
    path(
        "resend-verification/",
        ResendVerificationAPIView.as_view(),
        name="auth-resend-verification",
    ),
    path("token/refresh/", TokenRefreshAPIView.as_view(), name="auth-token-refresh"),
    path("change-password/", ChangePasswordAPIView.as_view(), name="auth-change-password"),
    path("logout/", LogoutAPIView.as_view(), name="auth-logout"),
]
