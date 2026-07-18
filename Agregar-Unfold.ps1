# ============================================================================
#  Agregar-Unfold.ps1
#  Instala y configura django-unfold sobre el proyecto Control-Ingreso
#  que ya fue creado con Crear-ControlIngreso.ps1
# ============================================================================

# ------------------------- CONFIGURACION -----------------------------------
$ProjectPath = "C:\Users\Usuario\Desktop\Control-ingreso"
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

if (-not (Test-Path (Join-Path $ProjectPath "manage.py"))) {
    throw "No se encontro manage.py en '$ProjectPath'. Revisa que $ProjectPath sea la ruta correcta del proyecto ya creado."
}

Set-Location $ProjectPath

# ==============================================================================
Write-Step "Activando entorno virtual"
# ==============================================================================
if (-not (Test-Path ".\venv\Scripts\Activate.ps1")) {
    throw "No se encontro el entorno virtual en $ProjectPath\venv. Corre primero Crear-ControlIngreso.ps1."
}
& ".\venv\Scripts\Activate.ps1"

# ==============================================================================
Write-Step "Instalando django-unfold"
# ==============================================================================
pip install django-unfold

# ==============================================================================
Write-Step "Respaldando settings.py y admin.py"
# ==============================================================================
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$settingsPath = Join-Path $ProjectPath "config\settings.py"
$adminPath = Join-Path $ProjectPath "asistencia\admin.py"

Copy-Item $settingsPath "$settingsPath.$timestamp.bak"
Copy-Item $adminPath "$adminPath.$timestamp.bak"

# ==============================================================================
Write-Step "Agregando 'unfold' a INSTALLED_APPS en settings.py"
# ==============================================================================
$settings = Get-Content $settingsPath -Raw

if ($settings -notmatch "'unfold',") {
    $settings = $settings -replace "'django\.contrib\.admin',", "'unfold',`r`n    'django.contrib.admin',"

    $unfoldConfig = @'

# ---------------- Unfold: configuracion del panel admin ----------------
UNFOLD = {
    "SITE_TITLE": "Control de Ingreso",
    "SITE_HEADER": "Control de Ingreso",
    "SITE_SYMBOL": "badge",
    "SHOW_HISTORY": True,
    "SHOW_VIEW_ON_SITE": True,
}
# --------------------------------------------------------------------------
'@
    $settings += $unfoldConfig
    Write-Utf8NoBom -Path $settingsPath -Content $settings
    Write-Host "settings.py actualizado." -ForegroundColor Green
} else {
    Write-Host "settings.py ya tenia 'unfold' configurado, no se toco." -ForegroundColor Yellow
}

# ==============================================================================
Write-Step "Actualizando asistencia/admin.py para usar Unfold"
# ==============================================================================
$adminContent = Get-Content $adminPath -Raw

if ($adminContent -notmatch "from unfold.admin import ModelAdmin") {
    $adminContent = $adminContent -replace "from django\.contrib import admin", "from django.contrib import admin`r`nfrom unfold.admin import ModelAdmin"
    $adminContent = $adminContent -replace "class TrabajadorAdmin\(admin\.ModelAdmin\):", "class TrabajadorAdmin(ModelAdmin):"
    $adminContent = $adminContent -replace "class RegistroAsistenciaAdmin\(admin\.ModelAdmin\):", "class RegistroAsistenciaAdmin(ModelAdmin):"
    Write-Utf8NoBom -Path $adminPath -Content $adminContent
    Write-Host "admin.py actualizado." -ForegroundColor Green
} else {
    Write-Host "admin.py ya usaba Unfold, no se toco." -ForegroundColor Yellow
}

# ==============================================================================
Write-Step "Verificando el proyecto (manage.py check)"
# ==============================================================================
python manage.py check

# ==============================================================================
Write-Step "Actualizando requirements.txt"
# ==============================================================================
pip freeze | Out-File -FilePath (Join-Path $ProjectPath "requirements.txt") -Encoding utf8

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " LISTO. Unfold instalado y configurado." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Reinicia el servidor para ver los cambios:"
Write-Host "  python manage.py runserver"
Write-Host ""
Write-Host "Luego entra de nuevo a http://127.0.0.1:8000/admin/"
Write-Host ""
