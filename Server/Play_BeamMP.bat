@echo off
title K BNG M Hoster v0.6.1 - GUI
:: Thin launcher: launches the GUI (logic lives in HosterCore.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Play_BeamMP.ps1" %*