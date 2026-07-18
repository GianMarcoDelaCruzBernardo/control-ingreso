# ============================================================================
#  Control-Ingreso - Script de creacion de proyecto Django
#  Sistema de control de ingreso/salida de operarios via QR + geolocalizacion
# ============================================================================
#  Que hace este script:
#   1. Crea (o respalda si ya existe) la carpeta del proyecto
#   2. Crea entorno virtual e instala dependencias
#   3. Genera el proyecto Django "config" y la app "asistencia"
#   4. Escribe modelos, formularios, vistas, admin, urls y templates
#   5. Corre migraciones y crea un superusuario
#   6. Deja todo listo para "python manage.py runserver"
# ============================================================================

# ------------------------- CONFIGURACION -----------------------------------
# EDITA ESTOS VALORES ANTES DE EJECUTAR EL SCRIPT
$ProjectPath   = "C:\Users\Usuario\Desktop\Control-ingreso"

# Coordenadas de tu empresa (sacalas de Google Maps: click derecho -> copiar coordenadas)
$CompanyLat    = -8.98445
$CompanyLng    = -78.60684
$RadiusMeters  = 50            # Radio permitido en metros desde la empresa

# Superusuario que se crea automaticamente (CAMBIA LA CLAVE apenas entres)
$SuperuserUser = "admin"
$SuperuserPass = "Admin123!"
$SuperuserMail = "admin@controlingreso.local"
# -----------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Write-Step {
    param([string]$Msg)
    Write-Host ""
    Write-Host ">> $Msg" -ForegroundColor Cyan
}

# ==============================================================================
Write-Step "Verificando ruta del proyecto"
# ==============================================================================
# Nos movemos a una carpeta neutral (fuera de $ProjectPath) para que Windows
# no bloquee el renombrado/creacion de la carpeta si el script se ejecuto
# estando parado dentro de ella.
Set-Location $env:TEMP

$manageExists = Test-Path (Join-Path $ProjectPath "manage.py")

if ($manageExists) {
    # Ya existe un proyecto Django real ahi -> lo respaldamos por seguridad
    $backupPath = "$ProjectPath`_bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Write-Warning "Ya existe un proyecto Django en '$ProjectPath'. Se respalda en: $backupPath"
    try {
        Rename-Item -Path $ProjectPath -NewName (Split-Path $backupPath -Leaf) -ErrorAction Stop
    } catch {
        Write-Host ""
        Write-Host "No se pudo respaldar la carpeta automaticamente porque esta en uso." -ForegroundColor Red
        Write-Host "Cierra cualquier ventana del Explorador de Windows, VSCode, terminal" -ForegroundColor Red
        Write-Host "u otro programa que tenga abierta esa carpeta, y vuelve a ejecutar el script." -ForegroundColor Red
        throw
    }
    New-Item -ItemType Directory -Path $ProjectPath -Force | Out-Null
} elseif (-not (Test-Path $ProjectPath)) {
    # No existe todavia -> la creamos
    New-Item -ItemType Directory -Path $ProjectPath -Force | Out-Null
} else {
    # La carpeta existe pero no tiene un proyecto Django (ej: solo tiene este .ps1)
    # -> la usamos tal cual, sin necesidad de respaldo ni renombrado
    Write-Host "La carpeta '$ProjectPath' existe pero no tiene un proyecto Django. Se usara directamente." -ForegroundColor Yellow
}

Set-Location $ProjectPath

# ==============================================================================
Write-Step "Creando entorno virtual e instalando dependencias"
# ==============================================================================
python -m venv venv
if (-not (Test-Path ".\venv\Scripts\Activate.ps1")) {
    throw "No se pudo crear el entorno virtual. Verifica que Python este instalado y en el PATH."
}
& ".\venv\Scripts\Activate.ps1"

python -m pip install --upgrade pip
pip install django "qrcode[pil]" openpyxl pillow

# ==============================================================================
Write-Step "Creando proyecto Django (config) y app (asistencia)"
# ==============================================================================
django-admin startproject config .
python manage.py startapp asistencia

# ==============================================================================
Write-Step "Configurando settings.py"
# ==============================================================================
$settingsPath = Join-Path $ProjectPath "config\settings.py"
$settings = Get-Content $settingsPath -Raw

$settings = $settings -replace "'django.contrib.staticfiles',", "'django.contrib.staticfiles',`r`n    'asistencia',"
$settings = $settings -replace "'DIRS': \[\],", "'DIRS': [BASE_DIR / 'templates'],"
$settings = $settings -replace "LANGUAGE_CODE = 'en-us'", "LANGUAGE_CODE = 'es-pe'"
$settings = $settings -replace "TIME_ZONE = 'UTC'", "TIME_ZONE = 'America/Lima'"

$customBlock = @"

# ---------------- Control de Ingreso: configuracion propia ----------------
COMPANY_LATITUDE = $CompanyLat
COMPANY_LONGITUDE = $CompanyLng
ALLOWED_RADIUS_METERS = $RadiusMeters
# ----------------------------------------------------------------------------
"@
$settings += $customBlock
Write-Utf8NoBom -Path $settingsPath -Content $settings

# ==============================================================================
Write-Step "Escribiendo config/urls.py"
# ==============================================================================
$projectUrls = @'
from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path('admin/', admin.site.urls),
    path('', include('asistencia.urls')),
]
'@
Write-Utf8NoBom -Path (Join-Path $ProjectPath "config\urls.py") -Content $projectUrls

# ==============================================================================
Write-Step "Escribiendo asistencia/models.py"
# ==============================================================================
$models = @'
from django.db import models
from django.utils import timezone


class Trabajador(models.Model):
    nombres = models.CharField(max_length=100)
    apellidos = models.CharField(max_length=100)
    dni = models.CharField(max_length=15, blank=True, null=True)
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
'@
Write-Utf8NoBom -Path (Join-Path $ProjectPath "asistencia\models.py") -Content $models

# ==============================================================================
Write-Step "Escribiendo asistencia/forms.py"
# ==============================================================================
$forms = @'
from django import forms


class RegistroForm(forms.Form):
    nombres = forms.CharField(
        max_length=100,
        label="Nombres",
        widget=forms.TextInput(attrs={'placeholder': 'Ej: Juan Carlos', 'autofocus': True})
    )
    apellidos = forms.CharField(
        max_length=100,
        label="Apellidos",
        widget=forms.TextInput(attrs={'placeholder': 'Ej: Perez Gomez'})
    )
    dni = forms.CharField(
        max_length=15,
        required=False,
        label="DNI (opcional)",
        widget=forms.TextInput(attrs={'placeholder': 'Opcional por ahora'})
    )
'@
Write-Utf8NoBom -Path (Join-Path $ProjectPath "asistencia\forms.py") -Content $forms

# ==============================================================================
Write-Step "Escribiendo asistencia/views.py"
# ==============================================================================
$views = @'
import io
import math

import qrcode
from django.conf import settings
from django.contrib.admin.views.decorators import staff_member_required
from django.http import HttpResponse
from django.shortcuts import render
from django.utils import timezone

from .forms import RegistroForm
from .models import RegistroAsistencia, Trabajador


def calcular_distancia_metros(lat1, lng1, lat2, lng2):
    """Distancia entre dos coordenadas usando la formula de haversine (en metros)."""
    radio_tierra = 6371000
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return 2 * radio_tierra * math.asin(math.sqrt(a))


def registrar(request):
    contexto = {}

    if request.method == 'POST':
        form = RegistroForm(request.POST)
        lat = request.POST.get('lat')
        lng = request.POST.get('lng')

        if not lat or not lng:
            contexto['error'] = (
                "No se pudo obtener tu ubicacion. Activa el GPS/ubicacion "
                "del celular y vuelve a intentar."
            )
            contexto['form'] = form
            return render(request, 'asistencia/registrar.html', contexto)

        try:
            lat = float(lat)
            lng = float(lng)
        except ValueError:
            contexto['error'] = "Ubicacion invalida. Intenta nuevamente."
            contexto['form'] = form
            return render(request, 'asistencia/registrar.html', contexto)

        distancia = calcular_distancia_metros(
            lat, lng, settings.COMPANY_LATITUDE, settings.COMPANY_LONGITUDE
        )

        if distancia > settings.ALLOWED_RADIUS_METERS:
            contexto['error'] = (
                f"No te encuentras dentro del establecimiento (distancia: {int(distancia)}m). "
                "No se puede registrar el ingreso/salida desde fuera de la empresa."
            )
            contexto['form'] = form
            return render(request, 'asistencia/registrar.html', contexto)

        if form.is_valid():
            nombres = form.cleaned_data['nombres'].strip().title()
            apellidos = form.cleaned_data['apellidos'].strip().title()
            dni = (form.cleaned_data.get('dni') or '').strip()

            trabajador, _creado = Trabajador.objects.get_or_create(
                nombres__iexact=nombres,
                apellidos__iexact=apellidos,
                defaults={'nombres': nombres, 'apellidos': apellidos, 'dni': dni or None}
            )
            if dni and not trabajador.dni:
                trabajador.dni = dni
                trabajador.save(update_fields=['dni'])

            hoy = timezone.localdate()
            ahora = timezone.now()

            registro_abierto = RegistroAsistencia.objects.filter(
                trabajador=trabajador, fecha=hoy,
                hora_entrada__isnull=False, hora_salida__isnull=True
            ).first()

            if registro_abierto:
                registro_abierto.hora_salida = ahora
                registro_abierto.lat_salida = lat
                registro_abierto.lng_salida = lng
                registro_abierto.save()
                contexto['mensaje'] = (
                    f"SALIDA registrada correctamente a las "
                    f"{timezone.localtime(ahora).strftime('%H:%M:%S')}"
                )
            else:
                RegistroAsistencia.objects.create(
                    trabajador=trabajador, fecha=hoy, hora_entrada=ahora,
                    lat_entrada=lat, lng_entrada=lng
                )
                contexto['mensaje'] = (
                    f"INGRESO registrado correctamente a las "
                    f"{timezone.localtime(ahora).strftime('%H:%M:%S')}"
                )

            contexto['trabajador'] = trabajador
            return render(request, 'asistencia/resultado.html', contexto)

        contexto['form'] = form
        return render(request, 'asistencia/registrar.html', contexto)

    contexto['form'] = RegistroForm()
    return render(request, 'asistencia/registrar.html', contexto)


@staff_member_required
def qr_view(request):
    return render(request, 'asistencia/qr.html')


@staff_member_required
def qr_image(request):
    url = request.build_absolute_uri('/')
    qr = qrcode.QRCode(version=1, box_size=10, border=4)
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")

    buffer = io.BytesIO()
    img.save(buffer, format='PNG')
    return HttpResponse(buffer.getvalue(), content_type='image/png')
'@
Write-Utf8NoBom -Path (Join-Path $ProjectPath "asistencia\views.py") -Content $views

# ==============================================================================
Write-Step "Escribiendo asistencia/admin.py"
# ==============================================================================
$admin = @'
from django.contrib import admin
from django.http import HttpResponse
from django.utils import timezone
from django.utils.html import format_html

import openpyxl
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

from .models import RegistroAsistencia, Trabajador


@admin.register(Trabajador)
class TrabajadorAdmin(admin.ModelAdmin):
    list_display = ('apellidos', 'nombres', 'dni', 'activo', 'creado')
    list_filter = ('activo',)
    search_fields = ('nombres', 'apellidos', 'dni')


def exportar_excel(modeladmin, request, queryset):
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "Control de Ingreso"

    headers = ['Apellidos', 'Nombres', 'DNI', 'Fecha', 'Hora Entrada', 'Hora Salida', 'Horas Trabajadas', 'Estado']

    header_fill = PatternFill(start_color="1F4E78", end_color="1F4E78", fill_type="solid")
    header_font = Font(color="FFFFFF", bold=True, size=11)
    thin_border = Border(
        left=Side(style='thin'), right=Side(style='thin'),
        top=Side(style='thin'), bottom=Side(style='thin')
    )
    center = Alignment(horizontal='center', vertical='center')

    ws.append(['CONTROL DE INGRESO Y SALIDA DE PERSONAL'])
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=len(headers))
    ws['A1'].font = Font(bold=True, size=14, color="1F4E78")
    ws['A1'].alignment = center

    ws.append([f"Generado el: {timezone.localtime(timezone.now()).strftime('%d/%m/%Y %H:%M:%S')}"])
    ws.merge_cells(start_row=2, start_column=1, end_row=2, end_column=len(headers))
    ws['A2'].font = Font(italic=True, size=9, color="666666")
    ws['A2'].alignment = center

    ws.append([])

    header_row_idx = 4
    ws.append(headers)
    for col_num in range(1, len(headers) + 1):
        cell = ws.cell(row=header_row_idx, column=col_num)
        cell.fill = header_fill
        cell.font = header_font
        cell.alignment = center
        cell.border = thin_border

    row_idx = header_row_idx + 1
    for registro in queryset.select_related('trabajador').order_by('-fecha', 'trabajador__apellidos'):
        hora_entrada = timezone.localtime(registro.hora_entrada).strftime('%H:%M:%S') if registro.hora_entrada else '-'
        hora_salida = timezone.localtime(registro.hora_salida).strftime('%H:%M:%S') if registro.hora_salida else '-'
        fila = [
            registro.trabajador.apellidos,
            registro.trabajador.nombres,
            registro.trabajador.dni or '-',
            registro.fecha.strftime('%d/%m/%Y'),
            hora_entrada,
            hora_salida,
            registro.horas_trabajadas,
            registro.estado,
        ]
        ws.append(fila)
        for col_num in range(1, len(headers) + 1):
            cell = ws.cell(row=row_idx, column=col_num)
            cell.border = thin_border
            cell.alignment = center
            if registro.estado == 'EN CURSO':
                cell.fill = PatternFill(start_color="FFF2CC", end_color="FFF2CC", fill_type="solid")
        row_idx += 1

    for col_num, header in enumerate(headers, start=1):
        max_length = len(header)
        for row in range(header_row_idx + 1, row_idx):
            value = ws.cell(row=row, column=col_num).value
            if value:
                max_length = max(max_length, len(str(value)))
        ws.column_dimensions[get_column_letter(col_num)].width = max_length + 4

    ws.freeze_panes = f"A{header_row_idx + 1}"
    ws.auto_filter.ref = f"A{header_row_idx}:{get_column_letter(len(headers))}{header_row_idx}"

    response = HttpResponse(
        content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    )
    filename = f"control_ingreso_{timezone.localtime(timezone.now()).strftime('%Y%m%d_%H%M%S')}.xlsx"
    response['Content-Disposition'] = f'attachment; filename="{filename}"'
    wb.save(response)
    return response


exportar_excel.short_description = "Exportar seleccionados a Excel (profesional)"


@admin.register(RegistroAsistencia)
class RegistroAsistenciaAdmin(admin.ModelAdmin):
    list_display = (
        'trabajador', 'fecha', 'hora_entrada_local',
        'hora_salida_local', 'horas_trabajadas', 'estado_coloreado'
    )
    list_filter = ('fecha',)
    search_fields = ('trabajador__nombres', 'trabajador__apellidos', 'trabajador__dni')
    date_hierarchy = 'fecha'
    actions = [exportar_excel]

    def hora_entrada_local(self, obj):
        return timezone.localtime(obj.hora_entrada).strftime('%H:%M:%S') if obj.hora_entrada else '-'
    hora_entrada_local.short_description = 'Hora Entrada'

    def hora_salida_local(self, obj):
        return timezone.localtime(obj.hora_salida).strftime('%H:%M:%S') if obj.hora_salida else '-'
    hora_salida_local.short_description = 'Hora Salida'

    def estado_coloreado(self, obj):
        colores = {'EN CURSO': 'orange', 'COMPLETADO': 'green', 'SIN INGRESO': 'red'}
        color = colores.get(obj.estado, 'black')
        return format_html('<strong style="color: {};">{}</strong>', color, obj.estado)
    estado_coloreado.short_description = 'Estado'
'@
Write-Utf8NoBom -Path (Join-Path $ProjectPath "asistencia\admin.py") -Content $admin

# ==============================================================================
Write-Step "Escribiendo asistencia/urls.py"
# ==============================================================================
$appUrls = @'
from django.urls import path

from . import views

urlpatterns = [
    path('', views.registrar, name='registrar'),
    path('qr/', views.qr_view, name='qr_view'),
    path('qr/imagen/', views.qr_image, name='qr_image'),
]
'@
Write-Utf8NoBom -Path (Join-Path $ProjectPath "asistencia\urls.py") -Content $appUrls

# ==============================================================================
Write-Step "Creando carpeta de templates"
# ==============================================================================
New-Item -ItemType Directory -Path (Join-Path $ProjectPath "templates") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $ProjectPath "templates\asistencia") -Force | Out-Null

$baseHtml = @'
{% load static %}
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{% block title %}Control de Ingreso{% endblock %}</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            background: linear-gradient(135deg, #1F4E78, #2c7a9e);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .card {
            background: #fff;
            border-radius: 16px;
            padding: 32px 28px;
            max-width: 420px;
            width: 100%;
            box-shadow: 0 10px 30px rgba(0,0,0,0.25);
            text-align: center;
        }
        h1 { color: #1F4E78; font-size: 22px; margin-bottom: 8px; }
        label { display: block; text-align: left; font-size: 13px; color: #333; margin-bottom: 6px; font-weight: 600; }
        input[type=text] {
            width: 100%; padding: 12px 14px; margin-bottom: 16px;
            border: 1.5px solid #d0d7de; border-radius: 8px; font-size: 15px;
        }
        input[type=text]:focus { outline: none; border-color: #1F4E78; }
        button {
            width: 100%; padding: 14px; background: #1F4E78; color: #fff;
            border: none; border-radius: 8px; font-size: 16px; font-weight: 600;
            cursor: pointer;
        }
        button:disabled { background: #aaa; cursor: not-allowed; }
        .error {
            background: #fdecea; color: #b3261e; padding: 12px 14px;
            border-radius: 8px; margin-bottom: 18px; font-size: 14px; text-align: left;
        }
        .success {
            background: #e6f4ea; color: #1e7d34; padding: 20px; border-radius: 8px;
            font-size: 17px; font-weight: 600;
        }
        .status-msg { font-size: 13px; color: #888; margin-bottom: 14px; }
    </style>
</head>
<body>
    <div class="card">
        {% block content %}{% endblock %}
    </div>
</body>
</html>
'@
Write-Utf8NoBom -Path (Join-Path $ProjectPath "templates\base.html") -Content $baseHtml

$registrarHtml = @'
{% extends 'base.html' %}
{% block title %}Registro de Ingreso/Salida{% endblock %}
{% block content %}
    <h1>Control de Ingreso</h1>

    {% if error %}
        <div class="error">{{ error }}</div>
    {% endif %}

    <p class="status-msg" id="geo-status">Obteniendo tu ubicacion...</p>

    <form method="post" id="registro-form">
        {% csrf_token %}
        <label for="id_nombres">Nombres</label>
        {{ form.nombres }}
        <label for="id_apellidos">Apellidos</label>
        {{ form.apellidos }}
        <label for="id_dni">DNI (opcional)</label>
        {{ form.dni }}
        <input type="hidden" name="lat" id="id_lat">
        <input type="hidden" name="lng" id="id_lng">
        <button type="submit" id="submit-btn" disabled>Obteniendo ubicacion...</button>
    </form>

    <script>
        var status = document.getElementById('geo-status');
        var btn = document.getElementById('submit-btn');
        var latInput = document.getElementById('id_lat');
        var lngInput = document.getElementById('id_lng');

        if (!navigator.geolocation) {
            status.textContent = 'Tu dispositivo no soporta geolocalizacion.';
        } else {
            navigator.geolocation.getCurrentPosition(
                function (pos) {
                    latInput.value = pos.coords.latitude;
                    lngInput.value = pos.coords.longitude;
                    status.textContent = 'Ubicacion obtenida correctamente.';
                    btn.disabled = false;
                    btn.textContent = 'Registrar';
                },
                function (err) {
                    status.textContent = 'No se pudo obtener tu ubicacion. Activa el GPS y recarga la pagina.';
                },
                { enableHighAccuracy: true, timeout: 10000 }
            );
        }
    </script>
{% endblock %}
'@
Write-Utf8NoBom -Path (Join-Path $ProjectPath "templates\asistencia\registrar.html") -Content $registrarHtml

$resultadoHtml = @'
{% extends 'base.html' %}
{% block title %}Registro exitoso{% endblock %}
{% block content %}
    <h1>{{ trabajador.nombre_completo }}</h1>
    <div class="success">{{ mensaje }}</div>
    <p class="status-msg" style="margin-top:18px;">Puedes cerrar esta ventana.</p>
{% endblock %}
'@
Write-Utf8NoBom -Path (Join-Path $ProjectPath "templates\asistencia\resultado.html") -Content $resultadoHtml

$qrHtml = @'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>QR Control de Ingreso</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 40px; }
        img { border: 4px solid #1F4E78; padding: 10px; }
        h1 { color: #1F4E78; }
        @media print { .no-print { display: none; } }
    </style>
</head>
<body>
    <h1>Escanea para registrar tu ingreso/salida</h1>
    <img src="{% url 'qr_image' %}" alt="QR Control de Ingreso" width="350">
    <p class="no-print">Imprime esta pagina y pegala en la puerta de ingreso.</p>
</body>
</html>
'@
Write-Utf8NoBom -Path (Join-Path $ProjectPath "templates\asistencia\qr.html") -Content $qrHtml

# ==============================================================================
Write-Step "Creando .gitignore"
# ==============================================================================
$gitignore = @'
venv/
__pycache__/
*.pyc
db.sqlite3
.env
'@
Write-Utf8NoBom -Path (Join-Path $ProjectPath ".gitignore") -Content $gitignore

# ==============================================================================
Write-Step "Generando migraciones y aplicandolas"
# ==============================================================================
python manage.py makemigrations asistencia
python manage.py migrate

# ==============================================================================
Write-Step "Creando superusuario ($SuperuserUser)"
# ==============================================================================
$env:DJANGO_SUPERUSER_USERNAME = $SuperuserUser
$env:DJANGO_SUPERUSER_PASSWORD = $SuperuserPass
$env:DJANGO_SUPERUSER_EMAIL = $SuperuserMail
python manage.py createsuperuser --noinput
Remove-Item Env:\DJANGO_SUPERUSER_USERNAME, Env:\DJANGO_SUPERUSER_PASSWORD, Env:\DJANGO_SUPERUSER_EMAIL

# ==============================================================================
Write-Step "Verificando el proyecto (manage.py check)"
# ==============================================================================
python manage.py check

# ==============================================================================
Write-Step "Congelando dependencias en requirements.txt"
# ==============================================================================
pip freeze | Out-File -FilePath (Join-Path $ProjectPath "requirements.txt") -Encoding utf8

# ==============================================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " LISTO. Proyecto creado en: $ProjectPath" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
if ($CompanyLat -eq 0 -and $CompanyLng -eq 0) {
    Write-Warning "COMPANY_LATITUDE / COMPANY_LONGITUDE siguen en 0,0. Edita config\settings.py con las coordenadas reales de tu empresa antes de usarlo, o vuelve a correr el script cambiando las variables del inicio."
}
Write-Host "Para levantar el servidor:"
Write-Host "  cd `"$ProjectPath`""
Write-Host "  .\venv\Scripts\Activate.ps1"
Write-Host "  python manage.py runserver"
Write-Host ""
Write-Host "URLs:"
Write-Host "  Formulario de ingreso/salida : http://127.0.0.1:8000/"
Write-Host "  QR para imprimir (staff)      : http://127.0.0.1:8000/qr/"
Write-Host "  Panel admin                   : http://127.0.0.1:8000/admin/"
Write-Host "  Usuario admin                 : $SuperuserUser / $SuperuserPass (cambia la clave)"
Write-Host ""
