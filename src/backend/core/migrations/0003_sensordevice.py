import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("core", "0002_sensor_reading"),
    ]

    operations = [
        migrations.CreateModel(
            name="SensorDevice",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                (
                    "type",
                    models.CharField(
                        choices=[
                            ("temperature", "Temperature"),
                            ("water", "Water"),
                            ("weight_scale", "Weight scale"),
                        ],
                        max_length=20,
                    ),
                ),
                (
                    "location",
                    models.CharField(
                        choices=[
                            ("room", "Room"),
                            ("tank", "Tank"),
                            ("scale", "Scale"),
                        ],
                        max_length=10,
                    ),
                ),
            ],
            options={
                "ordering": ["id"],
            },
        ),
    ]
