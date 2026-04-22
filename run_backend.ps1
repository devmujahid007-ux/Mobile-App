# Start NeuroScan FastAPI (run from repo root: .\run_backend.ps1)
# Uses venv python directly so you do not need Activate.ps1 (avoids execution-policy errors).

$ErrorActionPreference = "Stop"
$backend = Join-Path $PSScriptRoot "backend"
Set-Location $backend

$py = Join-Path $backend "venv\Scripts\python.exe"
if (-not (Test-Path $py)) {
    Write-Host "No venv at backend\venv. Run: cd backend; py -3 -m venv venv; .\venv\Scripts\pip install -r requirements.txt" -ForegroundColor Yellow
    exit 1
}

Write-Host "Starting API on port 8000. Use http://127.0.0.1:8000 in the browser - never http://0.0.0.0 (Chrome: ERR_ADDRESS_INVALID)." -ForegroundColor Green
Write-Host "Docs: http://127.0.0.1:8000/docs   Health: http://127.0.0.1:8000/health" -ForegroundColor Green
Write-Host "Keep this window open while you use the app. Closing it stops the API." -ForegroundColor Yellow

# Open Swagger in the default browser after the server is up (avoids users typing 0.0.0.0).
$null = Start-Job -ScriptBlock {
    Start-Sleep -Seconds 5
    Start-Process 'http://127.0.0.1:8000/docs'
}
Write-Host 'Opening http://127.0.0.1:8000/docs in your browser in about 5 seconds...' -ForegroundColor Cyan

& $py -m uvicorn main:app --host 0.0.0.0 --port 8000
