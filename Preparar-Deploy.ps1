# ============================================================================
#  Preparar-Deploy.ps1
#  Prepara Control-Ingreso para Render (Postgres via DATABASE_URL, gunicorn,
#  whitenoise para estaticos) y sube todo al repositorio de GitHub.
# ============================================================================
#  Que hace:
#   1. Instala dj-database-url, psycopg2-binary, gunicorn, whitenoise
#   2. Ajusta settings.py: SECRET_KEY/DEBUG/ALLOWED_HOSTS por variable de
#      entorno, DATABASES via DATABASE_URL (Postgres en Render, SQLite en local),
#      whitenoise para estaticos, CSRF_TRUSTED_ORIGINS
#   3. Crea Procfile y build.sh para Render
#   4. Actualiza requirements.txt y .gitignore
#   5. Sube todo al repo de GitHub que le indiques
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

# ==============================================================================
Write-Step "Activando entorno virtual e instalando dependencias de deploy"
# ==============================================================================
if (-not (Test-Path ".\venv\Scripts\Activate.ps1")) {
    throw "No se encontro el entorno virtual en $ProjectPath\venv. Corre primero Crear-ControlIngreso.ps1."
}
& ".\venv\Scripts\Activate.ps1"

pip install dj-database-url psycopg2-binary gunicorn whitenoise

# ==============================================================================
Write-Step "Respaldando settings.py"
# ==============================================================================
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$settingsPath = Join-Path $ProjectPath "config\settings.py"
Copy-Item $settingsPath "$settingsPath.$timestamp.bak"

$settings = Get-Content $settingsPath -Raw

# ==============================================================================
Write-Step "Configurando settings.py para produccion (Render)"
# ==============================================================================
if ($settings -notmatch "import dj_database_url") {

    # --- imports ---
    $settings = $settings -replace "from pathlib import Path", "import os`r`nfrom pathlib import Path`r`nimport dj_database_url"

    # --- SECRET_KEY por variable de entorno ---
    $settings = $settings -replace '(?m)^SECRET_KEY = .*$', "SECRET_KEY = os.environ.get('SECRET_KEY', 'dev-insecure-key-CAMBIAME-en-produccion')"

    # --- DEBUG por variable de entorno (True en local, False en Render) ---
    $settings = $settings -replace '(?m)^DEBUG = .*$', "DEBUG = os.environ.get('DEBUG', 'True') == 'True'"

    # --- ALLOWED_HOSTS por variable de entorno ---
    $settings = $settings -replace '(?m)^ALLOWED_HOSTS = \[\]$', "ALLOWED_HOSTS = os.environ.get('ALLOWED_HOSTS', '127.0.0.1,localhost').split(',')"

    # --- whitenoise en MIDDLEWARE (justo despues de SecurityMiddleware) ---
    $settings = $settings -replace "'django\.middleware\.security\.SecurityMiddleware',", "'django.middleware.security.SecurityMiddleware',`r`n    'whitenoise.middleware.WhiteNoiseMiddleware',"

    # --- DATABASES: Postgres en Render via DATABASE_URL, SQLite en local ---
    $settings = $settings -replace "(?s)DATABASES = \{.*?\n\}\n", @"
DATABASES = {
    'default': dj_database_url.config(
        default=f'sqlite:///{BASE_DIR / "db.sqlite3"}',
        conn_max_age=600,
    )
}
"@

    # --- Estaticos con whitenoise ---
    $settings = $settings -replace "(?m)^STATIC_URL = 'static/'$", @"
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
"@

    # --- CSRF_TRUSTED_ORIGINS (necesario para POST desde el dominio de Render) ---
    $csrfBlock = @'

# ---------------- Deploy: CSRF trusted origins ----------------
CSRF_TRUSTED_ORIGINS = [o for o in os.environ.get('CSRF_TRUSTED_ORIGINS', '').split(',') if o]
# ----------------------------------------------------------------
'@
    $settings += $csrfBlock

    Write-Utf8NoBom -Path $settingsPath -Content $settings
    Write-Host "settings.py actualizado para produccion." -ForegroundColor Green
} else {
    Write-Host "settings.py ya estaba configurado para produccion, no se toco." -ForegroundColor Yellow
}

# ==============================================================================
Write-Step "Creando Procfile y build.sh"
# ==============================================================================
$procfile = "web: gunicorn config.wsgi --log-file -"
Write-Utf8NoBom -Path (Join-Path $ProjectPath "Procfile") -Content $procfile

$buildSh = @'
#!/usr/bin/env bash
set -o errexit

pip install -r requirements.txt
python manage.py collectstatic --noinput
python manage.py migrate
'@
Write-Utf8NoBom -Path (Join-Path $ProjectPath "build.sh") -Content $buildSh

# ==============================================================================
Write-Step "Actualizando .gitignore"
# ==============================================================================
$gitignorePath = Join-Path $ProjectPath ".gitignore"
$gitignore = Get-Content $gitignorePath -Raw
$extras = @('*.bak', 'staticfiles/', '.env')
foreach ($line in $extras) {
    if ($gitignore -notmatch [regex]::Escape($line)) {
        $gitignore += "`r`n$line"
    }
}
Write-Utf8NoBom -Path $gitignorePath -Content $gitignore

# ==============================================================================
Write-Step "Verificando el proyecto (manage.py check)"
# ==============================================================================
python manage.py check

# ==============================================================================
Write-Step "Actualizando requirements.txt"
# ==============================================================================
pip freeze | Out-File -FilePath (Join-Path $ProjectPath "requirements.txt") -Encoding utf8

# ==============================================================================
Write-Step "Subiendo el proyecto a GitHub"
# ==============================================================================
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git no esta instalado o no esta en el PATH. Instalalo desde https://git-scm.com/ y vuelve a correr el script."
}

if (-not (Test-Path (Join-Path $ProjectPath ".git"))) {
    git init
    git branch -M main
}

$remotes = git remote
if ($remotes -contains "origin") {
    git remote set-url origin $RepoUrl
} else {
    git remote add origin $RepoUrl
}

git add -A

# Los comandos de git escriben a veces en stderr aunque no fallen de verdad
# (ej: "no hay commits todavia", "nothing to commit"), asi que aqui adentro
# usamos $LASTEXITCODE en vez de dejar que corte el script entero.
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"

git commit -m "Deploy: Postgres via DATABASE_URL, gunicorn, whitenoise"
if ($LASTEXITCODE -ne 0) {
    Write-Host "No habia cambios nuevos para commitear (probablemente ya estaba todo commiteado)." -ForegroundColor Yellow
}

Write-Host "Intentando sincronizar con el repositorio remoto (por si tiene un README inicial)..." -ForegroundColor Yellow
git pull origin main --allow-unrelated-histories --no-edit
if ($LASTEXITCODE -ne 0) {
    Write-Host "No habia nada que sincronizar (repo remoto vacio) o no aplico, seguimos con el push." -ForegroundColor Yellow
}

git push -u origin main
$pushExitCode = $LASTEXITCODE

$ErrorActionPreference = $prevEAP

if ($pushExitCode -ne 0) {
    throw "El 'git push' fallo. Revisa el mensaje de git de arriba (usuario/token de GitHub, o conflicto de historial) y vuelve a correr el script."
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " LISTO. Proyecto subido a: $RepoUrl" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Siguiente paso: crear el Web Service + PostgreSQL en Render."
Write-Host "Te explico los pasos manuales en el chat."
Write-Host ""
