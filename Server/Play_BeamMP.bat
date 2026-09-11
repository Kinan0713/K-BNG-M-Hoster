@echo off
title K BNG M Hoster v0.7.0
:: Thin launcher: launches the GUI (logic lives in HosterCore.ps1).
:: "start" makes this window close instantly - the GUI runs in its own hidden console.
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Play_BeamMP.ps1" %*
exit /b 0