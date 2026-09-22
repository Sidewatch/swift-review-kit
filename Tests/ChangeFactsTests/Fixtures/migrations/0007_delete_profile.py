from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("accounts", "0006_profile_bio")]

    operations = [
        migrations.RemoveField(model_name="profile", name="bio"),
        migrations.AlterField(model_name="profile", name="age", field=models.CharField(max_length=8)),
        migrations.DeleteModel(name="LegacyProfile"),
        migrations.RunSQL("UPDATE accounts_profile SET plan = 'free'"),
        # migrations.DeleteModel(name="Profile"),  # a comment
    ]
