@echo off
title NeuroScan AI — Flutter
cd /d "%~dp0f_a_det_app"
if not exist "pubspec.yaml" (
  echo ERROR: Could not find f_a_det_app\pubspec.yaml
  echo Keep this file in the Mobile-app folder next to f_a_det_app.
  pause
  exit /b 1
)
echo.
echo Starting NeuroScan AI in Chrome (flutter run -d chrome)...
echo.
flutter run -d chrome
echo.
if errorlevel 1 (
  echo Run failed. See messages above.
  pause
)
