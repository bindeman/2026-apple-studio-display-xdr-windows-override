@echo off
setlocal
cd /d "%~dp0"
start "Apple Display Brightness" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0scripts\AppleDisplayBrightnessTray.ps1"
