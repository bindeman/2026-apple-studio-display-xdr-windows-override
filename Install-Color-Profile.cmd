@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-StudioXdrColorProfile.ps1" -ProfilePath "%~dp0profiles\StudioDisplayXDR-DisplayP3.icm"
pause
