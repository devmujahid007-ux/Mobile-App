# Start API without Docker. Requires local MySQL 8.

$ErrorActionPreference = 'Stop'

$backendPath = Join-Path $PSScriptRoot 'backend'
Set-Location $backendPath

if (-not (Test-Path '.\.env')) {
    Copy-Item '.\.env.example' '.\.env'
    Write-Host "Created backend/.env from .env.example. Update MYSQL_PASSWORD if needed." -ForegroundColor Yellow
}

if (-not (Test-Path '.\venv\Scripts\python.exe')) {
    Write-Host 'Creating venv...' -ForegroundColor Cyan
    py -3 -m venv venv
    if (-not (Test-Path '.\venv\Scripts\python.exe')) {
        python -m venv venv
    }
}

$py = Join-Path $backendPath 'venv\Scripts\python.exe'
$pip = Join-Path $backendPath 'venv\Scripts\pip.exe'

Write-Host 'Installing Python dependencies (first run can take time)...' -ForegroundColor Cyan
& $pip install -r requirements.txt

Write-Host 'Creating/updating database tables...' -ForegroundColor Cyan
& $py create_tables.py

Write-Host ''
Write-Host 'API on :8000 — use http://127.0.0.1:8000 in the browser (not 0.0.0.0).' -ForegroundColor Green
Write-Host 'Docs: http://127.0.0.1:8000/docs   Health: http://127.0.0.1:8000/health' -ForegroundColor Green
Write-Host 'Keep this window open while testing. Closing it stops the API.' -ForegroundColor Yellow
$null = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 5
    Start-Process 'http://127.0.0.1:8000/docs'
}
Write-Host 'Opening http://127.0.0.1:8000/docs in ~5 seconds...' -ForegroundColor Cyan
& $py -m uvicorn main:app --host 0.0.0.0 --port 8000
