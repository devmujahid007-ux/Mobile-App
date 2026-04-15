# Start API without Docker — you MUST have MySQL 8 running first.
#
# 1) Install MySQL Server (https://dev.mysql.com/downloads/mysql/)
# 2) Create database: CREATE DATABASE tumer_db;
# 3) Edit backend\.env — MYSQL_USER, MYSQL_PASSWORD, MYSQL_HOST (usually 127.0.0.1), MYSQL_PORT, MYSQL_DB
#
# Then run from Mobile-app folder:
#   .\setup_backend_no_docker.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot\backend

if (-not (Test-Path ".\.env")) {
    Copy-Item ".\.env.example" ".\.env"
    Write-Host "Created .env from .env.example — edit MYSQL_PASSWORD if your MySQL root password is not 'admin'." -ForegroundColor Yellow
}

if (-not (Test-Path ".\venv\Scripts\python.exe")) {
    Write-Host "Creating venv..." -ForegroundColor Cyan
    py -3 -m venv venv
    if (-not (Test-Path ".\venv\Scripts\python.exe")) {
        python -m venv venv
    }
}

& .\venv\Scripts\Activate.ps1
Write-Host "pip install (first run: several minutes, downloads PyTorch)..." -ForegroundColor Cyan
pip install -r requirements.txt

Write-Host "Creating tables..." -ForegroundColor Cyan
python create_tables.py

Write-Host ""
Write-Host "Starting API — keep this window OPEN. Open http://127.0.0.1:8000/docs" -ForegroundColor Green
uvicorn main:app --host 0.0.0.0 --port 8000
