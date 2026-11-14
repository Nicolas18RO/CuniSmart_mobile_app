from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("core", "0013_r3_read_snapshots")]

    operations = [
        migrations.AlterField(
            model_name="syncoperationreceipt",
            name="action",
            field=models.CharField(max_length=16),
        ),
    ]
