import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0010_genealogy_integrity_history"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]
    operations = [
        migrations.CreateModel(
            name="ReproductiveEvent",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("uuid", models.UUIDField(default=uuid.uuid4, unique=True)),
                ("mating_date", models.DateField()),
                ("estimated_birth_date", models.DateField()),
                ("notes", models.TextField(blank=True)),
                ("version", models.PositiveIntegerField(default=1)),
                ("deleted_at", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("female", models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name="reproductive_events_as_female", to="core.rabbit")),
                ("male", models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name="reproductive_events_as_male", to="core.rabbit")),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="reproductive_events", to=settings.AUTH_USER_MODEL)),
            ],
            options={
                "ordering": ["estimated_birth_date", "uuid"],
                "constraints": [
                    models.CheckConstraint(condition=~models.Q(male=models.F("female")), name="reproductive_distinct_rabbits"),
                    models.CheckConstraint(condition=models.Q(version__gte=1), name="reproductive_positive_version"),
                ],
            },
        ),
    ]
