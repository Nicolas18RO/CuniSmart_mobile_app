from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("accounts", "0004_email_verification_code"),
    ]

    operations = [
        migrations.AlterField(
            model_name="passwordresettoken",
            name="token_hash",
            field=models.CharField(db_index=True, max_length=64),
        ),
        migrations.AddField(
            model_name="passwordresettoken",
            name="failed_attempts",
            field=models.PositiveSmallIntegerField(default=0),
        ),
    ]
