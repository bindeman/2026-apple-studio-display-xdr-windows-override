@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Test-StudioXdrAmbientPreflight.ps1"
echo.
pause
