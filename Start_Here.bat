@echo off
title K BNG M Hoster v0.5 - Simplest Edition
:: START HERE - just double-click this file.
:: All logic lives in Server\Play_BeamMP.ps1 (single source of truth).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Server\Play_BeamMP.ps1" %*
if errorlevel 1 pause