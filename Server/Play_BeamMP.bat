@echo off
title K BNG M Hoster v0.5 - Simplest Edition
:: Thin launcher: all logic lives in Play_BeamMP.ps1 (single source of truth).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Play_BeamMP.ps1" %*
if errorlevel 1 pause
