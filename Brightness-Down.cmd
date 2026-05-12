@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\StudioXdrBrightness.ps1" -StepPercent -5 %*
