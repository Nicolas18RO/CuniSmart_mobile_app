from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("core", "0008_parent_link")]

    operations = [
        migrations.AddField(
            model_name="rabbit",
            name="genealogy_knowledge",
            field=models.CharField(
                choices=[("UNKNOWN", "Unknown"), ("FOUNDER", "Declared founder"),
                         ("RECORDED", "Both parents recorded")],
                default="UNKNOWN", max_length=8,
            ),
        ),
    ]
