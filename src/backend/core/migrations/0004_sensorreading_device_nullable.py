import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0003_sensordevice"),
    ]

    operations = [
        migrations.AddField(
            model_name="sensorreading",
            name="sensor_device",
            field=models.ForeignKey(
                null=True,
                on_delete=django.db.models.deletion.CASCADE,
                related_name="readings",
                to="core.sensordevice",
            ),
        ),
        migrations.AlterField(
            model_name="sensorreading",
            name="rabbit",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="sensor_readings",
                to="core.rabbit",
            ),
        ),
        migrations.AlterField(
            model_name="sensorreading",
            name="temperature",
            field=models.FloatField(blank=True, null=True),
        ),
        migrations.AlterField(
            model_name="sensorreading",
            name="weight",
            field=models.FloatField(blank=True, null=True),
        ),
        migrations.AlterField(
            model_name="sensorreading",
            name="water_level",
            field=models.FloatField(blank=True, null=True),
        ),
    ]
