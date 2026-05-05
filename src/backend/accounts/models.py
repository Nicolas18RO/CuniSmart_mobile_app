from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models
from django.utils.translation import gettext_lazy as _


class UserManager(BaseUserManager):
    """Email-based user manager (no username)."""

    use_in_migrations = True

    def _create_user(self, email, password, **extra_fields):
        if not email:
            raise ValueError(_("The email address must be set"))
        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, email, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", False)
        extra_fields.setdefault("is_superuser", False)
        return self._create_user(email, password, **extra_fields)

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("is_verified", True)
        if extra_fields.get("is_staff") is not True:
            raise ValueError(_("Superuser must have is_staff=True."))
        if extra_fields.get("is_superuser") is not True:
            raise ValueError(_("Superuser must have is_superuser=True."))
        return self._create_user(email, password, **extra_fields)


class User(AbstractUser):
    """Custom user: login with email; optional roles for API authorization."""

    class Role(models.TextChoices):
        USER = "user", _("User")
        ADMIN = "admin", _("Admin")

    username = None
    email = models.EmailField(_("email address"), unique=True, db_index=True)
    role = models.CharField(
        max_length=16,
        choices=Role.choices,
        default=Role.USER,
    )
    is_verified = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    display_name = models.CharField(
        _("display name"),
        max_length=150,
        blank=True,
        help_text=_("Optional name shown in the app (no separate username field)."),
    )

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS: list[str] = []

    objects = UserManager()

    class Meta:
        verbose_name = _("user")
        verbose_name_plural = _("users")
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return self.email


class UserSettings(models.Model):
    """Per-user preferences (theme, locale, notifications, future biometric flag)."""

    class Theme(models.TextChoices):
        LIGHT = "light", _("Light")
        DARK = "dark", _("Dark")
        SYSTEM = "system", _("System")

    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name="settings",
    )
    theme = models.CharField(
        max_length=16,
        choices=Theme.choices,
        default=Theme.SYSTEM,
    )
    language = models.CharField(max_length=16, default="en")
    notifications_enabled = models.BooleanField(default=True)
    biometric_enabled = models.BooleanField(default=False)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = _("user settings")
        verbose_name_plural = _("user settings")

    def __str__(self) -> str:
        return f"Settings<{self.user_id}>"
