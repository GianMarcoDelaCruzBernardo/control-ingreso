from django.core.validators import RegexValidator
from django.db import models
from django.utils import timezone

validar_dni = RegexValidator(
    regex=r'^\d{8,15}$',
    message='El documento debe contener solo numeros (8 a 15 digitos).'
)


class Trabajador(models.Model):
    dni = models.CharField(
        max_length=15,
        unique=True,
        db_index=True,
        null=True,
        blank=True,
        validators=[validar_dni],
        help_text='Documento de identidad. Se usa para reconocer al trabajador en su siguiente registro.'
    )
    nombres = models.CharField(max_length=100)
    apellidos = models.CharField(max_length=100)
    activo = models.BooleanField(default=True)
    creado = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['apellidos', 'nombres']

    def __str__(self):
        return f"{self.apellidos}, {self.nombres}"

    @property
    def nombre_completo(self):
        return f"{self.nombres} {self.apellidos}"


class RegistroAsistencia(models.Model):
    trabajador = models.ForeignKey(Trabajador, on_delete=models.CASCADE, related_name='registros')
    fecha = models.DateField(default=timezone.localdate)
    hora_entrada = models.DateTimeField(null=True, blank=True)
    hora_salida = models.DateTimeField(null=True, blank=True)
    lat_entrada = models.FloatField(null=True, blank=True)
    lng_entrada = models.FloatField(null=True, blank=True)
    lat_salida = models.FloatField(null=True, blank=True)
    lng_salida = models.FloatField(null=True, blank=True)

    class Meta:
        ordering = ['-fecha', '-hora_entrada']
        verbose_name = 'Registro de asistencia'
        verbose_name_plural = 'Registros de asistencia'

    def __str__(self):
        return f"{self.trabajador} - {self.fecha}"

    @property
    def horas_trabajadas(self):
        if self.hora_entrada and self.hora_salida:
            delta = self.hora_salida - self.hora_entrada
            total_seconds = delta.total_seconds()
            horas = int(total_seconds // 3600)
            minutos = int((total_seconds % 3600) // 60)
            return f"{horas}h {minutos}m"
        return "-"

    @property
    def estado(self):
        if self.hora_entrada and not self.hora_salida:
            return "EN CURSO"
        elif self.hora_entrada and self.hora_salida:
            return "COMPLETADO"
        return "SIN INGRESO"
