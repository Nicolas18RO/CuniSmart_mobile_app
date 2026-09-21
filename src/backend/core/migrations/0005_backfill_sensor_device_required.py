import django.db.models.deletion
from django.db import migrations, models


def backfill_sensor_device(apps, schema_editor):
    SensorDevice = apps.get_model("core", "SensorDevice")
    SensorReading = apps.get_model("core", "SensorReading")
    qs = SensorReading.objects.filter(sensor_device__isnull=True)
    if not qs.exists():
        return
    device = (
        SensorDevice.objects.filter(type="weight_scale", location="scale")
        .order_by("pk")
        .first()
    )
    if device is None:
        device = SensorDevice.objects.create(type="weight_scale", location="scale")
    qs.update(sensor_device=device)


def noop_reverse(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0004_sensorreading_device_nullable"),
    ]

    operations = [
        migrations.RunPython(backfill_sensor_device, noop_reverse),
        migrations.AlterField(
            model_name="sensorreading",
            name="sensor_device",
            field=models.ForeignKey(
                on_delete=django.db.models.deletion.CASCADE,
                related_name="readings",
                to="core.sensordevice",
            ),
        ),
    ]
