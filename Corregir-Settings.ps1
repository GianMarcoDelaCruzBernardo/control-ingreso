# ============================================================================
#  Corregir-Settings.ps1
#  Corrige settings.py: normaliza CRLF->LF y aplica (si faltan) los bloques
#  de STORAGES (whitenoise) y DATABASES (dj_database_url / Postgres) que el
#  script anterior no logro insertar por un problema de saltos de linea.
# ============================================================================

# ------------------------- CONFIGURACION -----------------------------------
$ProjectPath = "C:\Users\Usuario\Desktop\Control-ingreso"
$RepoUrl     = "https://github.com/GianMarcoDelaCruzBernardo/control-ingreso.git"
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
    throw "No se encontro manage.py en '$ProjectPath'. Revisa la ruta."
}

Set-Location $ProjectPath
if (Test-Path ".\venv\Scripts\Activate.ps1") {
    & ".\venv\Scripts\Activate.ps1"
}

# ==============================================================================
Write-Step "Respaldando settings.py"
# ==============================================================================
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$settingsPath = Join-Path $ProjectPath "config\settings.py"
Copy-Item $settingsPath "$settingsPath.$timestamp.bak"

$settings = Get-Content $settingsPath -Raw

# Normalizamos TODO el archivo a saltos de linea LF. Python/Django no tienen
# ningun problema con LF puro (funciona igual en Windows, y es justo lo que
# Render/Linux espera), asi evitamos el problema de mezclar CRLF y LF.
$settings = $settings -replace "`r`n", "`n"

# ==============================================================================
Write-Step "Verificando/aplicando bloque de DATABASES (Postgres via DATABASE_URL)"
# ==============================================================================
if ($settings -notmatch "dj_database_url\.config") {
    $settings = $settings -replace "(?s)DATABASES = \{.*?\n\}\n", @'
DATABASES = {
    'default': dj_database_url.config(
        default=f'sqlite:///{BASE_DIR / "db.sqlite3"}',
        conn_max_age=600,
    )
}
'@
    Write-Host "Bloque DATABASES corregido." -ForegroundColor Green
} else {
    Write-Host "DATABASES ya estaba correcto." -ForegroundColor Yellow
}

if ($settings -notmatch "import dj_database_url") {
    $settings = $settings -replace "import os", "import os`nimport dj_database_url"
    Write-Host "Import de dj_database_url agregado." -ForegroundColor Green
}

# ==============================================================================
Write-Step "Verificando/aplicando bloque de STORAGES (whitenoise)"
# ==============================================================================
if ($settings -notmatch "STORAGES = \{") {
    $settings = $settings -replace "(?m)^STATIC_URL = 'static/'\s*$", @'
STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'

STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}
'@
    Write-Host "Bloque STORAGES corregido." -ForegroundColor Green
} else {
    Write-Host "STORAGES ya estaba correcto." -ForegroundColor Yellow
}

Write-Utf8NoBom -Path $settingsPath -Content $settings

# ==============================================================================
Write-Step "Verificando el proyecto localmente (manage.py check)"
# ==============================================================================
python manage.py check

# ==============================================================================
Write-Step "Probando collectstatic localmente (para detectar el error antes que Render)"
# ==============================================================================
python manage.py collectstatic --noinput

# ==============================================================================
Write-Step "Subiendo la correccion a GitHub"
# ==============================================================================
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"

git add -A
git commit -m "Fix: normalizar saltos de linea en settings.py y corregir STORAGES/DATABASES"
if ($LASTEXITCODE -ne 0) {
    Write-Host "No habia cambios nuevos para commitear." -ForegroundColor Yellow
}

git push
$pushExitCode = $LASTEXITCODE
$ErrorActionPreference = $prevEAP

if ($pushExitCode -ne 0) {
    throw "El 'git push' fallo. Revisa el mensaje de arriba."
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " LISTO. Corregido y subido. Render deberia redeployar solo." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
