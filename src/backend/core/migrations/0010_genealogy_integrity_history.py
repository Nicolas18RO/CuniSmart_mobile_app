import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("core", "0009_rabbit_genealogy_knowledge")]
    operations = [
        migrations.CreateModel(name="GenealogyTransition", fields=[
            ("id", models.BigAutoField(primary_key=True, serialize=False, auto_created=True, verbose_name="ID")),
            ("previous", models.CharField(max_length=8)),
            ("current", models.CharField(max_length=8)),
            ("created_at", models.DateTimeField(auto_now_add=True)),
            ("rabbit", models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name="genealogy_transitions", to="core.rabbit")),
        ]),
        migrations.AddConstraint(model_name="parentlink", constraint=models.CheckConstraint(condition=~models.Q(child=models.F("parent")), name="parent_not_self")),
        migrations.AddConstraint(model_name="parentlink", constraint=models.CheckConstraint(condition=models.Q(role__in=["FATHER", "MOTHER"]), name="parent_valid_role")),
        migrations.AddConstraint(model_name="parentlink", constraint=models.CheckConstraint(condition=models.Q(version__gte=1), name="parent_positive_version")),
    ]
