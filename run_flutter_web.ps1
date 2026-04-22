param(
    [string]$ApiUrl = "http://127.0.0.1:8000"
)
$ErrorActionPreference = "Stop"

# Flutter web against the same FastAPI as the NeuroScan web app.
# --no-web-resources-cdn: avoids CanvasKit / font fetches from gstatic when offline or blocked.
# Point NEUROSCAN_API_URL at the machine running uvicorn (LAN example: http://192.168.1.50:8000).
# Without --no-web-resources-cdn, Chrome often fails: "Failed to fetch" for canvaskit.js / Roboto on gstatic.

Set-Location $PSScriptRoot\f_a_det_app
flutter pub get
flutter run -d chrome --no-web-resources-cdn `
    --dart-define=NEUROSCAN_API_URL=$ApiUrl
