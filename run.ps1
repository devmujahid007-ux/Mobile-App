# Flutter Web (Chrome) on the same PC as the API:
# Use 127.0.0.1 — Chrome often blocks localhost → 192.168.x.x unless the API sends
# Access-Control-Allow-Private-Network (backend now does), but 127.0.0.1 is still the most reliable.
#
# Physical phone on Wi‑Fi: run with LAN IP instead, e.g.
#   flutter run --dart-define=NEUROSCAN_API_URL=http://192.168.1.50:8000

Set-Location $PSScriptRoot\f_a_det_app
flutter run -d chrome --dart-define=NEUROSCAN_API_URL=http://127.0.0.1:8000
