import django.core.validators
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('asistencia', '0001_initial'),
    ]

    operations = [
        migrations.AlterField(
            model_name='trabajador',
            name='dni',
            field=models.CharField(
                blank=True, db_index=True, max_length=15, null=True, unique=True,
                validators=[django.core.validators.RegexValidator(
                    message='El documento debe contener solo numeros (8 a 15 digitos).',
                    regex='^\\d{8,15}$'
                )],
                help_text='Documento de identidad. Se usa para reconocer al trabajador en su siguiente registro.'
            ),
        ),
    ]
