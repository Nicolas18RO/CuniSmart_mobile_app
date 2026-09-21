from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as DjangoUserAdmin
from django.utils.translation import gettext_lazy as _

from .models import User, UserSettings


@admin.register(User)
class UserAdmin(DjangoUserAdmin):
    ordering = ("-created_at",)
    list_display = ("email", "role", "is_verified", "is_staff", "is_active", "created_at")
    list_filter = ("role", "is_staff", "is_active", "is_verified")
    search_fields = ("email", "display_name")
    readonly_fields = ("created_at", "last_login", "date_joined")

    fieldsets = (
        (None, {"fields": ("email", "password")}),
        (_("Personal info"), {"fields": ("display_name", "role", "is_verified")}),
        (
            _("Permissions"),
            {
                "fields": (
                    "is_active",
                    "is_staff",
                    "is_superuser",
                    "groups",
                    "user_permissions",
                ),
            },
        ),
        (_("Important dates"), {"fields": ("last_login", "date_joined", "created_at")}),
    )

    add_fieldsets = (
        (
            None,
            {
                "classes": ("wide",),
                "fields": (
                    "email",
                    "password1",
                    "password2",
                    "display_name",
                    "role",
                    "is_staff",
                    "is_superuser",
                ),
            },
        ),
    )


@admin.register(UserSettings)
class UserSettingsAdmin(admin.ModelAdmin):
    list_display = (
        "user",
        "theme",
        "language",
        "notifications_enabled",
        "biometric_enabled",
        "updated_at",
    )
    list_filter = ("theme", "notifications_enabled", "biometric_enabled")
    search_fields = ("user__email",)
    raw_id_fields = ("user",)
