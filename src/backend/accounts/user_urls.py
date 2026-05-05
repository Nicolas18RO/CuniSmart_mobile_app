from django.urls import path

from .user_views import BiometricStatusAPIView, MeProfileAPIView, UserSettingsAPIView

urlpatterns = [
    path("me/", MeProfileAPIView.as_view(), name="users-me"),
    path("settings/", UserSettingsAPIView.as_view(), name="users-settings"),
    path(
        "biometric-status/",
        BiometricStatusAPIView.as_view(),
        name="users-biometric-status",
    ),
]
