@echo off
title Build K BNG M Hoster Installer
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build-Installer.ps1"
echo.
pause
