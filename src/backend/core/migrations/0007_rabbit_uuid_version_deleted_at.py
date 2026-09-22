import uuid

from django.db import migrations, models


def fill_rabbit_uuids(apps, schema_editor):
    Rabbit = apps.get_model("core", "Rabbit")
    for rabbit in Rabbit.objects.filter(uuid__isnull=True):
        rabbit.uuid = uuid.uuid4()
        rabbit.save(update_fields=["uuid"])


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0006_rabbit_user"),
    ]

    operations = [
        migrations.AddField(
            model_name="rabbit",
            name="uuid",
            field=models.UUIDField(null=True),
        ),
        migrations.AddField(
            model_name="rabbit",
            name="version",
            field=models.PositiveIntegerField(default=1),
        ),
        migrations.AddField(
            model_name="rabbit",
            name="deleted_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.RunPython(fill_rabbit_uuids, migrations.RunPython.noop),
        migrations.AlterField(
            model_name="rabbit",
            name="uuid",
            field=models.UUIDField(default=uuid.uuid4, unique=True),
        ),
    ]
