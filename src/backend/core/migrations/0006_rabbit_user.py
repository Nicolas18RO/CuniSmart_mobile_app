import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


# Confirmed 2026-09-21: assign pre-ownership dev animals to the workspace owner.
# Do not change this email without an explicit new decision.
CONFIRMED_OWNER_EMAIL = "nicorodrigueopayome@gmail.com"


class UnownedRabbitMigrationError(RuntimeError):
    """Raised when unowned Rabbit rows cannot be assigned to the confirmed user."""


def assign_unowned_rabbits_to_confirmed_user(apps, schema_editor):
    Rabbit = apps.get_model("core", "Rabbit")
    User = apps.get_model("accounts", "User")
    unowned = Rabbit.objects.filter(user__isnull=True)
    if not unowned.exists():
        return
    owner = User.objects.filter(email__iexact=CONFIRMED_OWNER_EMAIL).first()
    if owner is None:
        raise UnownedRabbitMigrationError(
            f"R2.1 blocked: {unowned.count()} Rabbit row(s) have no owner and "
            f"{CONFIRMED_OWNER_EMAIL!r} does not exist."
        )
    unowned.update(user_id=owner.pk)


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("core", "0005_backfill_sensor_device_required"),
    ]

    operations = [
        migrations.AddField(
            model_name="rabbit",
            name="user",
            field=models.ForeignKey(
                null=True,
                on_delete=django.db.models.deletion.CASCADE,
                related_name="rabbits",
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        migrations.RunPython(
            assign_unowned_rabbits_to_confirmed_user,
            migrations.RunPython.noop,
        ),
        migrations.AlterField(
            model_name="rabbit",
            name="user",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.CASCADE,
                related_name="rabbits",
                to=settings.AUTH_USER_MODEL,
            ),
        ),
    ]
