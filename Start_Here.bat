@echo off
title K BNG M Hoster v0.7.2.3
:: START HERE - just double-click K-BNG-M-Hoster.exe or this file. That's all you need to do.
if exist "%~dp0K-BNG-M-Hoster.exe" (
    start "" "%~dp0K-BNG-M-Hoster.exe" %*
    exit /b 0
)
if not exist "%~dp0Server\Play_BeamMP.ps1" (
    echo.
    echo   ERROR: Server\Play_BeamMP.ps1 was not found.
    echo   Did you run this file from inside the zip?
    echo   First extract the whole folder from the zip, then run
    echo   K-BNG-M-Hoster.exe or Start_Here.bat again.
    echo.
    pause
    exit /b 1
)
:: "start" makes this window close instantly - the GUI runs in its own hidden console.
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Server\Play_BeamMP.ps1" %*
exit /b 0
