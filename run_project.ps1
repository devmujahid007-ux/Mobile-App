# One command: MySQL (Docker) + FastAPI + Flutter app
# Run from repo root: .\run_project.ps1
#
# First time only (venv, pip, DB tables):
#   .\setup_and_run_backend.ps1
#   or: .\setup_and_run_backend.ps1 -SkipDocker
#
# Every session:
#   .\run_project.ps1
#   Local MySQL: .\run_project.ps1 -SkipDocker
#   API only (this window): .\run_project.ps1 -BackendOnly

param(
    [switch]$SkipDocker,
    [switch]$BackendOnly
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
Set-Location $Root

if (-not $SkipDocker) {
    Write-Host "==> MySQL (docker compose up -d)..." -ForegroundColor Cyan
    docker compose up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Docker failed. Use local MySQL: .\run_project.ps1 -SkipDocker" -ForegroundColor Red
        exit 1
    }
    Start-Sleep -Seconds 5
} else {
    Write-Host "==> Skipping Docker; ensure MySQL in backend\.env is running." -ForegroundColor Yellow
}

$backend = Join-Path $Root "backend"
$py = Join-Path $backend "venv\Scripts\python.exe"
if (-not (Test-Path $py)) {
    Write-Host "No Python venv at backend\venv. Run once:" -ForegroundColor Red
    Write-Host "  .\setup_and_run_backend.ps1" -ForegroundColor Yellow
    Write-Host "  or: .\setup_and_run_backend.ps1 -SkipDocker" -ForegroundColor Yellow
    exit 1
}

# Flutter always calls http://127.0.0.1:8000 — if another backend (e.g. web) already owns this
# port, Contact Us and other routes hit the wrong process. Free the port for this mobile API.
Write-Host "==> Ensuring port 8000 is free for Mobile-app backend..." -ForegroundColor Yellow
try {
    $listen = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
    foreach ($row in $listen) {
        $procId = $row.OwningProcess
        if ($procId) {
            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
        }
    }
} catch {}
Start-Sleep -Seconds 2

if ($BackendOnly) {
    Set-Location $backend
    Write-Host "==> API: http://127.0.0.1:8000/docs (keep this window open)" -ForegroundColor Green
    $null = Start-Job -ScriptBlock {
        Start-Sleep -Seconds 5
        Start-Process "http://127.0.0.1:8000/docs"
    }
    & $py -m uvicorn main:app --host 0.0.0.0 --port 8000
    exit $LASTEXITCODE
}

# Full stack: API in a second window, Flutter in this window
$apiCmd = "Set-Location -LiteralPath '$backend'; Write-Host 'NeuroScan API on http://127.0.0.1:8000/docs' -ForegroundColor Green; & '$py' -m uvicorn main:app --host 0.0.0.0 --port 8000"
Write-Host "==> Starting API in a new window..." -ForegroundColor Cyan
Start-Process powershell -ArgumentList @("-NoExit", "-Command", $apiCmd)
Start-Sleep -Seconds 4

$flutterDir = Join-Path $Root "f_a_det_app"
Write-Host "==> Flutter: $flutterDir" -ForegroundColor Cyan
Set-Location -LiteralPath $flutterDir
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter run
