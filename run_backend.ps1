# Start NeuroScan FastAPI so phones / LAN / Flutter web can reach it.
# Requires: Python venv in .\backend\venv and dependencies installed (pip install -r requirements.txt)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\backend

if (-not (Test-Path ".\venv\Scripts\Activate.ps1")) {
    Write-Host "Run once from repo root: .\setup_and_run_backend.ps1"
    exit 1
}

Write-Host "Starting API on http://0.0.0.0:8000 — open http://127.0.0.1:8000/docs"
& .\venv\Scripts\Activate.ps1
uvicorn main:app --host 0.0.0.0 --port 8000
