@echo off
setlocal
set "ROOT=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\New-StudioXdrAmbientDriverPackage.ps1"
echo.
pause
