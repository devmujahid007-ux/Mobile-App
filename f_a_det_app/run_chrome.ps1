param(
    [string]$ApiUrl = "http://127.0.0.1:8000"
)
$ErrorActionPreference = "Stop"
# Required when fonts.gstatic.com / www.gstatic.com are blocked (CanvasKit + Roboto).
flutter run -d chrome --no-web-resources-cdn --dart-define=NEUROSCAN_API_URL=$ApiUrl
