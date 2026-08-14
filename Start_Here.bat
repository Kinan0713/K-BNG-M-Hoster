@echo off
title K BNG M Hoster v0.6.1 - GUI
:: START HERE - just double-click this file.
:: Launches the GUI (logic lives in Server\HosterCore.ps1).
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Server\Play_BeamMP.ps1" %*