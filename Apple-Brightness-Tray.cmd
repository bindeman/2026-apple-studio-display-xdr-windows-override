@echo off
setlocal
cd /d "%~dp0"
set "STABLE_APP=%LOCALAPPDATA%\StudioDisplayXdr\Support\StudioDisplayXdr.App\StudioDisplayXdr.exe"
if exist "%~dp0.git" goto local_app
if exist "%STABLE_APP%" (
  start "Studio Display XDR" "%STABLE_APP%"
  exit /b
)

:local_app
if exist "%~dp0StudioDisplayXdr.App\StudioDisplayXdr.exe" (
  start "Studio Display XDR" "%~dp0StudioDisplayXdr.App\StudioDisplayXdr.exe"
) else if exist "%~dp0dist\StudioDisplayXdr.App\StudioDisplayXdr.exe" (
  start "Studio Display XDR" "%~dp0dist\StudioDisplayXdr.App\StudioDisplayXdr.exe"
) else (
  start "Studio Display XDR" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\AppleDisplayBrightnessTray.ps1"
)
