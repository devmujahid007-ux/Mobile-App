# One-shot: MySQL (Docker) + Python venv + DB tables + Uvicorn on :8000
# Run from Mobile-app folder:  .\setup_and_run_backend.ps1
# If MySQL is already installed locally (no Docker):  .\setup_and_run_backend.ps1 -SkipDocker

param(
    [switch]$SkipDocker
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
Set-Location $Root

if (-not $SkipDocker) {
    Write-Host "==> Starting MySQL (docker compose)..." -ForegroundColor Cyan
    docker compose up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Docker failed. Install Docker Desktop, OR start MySQL on this PC and run:" -ForegroundColor Red
        Write-Host "  .\setup_and_run_backend.ps1 -SkipDocker" -ForegroundColor Yellow
        Write-Host "Or use: .\setup_backend_no_docker.ps1" -ForegroundColor Yellow
        exit 1
    }
    Start-Sleep -Seconds 6
} else {
    Write-Host "==> Skipping Docker — using MySQL from backend/.env (ensure it is running)." -ForegroundColor Yellow
}

Set-Location "$Root\backend"

if (-not (Test-Path ".\.env")) {
    Copy-Item ".\.env.example" ".\.env"
    Write-Host "Created backend\.env from .env.example — edit MYSQL_* if needed." -ForegroundColor Yellow
}

if (-not (Test-Path ".\venv\Scripts\python.exe")) {
    Write-Host "==> Creating Python venv..." -ForegroundColor Cyan
    py -3 -m venv venv
    if ($LASTEXITCODE -ne 0) { python -m venv venv }
}

$py = Join-Path (Get-Location) "venv\Scripts\python.exe"
$pip = Join-Path (Get-Location) "venv\Scripts\pip.exe"
Write-Host "==> pip install (first time can take several minutes)..." -ForegroundColor Cyan
& $pip install -r requirements.txt

Write-Host "==> create_tables.py..." -ForegroundColor Cyan
& $py create_tables.py

Write-Host "==> API: http://127.0.0.1:8000/docs (do not use 0.0.0.0 in the browser)." -ForegroundColor Green
Write-Host "Keep this window open — closing it stops the API." -ForegroundColor Yellow
$null = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 5
    Start-Process 'http://127.0.0.1:8000/docs'
}
& $py -m uvicorn main:app --host 0.0.0.0 --port 8000
