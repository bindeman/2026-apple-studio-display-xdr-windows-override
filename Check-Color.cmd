@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Get-StudioXdrColorStatus.ps1"
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Find-StudioXdrColorProfiles.ps1" -IncludeUserFolders
echo.
pause
