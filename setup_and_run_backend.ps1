# One-shot: MySQL (Docker) + Python venv + DB tables + Uvicorn on :8000
# Run from Mobile-app folder:  .\setup_and_run_backend.ps1

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
Set-Location $Root

Write-Host "==> Starting MySQL (docker compose)..." -ForegroundColor Cyan
docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker failed. Install Docker Desktop or start MySQL yourself and set backend/.env" -ForegroundColor Red
    exit 1
}
Start-Sleep -Seconds 6

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

& .\venv\Scripts\Activate.ps1
Write-Host "==> pip install (first time can take several minutes)..." -ForegroundColor Cyan
pip install -r requirements.txt

Write-Host "==> create_tables.py..." -ForegroundColor Cyan
python create_tables.py

Write-Host "==> Uvicorn http://0.0.0.0:8000  (try http://127.0.0.1:8000/docs )" -ForegroundColor Green
uvicorn main:app --host 0.0.0.0 --port 8000
