# ========================================================================================
# K BNG M Hoster v0.3 - PowerShell launcher (fixed rewrite)
# Purpose: start a BeamMP server and stop it the moment the game session ends.
#
# Optional: drop your Discord webhook URL into "webhook.txt" (next to this file)
# to announce server online/offline. Leave it out to disable.
# ========================================================================================

$ErrorActionPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------------------
# 1. RESOLVE THE REAL SERVER DIRECTORY
# ---------------------------------------------------------------------------------------
$ServerDir = (Get-Location).Path.TrimEnd('\') + '\'
if (-not (Test-Path -LiteralPath ($ServerDir + 'BeamMP-Server.exe'))) {
    $ServerDir = $PSScriptRoot.TrimEnd('\') + '\'
}

if (-not (Test-Path -LiteralPath ($ServerDir + 'BeamMP-Server.exe'))) {
    Write-Host "[ERROR] BeamMP-Server.exe was not found in:" -ForegroundColor Red
    Write-Host "        $ServerDir"
    Write-Host ""
    Write-Host "Please run the launcher from inside your K BNG M Hoster folder!"
    Read-Host "Press Enter to exit"
    exit 1
}
if (-not (Test-Path -LiteralPath ($ServerDir + 'ServerConfig.toml'))) {
    Write-Host "[ERROR] ServerConfig.toml was not found in:" -ForegroundColor Red
    Write-Host "        $ServerDir"
    Read-Host "Press Enter to exit"
    exit 1
}
$launcherPath = Join-Path $env:APPDATA 'BeamMP-Launcher\BeamMP-Launcher.exe'
if (-not (Test-Path -LiteralPath $launcherPath)) {
    Write-Host "[ERROR] BeamMP-Launcher.exe was not found at:" -ForegroundColor Red
    Write-Host "        $launcherPath"
    Write-Host ""
    Write-Host "This tool requires the official BeamMP Launcher to detect your game session."
    Write-Host "Please install it first, then run this tool again."
    Read-Host "Press Enter to exit"
    exit 1
}
Set-Location -LiteralPath $ServerDir

# ---------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------
function Write-Log([string]$Message) {
    $logDir = $ServerDir + 'Logs'
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    Add-Content -LiteralPath ($logDir + '\launcher.log') -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

function Speak([string]$Text) {
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $synth.Speak($Text)
    } catch { }
}

function Send-Webhook([string]$Title, [string]$Description, [int]$Color) {
    $whFile = $ServerDir + 'webhook.txt'
    if (-not (Test-Path -LiteralPath $whFile)) { return }
    $url = (Get-Content -LiteralPath $whFile -Raw).Trim()
    if (-not $url -or $url -like 'YOUR*') { return }
    if ($url -notlike 'https://discord.com/api/webhooks/*') {
        Write-Log "Webhook ignored: URL does not look like a Discord webhook"
        return
    }
    $body = @{
        embeds = @(@{
            title       = $Title
            description = $Description
            color       = $Color
            timestamp   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        })
    } | ConvertTo-Json -Depth 10
    try {
        Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType 'application/json' | Out-Null
    } catch {
        Write-Log "Webhook failed: $($_.Exception.Message)"
    }
}

Write-Log "===== Launcher started ====="

# ---------------------------------------------------------------------------------------
# 2. EULA GATEWAY
# ---------------------------------------------------------------------------------------
Clear-Host
Write-Host "===============================================================================" -ForegroundColor Yellow
Write-Host "              K BNG M Hoster - END USER LICENSE AGREEMENT" -ForegroundColor Yellow
Write-Host "===============================================================================" -ForegroundColor Yellow
Write-Host " Owner / Creator: Kinan (Discord: @raed713)"
Write-Host ""
Write-Host " TERMS OF SERVICE:"
Write-Host " 1. OWNERSHIP: This tool is the intellectual property of Kinan."
Write-Host " 2. DISTRIBUTION: Re-uploading, redistributing, or selling is STRICTLY PROHIBITED."
Write-Host " 3. TAMPERING: Editing, obfuscating, or removing Kinan's name is ILLEGAL."
Write-Host " 4. FAKING: Claiming ownership will result in a permanent ban."
Write-Host "===============================================================================" -ForegroundColor Yellow
Write-Host ""
$answer = Read-Host "Do you ACCEPT these terms and acknowledge Kinan as the owner (Y/N)"
if ($answer -notmatch '^\s*[Yy]') {
    Write-Host ""
    Write-Host "[ABORTED] You must accept the license agreement to run K BNG M Hoster."
    Write-Log "EULA rejected"
    Start-Sleep -Seconds 3
    exit 0
}
Write-Log "EULA accepted"

# ---------------------------------------------------------------------------------------
# 3. BANNER
# ---------------------------------------------------------------------------------------
Clear-Host
Write-Host "==================================================================================================" -ForegroundColor Cyan
Write-Host "    K   K   BBB   N   N   GGG     M   M   H   H   OOO   SSS  TTTTT  EEE  RRRR" -ForegroundColor Cyan
Write-Host "    K  K    B  B  NN  N  G        MM MM   H   H  O   O S       T    E    R   R" -ForegroundColor Cyan
Write-Host "    KKK     BBB   N N N  G  GG    M M M   HHHHH  O   O  SSS    T    EEE  RRRR" -ForegroundColor Cyan
Write-Host "    K  K    B  B  N  NN  G   G    M   M   H   H  O   O     S   T    E    R R" -ForegroundColor Cyan
Write-Host "    K   K   BBB   N   N   GGG     M   M   H   H   OOO  SSSS    T    EEE  R  RR" -ForegroundColor Cyan
Write-Host "==================================================================================================" -ForegroundColor Cyan
Write-Host "    K BNG M Hoster v0.3 - Node Architecture"
Write-Host "    Sole Creator: Kinan | Official Discord: @raed713"
Write-Host "==================================================================================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------------------
# 4. SECURITY SCAN (non-destructive, logged)
# ---------------------------------------------------------------------------------------
$clientDir = $ServerDir + 'Resources\Client'
$quarantineDir = $ServerDir + 'Quarantine'
if (-not (Test-Path -LiteralPath $quarantineDir)) { New-Item -ItemType Directory -Path $quarantineDir -Force | Out-Null }
if (Test-Path -LiteralPath $clientDir) {
    Write-Host "[*] Running security scan on Resources\Client..."
    $suspects = @()
    $suspects += Get-ChildItem -Path $clientDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.exe', '.vbs', '.cmd', '.scr', '.pif' }

    # Also inspect the inside of .zip mods
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zips = Get-ChildItem -Path $clientDir -Recurse -Filter *.zip -File -ErrorAction SilentlyContinue
    foreach ($z in $zips) {
        if ($z.Length -eq 0) {
            Remove-Item -LiteralPath $z.FullName -Force -ErrorAction SilentlyContinue
            continue
        }
        try {
            $archive = [System.IO.Compression.ZipFile]::OpenRead($z.FullName)
            $bad = $false
            foreach ($entry in $archive.Entries) {
                if ($entry.FullName -match '\.(exe|vbs|cmd|scr|pif)$') { $bad = $true; break }
            }
            $archive.Dispose()
            if ($bad) { $suspects += $z }
        } catch { }
    }

    if ($suspects.Count -gt 0) {
        $dest = Join-Path $quarantineDir (Get-Date -Format 'yyyyMMdd-HHmmss')
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        foreach ($f in $suspects) {
            if (Test-Path -LiteralPath $f.FullName) {
                try {
                    Move-Item -LiteralPath $f.FullName -Destination $dest -Force -ErrorAction Stop
                    Write-Log "QUARANTINE: $($f.FullName)"
                } catch { }
            }
        }
        Write-Host "[SECURITY] $($suspects.Count) suspect file(s) quarantined."
    }
}

# ---------------------------------------------------------------------------------------
# 5. STABLE SERVER NAME + PORT (read from config, no random node id)
# ---------------------------------------------------------------------------------------
$serverName = 'K BNG M Server'
$serverPort = 30814
$cfgContent = Get-Content -LiteralPath ($ServerDir + 'ServerConfig.toml') -ErrorAction SilentlyContinue
$nameLine = $cfgContent | Select-String -Pattern '^\s*Name\s*=\s*"(.*)"' | Select-Object -First 1
if ($nameLine) { $serverName = $nameLine.Matches[0].Groups[1].Value }
$portLine = $cfgContent | Select-String -Pattern '^\s*Port\s*=\s*(\d+)' | Select-Object -First 1
if ($portLine) { $serverPort = [int]$portLine.Matches[0].Groups[1].Value }

# ---------------------------------------------------------------------------------------
# 6. REPAIR INVALID mods.json (BeamMP expects a JSON array, not "null")
# ---------------------------------------------------------------------------------------
$modsJson = $clientDir + '\mods.json'
if (Test-Path -LiteralPath $modsJson) {
    $raw = Get-Content -LiteralPath $modsJson -Raw -ErrorAction SilentlyContinue
    if ($raw -match '^\s*null\s*$') {
        Set-Content -LiteralPath $modsJson -Value '[]'
        Write-Log "Repaired mods.json (was 'null')"
    }
}

# ---------------------------------------------------------------------------------------
# 7. START THE SERVER (capture PID so we can kill exactly this instance)
# ---------------------------------------------------------------------------------------
Write-Host "[*] Starting BeamMP server..."
$server = Start-Process -FilePath ($ServerDir + 'BeamMP-Server.exe') -WorkingDirectory $ServerDir -WindowStyle Minimized -PassThru
Write-Log "Server process started (PID $($server.Id))"

# ---------------------------------------------------------------------------------------
# 8. WAIT UNTIL THE SERVER IS ACTUALLY LISTENING (real "LIVE" check)
# ---------------------------------------------------------------------------------------
$ready = $false
for ($i = 0; $i -lt 20; $i++) {
    if ($server.HasExited) { break }
    if (Get-NetTCPConnection -LocalPort $serverPort -State Listen -ErrorAction SilentlyContinue) { $ready = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $ready) {
    Write-Host "[ERROR] Server did not start. Check that your AuthKey is set correctly in ServerConfig.toml." -ForegroundColor Red
    Write-Log "Server failed to listen (PID $($server.Id))"
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Log "Server is live (PID $($server.Id))"

# ---------------------------------------------------------------------------------------
# 9. WATCHDOG: guarantee the server dies with the session even if this window is closed
# Only fires after the launcher has been observed running once (so it never kills the
# server before the game session actually begins).
# ---------------------------------------------------------------------------------------
$watchdogCmd = '$seen = $false; while ($true) { $running = [bool](Get-Process -Name BeamMP-Launcher -ErrorAction SilentlyContinue); if ($running) { $seen = $true }; if ($seen -and -not $running) { Stop-Process -Id ' + $server.Id + ' -Force -ErrorAction SilentlyContinue; break }; Start-Sleep -Seconds 2 }'
Start-Process powershell -WindowStyle Hidden -ArgumentList ('-NoProfile -Command "' + $watchdogCmd + '"') | Out-Null

# ---------------------------------------------------------------------------------------
# 10. OPTIONAL DISCORD WEBHOOK (opt-in via webhook.txt)
# ---------------------------------------------------------------------------------------
Send-Webhook 'K BNG M Hoster [ONLINE]' 'Server is now live.' 3066993

# ---------------------------------------------------------------------------------------
# 11. LIVE UI
# ---------------------------------------------------------------------------------------
Clear-Host
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "    SERVER IS LIVE!" -ForegroundColor Green
Write-Host "    Server Name : $serverName"
Write-Host "    Creator     : Kinan (Discord: @raed713)"
Write-Host "    Port        : $serverPort"
Write-Host ""
Write-Host "    Leave this window open. Closing it stops the server."
Write-Host "=================================================================" -ForegroundColor Green

# ---------------------------------------------------------------------------------------
# 12. VOICE ANNOUNCEMENT (best-effort)
# ---------------------------------------------------------------------------------------
Speak 'K BNG M Hoster is online.'

# ---------------------------------------------------------------------------------------
# 13. LAUNCH THE GAME LAUNCHER AND WAIT FOR THE SESSION TO END
# ---------------------------------------------------------------------------------------
Start-Process -FilePath $launcherPath | Out-Null
while (Get-Process -Name 'BeamMP-Launcher' -ErrorAction SilentlyContinue) {
    Start-Sleep -Seconds 5
}

# ---------------------------------------------------------------------------------------
# 14. SESSION ENDED - STOP ONLY THIS SERVER INSTANCE
# ---------------------------------------------------------------------------------------
Write-Host ""
Write-Host "=================================================================" -ForegroundColor Red
Write-Host " Game session ended. Stopping server..." -ForegroundColor Red
Write-Host "=================================================================" -ForegroundColor Red
Write-Log "Session ended"
if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
Write-Log "Server stopped"
Send-Webhook 'K BNG M Hoster [OFFLINE]' 'Server is now offline.' 15158332
Speak 'Session closed.'
exit 0
