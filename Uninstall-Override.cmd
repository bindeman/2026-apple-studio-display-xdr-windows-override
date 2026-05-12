@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall-StudioXdrEdidOverride.ps1" %*
pause
