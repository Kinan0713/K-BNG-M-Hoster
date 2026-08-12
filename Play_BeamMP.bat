@echo off
title K BNG M Hoster - Core Boot Sequence

:: ========================================================================================
:: K BNG M Hoster v0.4 - User-friendly launcher
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
:: 3. ARGUMENT DISPATCH (utility modes, no EULA required)
::     Play_BeamMP.bat mods   - open the Mod Manager
::     Play_BeamMP.bat help   - show usage
:: ========================================================================================
if /i "%~1"=="mods" goto MODMENU
if /i "%~1"=="help" goto USAGE

:: ========================================================================================
:: 4. EULA GATEWAY
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
:: 5. BANNER
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
echo    K BNG M Hoster v0.4 - Node Architecture
echo    Sole Creator: Kinan ^| Official Discord: @raed713
echo ==================================================================================================
echo.

:: ========================================================================================
:: 6. UPDATE CHECKER (non-blocking, cached for 24h)
:: Compares your local BeamMP-Server.exe file date against the latest official release.
:: Never delays startup and fails silently when there is no internet connection.
:: ========================================================================================
powershell -NoProfile -ExecutionPolicy Bypass -Command "$cache='%SERVER_DIR%Logs\update_check.json'; $msg=''; $run=$true; if(Test-Path -LiteralPath $cache){try{$j=Get-Content -LiteralPath $cache -Raw|ConvertFrom-Json; if($j.checked -and ((Get-Date)-[datetime]$j.checked).TotalHours -lt 24){$run=$false; $msg=$j.msg}}catch{}}; if($run){try{$r=Invoke-RestMethod -Uri 'https://api.github.com/repos/BeamMP/BeamMP-Server/releases/latest' -Headers @{'User-Agent'='K-BNG-M-Hoster'} -TimeoutSec 8; $local=(Get-Item -LiteralPath '%SERVER_DIR%BeamMP-Server.exe').LastWriteTime; $remote=[datetime]$r.published_at; if($remote -gt $local){$msg='[UPDATE] New BeamMP-Server '+$r.tag_name+' is available (published '+$r.published_at+'). Download: '+$r.html_url}; @{checked=(Get-Date).ToString('o'); msg=$msg}|ConvertTo-Json|Set-Content -LiteralPath $cache}catch{$msg=''}}; if($msg){Write-Host $msg -ForegroundColor Yellow}"

:: ========================================================================================
:: 7. SECURITY SCAN (non-destructive, logged)
:: Moves suspicious executables out of Resources\Client (including inside .zip mods)
:: so BeamMP never serves them.
:: ========================================================================================
echo [*] Running security scan on Resources\Client...
if not exist "%SERVER_DIR%Quarantine" mkdir "%SERVER_DIR%Quarantine"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=@(); $s+=Get-ChildItem -LiteralPath '%SERVER_DIR%Resources\Client' -Recurse -File -ErrorAction SilentlyContinue | Where-Object {$_.Extension -in '.exe','.vbs','.cmd','.scr','.pif'}; Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue; Get-ChildItem -LiteralPath '%SERVER_DIR%Resources\Client' -Recurse -Filter *.zip -File -ErrorAction SilentlyContinue | ForEach-Object { if($_.Length -eq 0){Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue; return}; try{$a=[IO.Compression.ZipFile]::OpenRead($_.FullName); $bad=$false; foreach($e in $a.Entries){if($e.FullName -match '\.(exe|vbs|cmd|scr|pif)$'){$bad=$true; break}}; $a.Dispose(); if($bad){$s+=$_}}catch{} }; if($s.Count){$q=Join-Path '%SERVER_DIR%Quarantine' (Get-Date -Format 'yyyyMMdd-HHmmss'); New-Item -ItemType Directory -Path $q -Force | Out-Null; foreach($f in $s){try{Move-Item -LiteralPath $f.FullName -Destination $q -Force -ErrorAction Stop}catch{}; Add-Content -LiteralPath '%SERVER_DIR%Logs\launcher.log' -Value ('[QUARANTINE] '+$f.FullName)}; Write-Host ('[SECURITY] '+$s.Count+' suspect file(s) quarantined.')}"

:: ========================================================================================
:: 8. STABLE SERVER NAME + PORT (read from config, no random node id)
:: ========================================================================================
set "SERVER_NAME="
for /f "usebackq tokens=2 delims==" %%N in (`findstr /b /c:"Name" "%SERVER_DIR%ServerConfig.toml"`) do set "SERVER_NAME=%%N"
if defined SERVER_NAME set "SERVER_NAME=%SERVER_NAME:"=%"
if not defined SERVER_NAME set "SERVER_NAME=K BNG M Server"

set "SERVER_PORT=30814"
for /f "usebackq tokens=2 delims==" %%P in (`findstr /b /c:"Port" "%SERVER_DIR%ServerConfig.toml"`) do set "SERVER_PORT=%%P"

:: ========================================================================================
:: 9. AUTH KEY AUTO-INJECTION (from .env or the BEAMMP_AUTHKEY env var)
:: Reads the key from the local .env file (or the BEAMMP_AUTHKEY environment variable)
:: and writes it into ServerConfig.toml right before the server starts, so you never
:: have to paste it manually. If both are missing, an already-set key in the config is
:: left untouched.
:: ========================================================================================
powershell -NoProfile -ExecutionPolicy Bypass -Command "$k = $env:BEAMMP_AUTHKEY; $src = 'BEAMMP_AUTHKEY env var'; $ef = '%SERVER_DIR%.env'; if (-not $k) { if (Test-Path -LiteralPath $ef) { $k = (Get-Content -LiteralPath $ef | Where-Object { $_ -match '^\s*BEAMMP_AUTHKEY\s*=' } | Select-Object -First 1) -replace '^\s*BEAMMP_AUTHKEY\s*=', ''; if ($k) { $k = $k.Trim().Trim([char]34, [char]39); $src = '.env file' } } }; $p = '%SERVER_DIR%ServerConfig.toml'; if ($k) { $c = Get-Content -LiteralPath $p; $c = $c | ForEach-Object { if ($_ -match '^\s*AuthKey\s*=') { 'AuthKey = ' + [char]34 + $k + [char]34 } else { $_ } }; Set-Content -LiteralPath $p -Value $c -Encoding UTF8; Write-Host ('[AUTH] AuthKey injected from ' + $src); Add-Content -LiteralPath '%SERVER_DIR%Logs\launcher.log' -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' [AUTH] AuthKey injected from ' + $src) } else { $pat = '^\s*AuthKey\s*=\s*' + [char]34 + '[^' + [char]34 + ']+' + [char]34; $hasKey = Select-String -LiteralPath $p -Pattern $pat -Quiet; if (-not $hasKey) { Write-Host '[AUTH] No AuthKey found. Create a .env file next to the launcher with: BEAMMP_AUTHKEY=your_key_here  (or set the BEAMMP_AUTHKEY environment variable).' -ForegroundColor Yellow; Add-Content -LiteralPath '%SERVER_DIR%Logs\launcher.log' -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' [AUTH] WARNING: no AuthKey found') } else { Write-Host '[AUTH] Using AuthKey already present in ServerConfig.toml.'; Add-Content -LiteralPath '%SERVER_DIR%Logs\launcher.log' -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' [AUTH] Using existing AuthKey in ServerConfig.toml') } }"

:: ========================================================================================
:: 10. REPAIR INVALID mods.json (BeamMP expects a JSON array, not "null")
:: ========================================================================================
if exist "%SERVER_DIR%Resources\Client\mods.json" (
    powershell -NoProfile -Command "$p = '%SERVER_DIR%Resources\Client\mods.json'; $c = Get-Content -LiteralPath $p -Raw; if ($c -match '^\s*null\s*$') { Set-Content -LiteralPath $p -Value '[]' }"
)

:: ========================================================================================
:: 11. SINGLE-INSTANCE + PORT PRE-CHECK (avoid two servers / confusing errors)
:: ========================================================================================
tasklist /FI "IMAGENAME eq BeamMP-Server.exe" /NH | find /I "BeamMP-Server.exe" >nul 2>&1
if not errorlevel 1 (
    color 0C
    echo [ERROR] A BeamMP-Server.exe is already running.
    echo         Close it before starting a new session, or change Port in ServerConfig.toml.
    echo [%date% %time%] Aborted: server already running >> "%LOGFILE%"
    pause
    exit /b 1
)
powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort %SERVER_PORT% -State Listen -ErrorAction SilentlyContinue) { $c = Get-NetTCPConnection -LocalPort %SERVER_PORT% -State Listen | Select-Object -First 1; $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue; Write-Host ('[ERROR] Port %SERVER_PORT% is already in use by: ' + $p.ProcessName + ' (PID ' + $p.Id + '). Close it or change Port in ServerConfig.toml.'); exit 1 } else { exit 0 }"
if errorlevel 1 (
    color 0C
    pause
    exit /b 1
)

:: ========================================================================================
:: 12. START THE SERVER (capture PID so we can kill exactly this instance)
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
:: 13. WAIT UNTIL THE SERVER IS ACTUALLY LISTENING (real "LIVE" check, up to 40s)
:: ========================================================================================
set /a WAIT_N=0
:WAITPORT
set /a WAIT_N+=1
if %WAIT_N% gtr 40 goto PORTFAIL
powershell -NoProfile -Command "if (Get-NetTCPConnection -LocalPort %SERVER_PORT% -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }" >nul 2>&1
if errorlevel 1 (
    timeout /t 1 /nobreak >nul
    goto WAITPORT
)
echo [OK] Server is listening on port %SERVER_PORT%.
goto SERVERLIVE

:: ========================================================================================
:: 14. STARTUP DIAGNOSTICS (reads Server.log and explains why the server failed)
:: ========================================================================================
:PORTFAIL
color 0C
echo [ERROR] Server did not start within 40 seconds. Diagnosing...
echo [%date% %time%] Server failed to listen (PID %SERVER_PID%) >> "%LOGFILE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%SERVER_DIR%Server.log'; $q='%SERVER_PORT%'; $c=@(); if(Test-Path -LiteralPath $p){$c=Get-Content -LiteralPath $p -Tail 20}; $txt=$c -join ' '; if($c.Count -eq 0){Write-Host '[DIAG] The server exited without writing Server.log. This usually means the Visual C++ Redistributable is missing - install from https://aka.ms/vs/17/release/vc_redist.x64.exe' -ForegroundColor Yellow} elseif($txt -match '(?i)(invalid auth|authentication failed|auth.*(invalid|wrong|rejected|missing))'){Write-Host '[DIAG] AuthKey is invalid or empty. Get one at https://keymaster.beammp.com and set it in your .env file (BEAMMP_AUTHKEY=...).' -ForegroundColor Yellow} elseif($txt -match '(?i)(bind|already in use|address already|access denied|permission denied)'){Write-Host ('[DIAG] Port ' + $q + ' is already in use. Close the other program or change Port in ServerConfig.toml.') -ForegroundColor Yellow} elseif($txt -match '(?i)(0xc000007b|vcruntime140|msvcp|vc_redist)'){Write-Host '[DIAG] Visual C++ Redistributable is missing - install from https://aka.ms/vs/17/release/vc_redist.x64.exe' -ForegroundColor Yellow} elseif($txt -match '(?i)(keymaster|backend|timeout|unreachable)'){Write-Host '[DIAG] Could not reach the BeamMP backend. Check your internet connection and firewall.' -ForegroundColor Yellow} elseif($txt -match '(?i)(map|level).*(missing|invalid|not found)'){Write-Host '[DIAG] The configured map or level was not found. Check the Map setting in ServerConfig.toml.' -ForegroundColor Yellow} else {Write-Host '[DIAG] Unknown error. Last server log lines:' -ForegroundColor Yellow; $c | Select-Object -Last 5 | ForEach-Object {Write-Host ('    ' + $_)}}"
echo [%date% %time%] Diagnostic printed >> "%LOGFILE%"
if defined SERVER_PID taskkill /PID %SERVER_PID% /F /T >nul 2>&1
pause
exit /b 1

:SERVERLIVE
echo [%date% %time%] Server is live (PID %SERVER_PID%) >> "%LOGFILE%"

:: ========================================================================================
:: 15. WATCHDOG: guarantee the server dies with the session even if this window is closed
:: Only fires after the launcher has been observed running once (so it never kills the
:: server before the game session actually begins). Also exits if the server crashes.
:: ========================================================================================
start "" /MIN powershell -NoProfile -Command "$seen=$false; $t0=[datetime]::Now; while($true){ $running=[bool](Get-Process -Name BeamMP-Launcher -ErrorAction SilentlyContinue); if($running){$seen=$true}; if($seen -and -not $running){Stop-Process -Id %SERVER_PID% -Force -ErrorAction SilentlyContinue; break}; if(-not (Get-Process -Id %SERVER_PID% -ErrorAction SilentlyContinue)){break}; if(-not $seen -and ([datetime]::Now-$t0).TotalMinutes -gt 60){break}; Start-Sleep -Seconds 2 }"

:: ========================================================================================
:: 16. PLAYER ACTIVITY TRACKER (background, reads Server.log)
:: Watches for player join/leave events, writes Logs\players.tmp for the LIVE screen,
:: and optionally posts join/leave embeds to the Discord webhook.
:: ========================================================================================
start "" /MIN powershell -NoProfile -Command "$sid=%SERVER_PID%; $posF='%SERVER_DIR%Logs\serverlog.pos'; $stateF='%SERVER_DIR%Logs\players.tmp'; $logF='%SERVER_DIR%Server.log'; $whF='%SERVER_DIR%webhook.txt'; $players=@{}; $off=0; if(Test-Path -LiteralPath $posF){$off=[long](Get-Content -LiteralPath $posF -Raw)}; while($true){ if($sid -and -not (Get-Process -Id $sid -ErrorAction SilentlyContinue)){break}; if(Test-Path -LiteralPath $logF){ try{ $fs=[IO.File]::Open($logF,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite); if($fs.Length -lt $off){$off=0}; $fs.Position=$off; $sr=New-Object IO.StreamReader($fs); $t=$sr.ReadToEnd(); $off=$fs.Position; $sr.Close(); $fs.Dispose(); if($t){ foreach($ln in ($t -split ([string][char]10))){ if($ln -match ('Player '+[char]34+'(.+?)'+[char]34+'.*?joined')){ $nm=$Matches[1]; if(-not $players.ContainsKey($nm)){ $players[$nm]=$true; if(Test-Path -LiteralPath $whF){$u=(Get-Content -LiteralPath $whF -Raw).Trim(); if($u -like 'https://discord.com/api/webhooks/*'){$b=@{embeds=@(@{title='K BNG M Hoster';description=('Player joined: '+$nm);color=3066993})}|ConvertTo-Json -Depth 10; try{Invoke-RestMethod -Uri $u -Method Post -Body $b -ContentType 'application/json'|Out-Null}catch{}}} }; continue }; if($ln -match ('Player '+[char]34+'(.+?)'+[char]34+'.*?left')){ $nm=$Matches[1]; if($players.ContainsKey($nm)){ $players.Remove($nm); if(Test-Path -LiteralPath $whF){$u=(Get-Content -LiteralPath $whF -Raw).Trim(); if($u -like 'https://discord.com/api/webhooks/*'){$b=@{embeds=@(@{title='K BNG M Hoster';description=('Player left: '+$nm);color=15158332})}|ConvertTo-Json -Depth 10; try{Invoke-RestMethod -Uri $u -Method Post -Body $b -ContentType 'application/json'|Out-Null}catch{}}} } } } }; Set-Content -LiteralPath $posF -Value $off; $last= if($players.Count){($players.Keys -join ', ')}else{'-'}; Set-Content -LiteralPath $stateF -Value ('Players online: '+$players.Count+' - in-game: '+$last) }catch{} }; Start-Sleep -Seconds 3 }"

:: ========================================================================================
:: 17. OPTIONAL DISCORD WEBHOOK (opt-in: only if webhook.txt exists next to the .exe)
:: ========================================================================================
set "WEBHOOK_URL="
if exist "%SERVER_DIR%webhook.txt" (
    for /f "usebackq delims=" %%U in ("%SERVER_DIR%webhook.txt") do set "WEBHOOK_URL=%%U"
)
if defined WEBHOOK_URL (
    if not "%WEBHOOK_URL%"=="YOUR_DISCORD_WEBHOOK_URL_HERE" (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "$u='%WEBHOOK_URL%'; if($u -like 'https://discord.com/api/webhooks/*'){ $t=(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); $b=@{embeds=@(@{title='K BNG M Hoster [ONLINE]'; description='Server is now live.'; color=3066993; timestamp=$t})}|ConvertTo-Json -Depth 10; try{Invoke-RestMethod -Uri $u -Method Post -Body $b -ContentType 'application/json'}catch{} }" >nul 2>&1
    )
)

:: ========================================================================================
:: 18. LIVE UI
:: ========================================================================================
color 0A
cls
echo =================================================================
echo    SERVER IS LIVE!
echo    Server Name : %SERVER_NAME%
echo    Creator     : Kinan (Discord: @raed713)
echo    Port        : %SERVER_PORT%
echo.
echo    Leave this window open. Closing it stops the server.
echo =================================================================

:: ========================================================================================
:: 19. VOICE ANNOUNCEMENT (best-effort; skipped if System.Speech is unavailable)
:: ========================================================================================
powershell -NoProfile -Command "try { Add-Type -AssemblyName System.Speech -ErrorAction Stop; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.Speak('K BNG M Hoster is online.') } catch { }" >nul 2>&1

:: ========================================================================================
:: 20. LAUNCH THE GAME LAUNCHER AND WAIT FOR THE SESSION TO END
:: Live player count is shown as soon as the tracker has something to report.
:: ========================================================================================
set "PLAYERSTATE="
start "" "%APPDATA%\BeamMP-Launcher\BeamMP-Launcher.exe"
:WAITSESSION
tasklist /FI "IMAGENAME eq BeamMP-Launcher.exe" | find /I "BeamMP-Launcher.exe" >nul 2>&1
if errorlevel 1 goto SESSIONEND
if exist "%SERVER_DIR%Logs\players.tmp" (
    for /f "usebackq delims=" %%P in ("%SERVER_DIR%Logs\players.tmp") do call :SHOWSTATE "%%P"
)
timeout /t 5 /nobreak >nul
goto WAITSESSION

:: ========================================================================================
:: 21. SESSION ENDED - STOP ONLY THIS SERVER INSTANCE
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

:: ========================================================================================
:: 22. UTILITIES (reached via goto from section 3 or call from the session loop)
:: ========================================================================================

:: Updates the window title + prints a line only when the player state changes.
:SHOWSTATE
set "NEWSTATE=%~1"
if "%NEWSTATE%"=="%PLAYERSTATE%" exit /b
set "PLAYERSTATE=%NEWSTATE%"
title K BNG M Hoster - %NEWSTATE%
echo    %NEWSTATE%
exit /b

:: Usage / help screen.
:USAGE
cls
color 0B
echo ============================================================
echo   K BNG M Hoster v0.4 - Usage
echo ============================================================
echo   Play_BeamMP.bat          Start the server and host a session
echo   Play_BeamMP.bat mods     Open the Mod Manager
echo   Play_BeamMP.bat help     Show this help
echo.
echo   Setup: copy .env.example to .env and set BEAMMP_AUTHKEY
echo   (or set the BEAMMP_AUTHKEY environment variable).
echo   One-time key: https://keymaster.beammp.com
echo.
pause
exit /b 0

:: Mod Manager: list, disable, enable, scan and open Resources\Client.
:MODMENU
powershell -NoProfile -ExecutionPolicy Bypass -Command "$client='%SERVER_DIR%Resources\Client'; $backup='%SERVER_DIR%Backups\mods'; $qroot='%SERVER_DIR%Quarantine'; if(-not(Test-Path -LiteralPath $client)){Write-Host '[ERROR] Resources\Client folder not found.' -ForegroundColor Red; Read-Host 'Press Enter to exit'; exit 1}; $mj=$client+'\mods.json'; if(Test-Path -LiteralPath $mj){$raw=Get-Content -LiteralPath $mj -Raw; if($raw -match '^\s*null\s*$'){Set-Content -LiteralPath $mj -Value '[]'}}; do{Clear-Host; Write-Host '============================================================' -ForegroundColor Cyan; Write-Host '   K BNG M Hoster v0.4 - Mod Manager (Resources\Client)' -ForegroundColor Cyan; Write-Host '============================================================' -ForegroundColor Cyan; $mods=@(Get-ChildItem -LiteralPath $client -File -ErrorAction SilentlyContinue); if($mods.Count -eq 0){Write-Host '   (no mods installed)' -ForegroundColor DarkGray}; for($i=0;$i -lt $mods.Count;$i++){ $mb='{0:N1}' -f ($mods[$i].Length/1MB); $fl=''; if($mods[$i].Extension -in '.exe','.vbs','.cmd','.scr','.pif'){$fl='   <-- SUSPICIOUS'}; Write-Host ('   [{0,2}] {1}  ({2} MB){3}' -f ($i+1),$mods[$i].Name,$mb,$fl) }; $dis=@(); if(Test-Path -LiteralPath $backup){$dis=@(Get-ChildItem -LiteralPath $backup -File -ErrorAction SilentlyContinue)}; if($dis.Count -gt 0){Write-Host '   -- Disabled (in Backups\mods) --'; for($i=0;$i -lt $dis.Count;$i++){Write-Host ('   [E{0}] {1}' -f ($i+1),$dis[$i].Name)}}; Write-Host ''; Write-Host '   D<n> disable  |  E<n> enable  |  S scan  |  O open folder  |  X exit'; $c=Read-Host '   Choice'; if($c -match '^[Dd](\d+)$'){ $n=[int]$Matches[1]; if($n -ge 1 -and $n -le $mods.Count){ if(-not(Test-Path -LiteralPath $backup)){New-Item -ItemType Directory -Path $backup -Force|Out-Null}; try{Move-Item -LiteralPath $mods[$n-1].FullName -Destination (Join-Path $backup $mods[$n-1].Name) -Force; Write-Host ('Disabled: '+$mods[$n-1].Name) -ForegroundColor Green}catch{Write-Host 'Could not move file (is it in use?).' -ForegroundColor Red}; Start-Sleep -Milliseconds 600 } } elseif($c -match '^[Ee](\d+)$'){ $n=[int]$Matches[1]; if($n -ge 1 -and $n -le $dis.Count){ try{Move-Item -LiteralPath $dis[$n-1].FullName -Destination $client -Force; Write-Host ('Enabled: '+$dis[$n-1].Name) -ForegroundColor Green}catch{Write-Host 'Could not move file.' -ForegroundColor Red}; Start-Sleep -Milliseconds 600 } } elseif($c -match '^[Ss]'){ Write-Host 'Scanning Resources\Client...'; $s=@(); $s+=Get-ChildItem -LiteralPath $client -Recurse -File -ErrorAction SilentlyContinue | Where-Object{$_.Extension -in '.exe','.vbs','.cmd','.scr','.pif'}; Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue; Get-ChildItem -LiteralPath $client -Recurse -Filter *.zip -File -ErrorAction SilentlyContinue | ForEach-Object{ if($_.Length -eq 0){Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue; return}; try{$a=[IO.Compression.ZipFile]::OpenRead($_.FullName); $bad=$false; foreach($e in $a.Entries){if($e.FullName -match '\.(exe|vbs|cmd|scr|pif)$'){$bad=$true; break}}; $a.Dispose(); if($bad){$s+=$_}}catch{} }; if($s.Count){$q=Join-Path $qroot ('modscan-'+ (Get-Date -Format 'yyyyMMdd-HHmmss')); New-Item -ItemType Directory -Path $q -Force|Out-Null; foreach($f in $s){try{Move-Item -LiteralPath $f.FullName -Destination $q -Force -ErrorAction Stop}catch{}}; Write-Host ('[SECURITY] '+$s.Count+' suspect file(s) quarantined.') -ForegroundColor Yellow}else{Write-Host 'Scan clean - no suspicious files found.' -ForegroundColor Green}; Start-Sleep -Milliseconds 1000 } elseif($c -match '^[Oo]'){ Start-Process explorer.exe -ArgumentList ([char]34 + $client + [char]34) } elseif($c -match '^[Xx]'){ break } else { Write-Host 'Invalid choice.' -ForegroundColor Yellow; Start-Sleep -Milliseconds 400 } }while($true)"
exit /b 0
