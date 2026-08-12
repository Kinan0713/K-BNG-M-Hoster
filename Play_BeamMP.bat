@echo off
title K BNG M Hoster - Core Boot Sequence

:: ========================================================================================
:: K BNG M Hoster v0.3 - Fixed launcher
:: Purpose: start a BeamMP server and stop it the moment the game session ends.
:: ========================================================================================

setlocal

:: ========================================================================================
:: 1. RESOLVE THE REAL SERVER DIRECTORY (no elevation, no re-extraction)
:: The SFX runs this batch from a temp folder, so we rely on the working directory
:: (which is the folder the .exe was launched from) and fall back to %~dp0.
:: ========================================================================================
set "SERVER_DIR=%CD%\"
if not exist "%SERVER_DIR%BeamMP-Server.exe" set "SERVER_DIR=%~dp0"
if not exist "%SERVER_DIR%BeamMP-Server.exe" (
    color 0C
    echo [ERROR] BeamMP-Server.exe was not found in:
    echo          %SERVER_DIR%
    echo.
    echo Please run the .exe from inside your K BNG M Hoster folder!
    echo.
    pause
    exit /b 1
)
if not exist "%SERVER_DIR%ServerConfig.toml" (
    color 0C
    echo [ERROR] ServerConfig.toml was not found in:
    echo          %SERVER_DIR%
    echo.
    pause
    exit /b 1
)
if not exist "%APPDATA%\BeamMP-Launcher\BeamMP-Launcher.exe" (
    color 0C
    echo [ERROR] BeamMP-Launcher.exe was not found at:
    echo          %APPDATA%\BeamMP-Launcher\BeamMP-Launcher.exe
    echo.
    echo This tool requires the official BeamMP Launcher to detect your game session.
    echo Please install it first, then run this tool again.
    echo.
    pause
    exit /b 1
)
cd /d "%SERVER_DIR%"

:: ========================================================================================
:: 2. LOGGING
:: ========================================================================================
set "LOGFILE=%SERVER_DIR%Logs\launcher.log"
if not exist "%SERVER_DIR%Logs" mkdir "%SERVER_DIR%Logs"
echo [%date% %time%] ===== Launcher started ===== >> "%LOGFILE%"

:: ========================================================================================
:: 3. EULA GATEWAY
:: ========================================================================================
:EULA
cls
color 0E
echo ===============================================================================
echo                   K BNG M Hoster - END USER LICENSE AGREEMENT
echo ===============================================================================
echo  Owner / Creator: Kinan (Discord: @raed713)
echo.
echo  TERMS OF SERVICE:
echo  1. OWNERSHIP: This tool is the intellectual property of Kinan.
echo  2. DISTRIBUTION: Re-uploading, redistributing, or selling is STRICTLY PROHIBITED.
echo  3. TAMPERING: Editing, obfuscating, or removing Kinan's name is ILLEGAL.
echo  4. FAKING: Claiming ownership will result in a permanent ban.
echo ===============================================================================
echo.
choice /C YN /T 30 /D N /M "Do you ACCEPT these terms and acknowledge Kinan as the owner"
if errorlevel 2 (
    echo.
    echo [ABORTED] You must accept the license agreement to run K BNG M Hoster.
    echo [%date% %time%] EULA rejected >> "%LOGFILE%"
    timeout /t 3 >nul
    exit /b
)
echo [%date% %time%] EULA accepted >> "%LOGFILE%"

:: ========================================================================================
:: 4. BANNER
:: ========================================================================================
color 0B
cls
echo ==================================================================================================
echo    K   K   BBB   N   N   GGG     M   M   H   H   OOO   SSS  TTTTT  EEE  RRRR
echo    K  K    B  B  NN  N  G        MM MM   H   H  O   O S       T    E    R   R
echo    KKK     BBB   N N N  G  GG    M M M   HHHHH  O   O  SSS    T    EEE  RRRR
echo    K  K    B  B  N  NN  G   G    M   M   H   H  O   O     S   T    E    R R
echo    K   K   BBB   N   N   GGG     M   M   H   H   OOO  SSSS    T    EEE  R  RR
echo ==================================================================================================
echo    K BNG M Hoster v0.3 - Node Architecture
echo    Sole Creator: Kinan ^| Official Discord: @raed713
echo ==================================================================================================
echo.

:: ========================================================================================
:: 5. SECURITY SCAN (non-destructive, logged)
:: Moves suspicious executables out of Resources\Client so BeamMP never serves them.
:: ========================================================================================
echo [*] Running security scan on Resources\Client...
if not exist "%SERVER_DIR%Quarantine" mkdir "%SERVER_DIR%Quarantine"
powershell -NoProfile -Command "$scan = Get-ChildItem -LiteralPath '%SERVER_DIR%Resources\Client' -Recurse -File -Include *.exe,*.vbs,*.cmd,*.scr,*.pif -ErrorAction SilentlyContinue; if ($scan) { $q = Join-Path '%SERVER_DIR%Quarantine' (Get-Date -Format 'yyyyMMdd-HHmmss'); New-Item -ItemType Directory -Path $q -Force | Out-Null; foreach ($f in $scan) { try { Move-Item -LiteralPath $f.FullName -Destination $q -Force -ErrorAction Stop } catch {} ; Add-Content -LiteralPath '%SERVER_DIR%Logs\launcher.log' -Value ('[QUARANTINE] ' + $f.FullName) }; Write-Host ('[SECURITY] ' + $scan.Count + ' suspect file(s) quarantined.') }"
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%SERVER_DIR%Resources\Client' -Filter *.zip -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -eq 0 } | Remove-Item -Force -ErrorAction SilentlyContinue" >nul 2>&1

:: ========================================================================================
:: 6. STABLE SERVER NAME (read from config, no random node id)
:: ========================================================================================
set "SERVER_NAME="
for /f "usebackq tokens=2 delims==" %%N in (`findstr /b /c:"Name" "%SERVER_DIR%ServerConfig.toml"`) do set "SERVER_NAME=%%N"
if not defined SERVER_NAME set "SERVER_NAME=K BNG M Server"

:: ========================================================================================
:: 7. REPAIR INVALID mods.json (BeamMP expects a JSON array, not "null")
:: ========================================================================================
if exist "%SERVER_DIR%Resources\Client\mods.json" (
    powershell -NoProfile -Command "$p = '%SERVER_DIR%Resources\Client\mods.json'; $c = Get-Content -LiteralPath $p -Raw; if ($c -match '^\s*null\s*$') { Set-Content -LiteralPath $p -Value '[]' }"
)

:: ========================================================================================
:: 8. START THE SERVER (capture PID so we can kill exactly this instance)
:: ========================================================================================
echo [*] Starting BeamMP server...
set "SERVER_PID="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "(Start-Process -FilePath '%SERVER_DIR%BeamMP-Server.exe' -WorkingDirectory '%SERVER_DIR%' -WindowStyle Minimized -PassThru).Id"`) do set "SERVER_PID=%%P"
if not defined SERVER_PID (
    color 0C
    echo [ERROR] Could not start BeamMP-Server.exe.
    echo [%date% %time%] Failed to start server process >> "%LOGFILE%"
    pause
    exit /b 1
)

:: ========================================================================================
:: 9. WAIT UNTIL THE SERVER IS ACTUALLY LISTENING (real "LIVE" check)
:: ========================================================================================
set /a WAIT_N=0
:WAITPORT
set /a WAIT_N+=1
if %WAIT_N% gtr 20 goto PORTFAIL
powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort 30814 -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }" >nul 2>&1
if errorlevel 1 (
    timeout /t 1 /nobreak >nul
    goto WAITPORT
)
echo [OK] Server is listening on port 30814.
goto SERVERLIVE

:PORTFAIL
color 0C
echo [ERROR] Server did not start. Check that your AuthKey is set correctly in ServerConfig.toml.
echo [%date% %time%] Server failed to listen (PID %SERVER_PID%) >> "%LOGFILE%"
if defined SERVER_PID taskkill /PID %SERVER_PID% /F /T >nul 2>&1
pause
exit /b 1

:SERVERLIVE
echo [%date% %time%] Server is live (PID %SERVER_PID%) >> "%LOGFILE%"

:: ========================================================================================
:: 10. WATCHDOG: guarantee the server dies with the session even if this window is closed
:: Only fires after the launcher has been observed running once (so it never kills the
:: server before the game session actually begins).
:: ========================================================================================
start "" /MIN powershell -NoProfile -Command "$seen = $false; while ($true) { $running = [bool](Get-Process -Name BeamMP-Launcher -ErrorAction SilentlyContinue); if ($running) { $seen = $true }; if ($seen -and -not $running) { Stop-Process -Id %SERVER_PID% -Force -ErrorAction SilentlyContinue; break }; Start-Sleep -Seconds 2 }"

:: ========================================================================================
:: 11. OPTIONAL DISCORD WEBHOOK (opt-in: only if webhook.txt exists next to the .exe)
:: ========================================================================================
set "WEBHOOK_URL="
if exist "%SERVER_DIR%webhook.txt" (
    for /f "usebackq delims=" %%U in ("%SERVER_DIR%webhook.txt") do set "WEBHOOK_URL=%%U"
)
if defined WEBHOOK_URL (
    if not "%WEBHOOK_URL%"=="YOUR_DISCORD_WEBHOOK_URL_HERE" (
        powershell -NoProfile -Command "$u = '%WEBHOOK_URL%'; $t = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); $b = @{ embeds = @( @{ title = 'K BNG M Hoster [ONLINE]'; description = 'Server is now live.'; color = 3066993; timestamp = $t } ) } | ConvertTo-Json -Depth 10; try { Invoke-RestMethod -Uri $u -Method Post -Body $b -ContentType 'application/json' } catch { }" >nul 2>&1
    )
)

:: ========================================================================================
:: 12. LIVE UI
:: ========================================================================================
color 0A
cls
echo =================================================================
echo    SERVER IS LIVE!
echo    Server Name : %SERVER_NAME%
echo    Creator     : Kinan (Discord: @raed713)
echo    Port        : 30814
echo.
echo    Leave this window open. Closing it stops the server.
echo =================================================================

:: ========================================================================================
:: 13. VOICE ANNOUNCEMENT (best-effort; skipped if System.Speech is unavailable)
:: ========================================================================================
powershell -NoProfile -Command "try { Add-Type -AssemblyName System.Speech -ErrorAction Stop; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.Speak('K BNG M Hoster is online.') } catch { }" >nul 2>&1

:: ========================================================================================
:: 14. LAUNCH THE GAME LAUNCHER AND WAIT FOR THE SESSION TO END
:: ========================================================================================
start "" "%APPDATA%\BeamMP-Launcher\BeamMP-Launcher.exe"
:WAITSESSION
tasklist /FI "IMAGENAME eq BeamMP-Launcher.exe" | find /I "BeamMP-Launcher.exe" >nul 2>&1
if errorlevel 1 goto SESSIONEND
timeout /t 5 /nobreak >nul
goto WAITSESSION

:: ========================================================================================
:: 15. SESSION ENDED - STOP ONLY THIS SERVER INSTANCE
:: ========================================================================================
:SESSIONEND
color 0C
title K BNG M Hoster - Terminating Sequence...
echo.
echo =================================================================
echo  Game session ended. Stopping server...
echo =================================================================
echo [%date% %time%] Session ended >> "%LOGFILE%"
if defined SERVER_PID (
    tasklist /FI "PID eq %SERVER_PID%" /NH | find "%SERVER_PID%" >nul 2>&1
    if not errorlevel 1 taskkill /PID %SERVER_PID% /F /T >nul 2>&1
)
echo [%date% %time%] Server stopped >> "%LOGFILE%"
powershell -NoProfile -Command "try { Add-Type -AssemblyName System.Speech -ErrorAction Stop; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.Speak('Session closed.') } catch { }" >nul 2>&1
exit /b 0
