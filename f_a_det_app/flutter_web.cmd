@echo off
REM Flutter web without loading CanvasKit/Roboto from gstatic (fixes "Failed to fetch" when CDN is blocked).
cd /d "%~dp0"
if "%NEUROSCAN_API_URL%"=="" set "NEUROSCAN_API_URL=http://127.0.0.1:8000"
flutter run -d chrome --no-web-resources-cdn --dart-define=NEUROSCAN_API_URL=%NEUROSCAN_API_URL% %*
