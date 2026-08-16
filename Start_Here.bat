@echo off
title K BNG M Hoster v0.6.7
:: START HERE - just double-click this file. That's all you ever need to do.
:: Everything else lives in the "Server" folder - you never need to open it.
if not exist "%~dp0Server\Play_BeamMP.ps1" (
    echo.
    echo   ERROR: Server\Play_BeamMP.ps1 was not found.
    echo   Did you run this file from inside the zip?
    echo   First extract the whole folder from the zip, then double-click
    echo   Start_Here.bat again.
    echo.
    pause
    exit /b 1
)
:: "start" makes this window close instantly - the GUI runs in its own hidden console.
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Server\Play_BeamMP.ps1" %*
exit /b 0
