# ========================================================================================
# K BNG M Hoster v0.5 - Simplest Edition
# Purpose: let anyone with zero technical skill host a BeamMP server.
#
# This file is the SINGLE source of truth. Start_Here.bat and Play_BeamMP.bat only
# launch this file.
#
# Optional: drop your Discord webhook URL into "webhook.txt" (next to this file)
# to announce server online/offline and player join/leave events.
# ========================================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Mode = '',   # friendly name: start | mods | fix | help | setup
    [switch]$Mods,        # open the Mod Manager directly
    [switch]$Help,        # show usage
    [switch]$Setup,       # force the first-run setup wizard
    [switch]$Fix          # open the Help / Fix menu directly
)

$ErrorActionPreference = 'SilentlyContinue'

# Accept friendly mode names passed by the .bat launchers (e.g. "Play_BeamMP.bat fix")
if ($Mode -eq 'mods') { $Mods = $true }
elseif ($Mode -eq 'fix') { $Fix = $true }
elseif ($Mode -eq 'help') { $Help = $true }
elseif ($Mode -eq 'setup') { $Setup = $true }

# ---------------------------------------------------------------------------------------
# 1. RESOLVE THE REAL SERVER DIRECTORY
# ---------------------------------------------------------------------------------------
$ServerDir = (Get-Location).Path.TrimEnd('\') + '\'
if (-not (Test-Path -LiteralPath ($ServerDir + 'BeamMP-Server.exe'))) {
    $ServerDir = $PSScriptRoot.TrimEnd('\') + '\'
}
if (-not (Test-Path -LiteralPath ($ServerDir + 'BeamMP-Server.exe'))) {
    Write-Host "I could not find the server program (BeamMP-Server.exe)." -ForegroundColor Red
    Write-Host "Make sure you run this from inside the K BNG M Hoster folder."
    Read-Host "Press Enter to exit"
    exit 1
}
if (-not (Test-Path -LiteralPath ($ServerDir + 'ServerConfig.toml'))) {
    Write-Host "I could not find the server settings file (ServerConfig.toml)." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
$launcherPath = Join-Path $env:APPDATA 'BeamMP-Launcher\BeamMP-Launcher.exe'
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

function Show-Usage {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  K BNG M Hoster v0.5 - Usage" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Just double-click Start_Here.bat - that's all."
    Write-Host ""
    Write-Host "  .\Play_BeamMP.ps1              Normal start"
    Write-Host "  .\Play_BeamMP.ps1 -Setup       First-time setup wizard"
    Write-Host "  .\Play_BeamMP.ps1 -Mods        Mod Manager"
    Write-Host "  .\Play_BeamMP.ps1 -Fix         Help / Fix Problems"
    Write-Host "  .\Play_BeamMP.ps1 -Help        This screen"
    Write-Host ""
    Write-Host "  Your key lives in the .env file (BEAMMP_AUTHKEY=...)."
    Write-Host "  Get one at: https://keymaster.beammp.com"
    Read-Host "Press Enter to exit"
}

function Show-Banner {
    Write-Host "==================================================================================================" -ForegroundColor Cyan
    Write-Host "    K   K   BBB   N   N   GGG     M   M   H   H   OOO   SSS  TTTTT  EEE  RRRR" -ForegroundColor Cyan
    Write-Host "    K  K    B  B  NN  N  G        MM MM   H   H  O   O S       T    E    R   R" -ForegroundColor Cyan
    Write-Host "    KKK     BBB   N N N  G  GG    M M M   HHHHH  O   O  SSS    T    EEE  RRRR" -ForegroundColor Cyan
    Write-Host "    K  K    B  B  N  NN  G   G    M   M   H   H  O   O     S   T    E    R R" -ForegroundColor Cyan
    Write-Host "    K   K   BBB   N   N   GGG     M   M   H   H   OOO  SSSS    T    EEE  R  RR" -ForegroundColor Cyan
    Write-Host "==================================================================================================" -ForegroundColor Cyan
    Write-Host "    K BNG M Hoster v0.5 - Simplest Edition"
    Write-Host "    Sole Creator: Kinan | Official Discord: @raed713"
    Write-Host "==================================================================================================" -ForegroundColor Cyan
    Write-Host ""
}

# Waits up to N seconds for a single key press. Returns the char or $null on timeout.
function Wait-OrKey([int]$Seconds, [string]$Prompt) {
    Write-Host $Prompt -NoNewline
    for ($i = 0; $i -lt $Seconds; $i++) {
        try {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                return [string]$key.KeyChar
            }
        } catch { }
        Start-Sleep -Seconds 1
    }
    return $null
}

function Get-ServerPort {
    $cfgPath = $ServerDir + 'ServerConfig.toml'
    $m = Select-String -LiteralPath $cfgPath -Pattern '^\s*Port\s*=\s*(\d+)' | Select-Object -First 1
    if ($m) { return [int]$m.Matches[0].Groups[1].Value }
    return 30813
}

function Get-FreePort {
    $start = 30813
    for ($p = $start; $p -lt ($start + 200); $p++) {
        if (-not (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)) { return $p }
    }
    return $start
}

function Test-AuthKeyConfigured {
    if ($env:BEAMMP_AUTHKEY) { return $true }
    if (Test-Path -LiteralPath ($ServerDir + '.env')) { return $true }
    $m = Select-String -LiteralPath ($ServerDir + 'ServerConfig.toml') -Pattern '^\s*AuthKey\s*=\s*"[^"]+"' | Select-Object -First 1
    return [bool]$m
}

function Get-BeamNGPath {
    $candidates = @()
    $log = Join-Path $env:APPDATA 'BeamMP-Launcher\Launcher.log'
    if (Test-Path -LiteralPath $log) {
        $m = Select-String -LiteralPath $log -Pattern 'GameDir from BeamNG.Drive.ini:\s*(.+?)\s*$' | Select-Object -Last 1
        if ($m) { $candidates += $m.Matches[0].Groups[1].Value.Trim() }
    }
    $candidates += "$env:USERPROFILE\Documents\BeamNG.drive"
    foreach ($base in @('C:\Program Files (x86)\Steam\steamapps\common', 'D:\SteamLibrary\steamapps\common', 'E:\SteamLibrary\steamapps\common', 'C:\SteamLibrary\steamapps\common')) {
        $candidates += (Join-Path $base 'BeamNG.drive')
    }
    foreach ($c in $candidates) {
        $exe = Join-Path $c 'BeamNG.drive.exe'
        if (Test-Path -LiteralPath $exe) { return $exe }
    }
    return ''
}

function Test-FirewallRule {
    try {
        $rules = Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*BeamMP*' -or $_.DisplayName -like '*K BNG*' }
        return [bool]$rules
    } catch { }
    return $false
}

function Add-FirewallRule {
    $serverExe = $ServerDir + 'BeamMP-Server.exe'
    $script = "New-NetFirewallRule -DisplayName 'K BNG M Hoster' -Direction Inbound -Action Allow -Program '$serverExe' -ErrorAction SilentlyContinue"
    $tmp = Join-Path $env:TEMP ('kbfw-' + [guid]::NewGuid().ToString('N') + '.ps1')
    Set-Content -LiteralPath $tmp -Value $script
    try {
        Write-Host "  A Windows security window will appear. Click 'Yes' to allow the server." -ForegroundColor Yellow
        Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $tmp + '"') -Verb RunAs -Wait | Out-Null
        Write-Host "  Firewall rule added." -ForegroundColor Green
    } catch {
        Write-Host "  Could not add the firewall rule (was the Windows window cancelled?)." -ForegroundColor Yellow
    }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

function Update-Config {
    param([string]$Name = '', [int]$Players = 0)
    $cfgPath = $ServerDir + 'ServerConfig.toml'
    $lines = @(Get-Content -LiteralPath $cfgPath)
    $lines = $lines | ForEach-Object {
        if ($Name -and $_ -match '^\s*Name\s*=') { 'Name = "' + $Name + '"' }
        elseif ($Players -gt 0 -and $_ -match '^\s*MaxPlayers\s*=') { "MaxPlayers = $Players" }
        else { $_ }
    }
    Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
}

# ---------------------------------------------------------------------------------------
# EULA (shown once, then remembered)
# ---------------------------------------------------------------------------------------
function Show-Eula {
    $marker = $ServerDir + 'Logs\eula.accepted'
    if (Test-Path -LiteralPath $marker) { return $true }
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
    $answer = Read-Host "Type Y to accept (required to use this tool) or N to exit"
    if ($answer -match '^\s*[Yy]') {
        Set-Content -LiteralPath $marker -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Write-Log "EULA accepted"
        return $true
    }
    Write-Host ""
    Write-Host "You must accept the license to use K BNG M Hoster."
    Write-Log "EULA rejected"
    Read-Host "Press Enter to exit"
    exit 0
}

# ---------------------------------------------------------------------------------------
# FIRST-RUN SETUP WIZARD (the tool does all the file editing)
# ---------------------------------------------------------------------------------------
function Show-SetupWizard {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   K BNG M Hoster - First-Time Setup" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Welcome! This takes about 1 minute and I do all the work."
    Write-Host "  You only need your free server key."
    Read-Host "  Press Enter to begin"

    # --- Step 1: the server key -------------------------------------------
    $key = $env:BEAMMP_AUTHKEY
    if ($key) {
        Write-Host ""
        Write-Host "  I found your key in the BEAMMP_AUTHKEY environment variable - great!" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  STEP 1 of 2: Your free server key" -ForegroundColor Green
        Write-Host "  This key is how BeamMP knows you own your server. It's free and takes 1 minute."
        if ($env:KBNG_TEST -ne '1') {
            Write-Host "  I'm opening the key website in your browser now..." -ForegroundColor Yellow
            Start-Process 'https://keymaster.beammp.com'
        }
        $done = $false
        while (-not $done) {
            Write-Host ""
            Write-Host "  On the website: sign in, generate a key, then copy it (Ctrl+C)."
            $key = Read-Host "  Paste your key here (right-click to paste)"
            $key = $key.Trim().Trim('"', "'")
            if ($key -match '^[A-Za-z0-9\-]{8,64}$') {
                $done = $true
            } elseif (-not $key) {
                $skip = Read-Host "  You left it empty. Type S to skip, or press Enter to try again"
                if ($skip -match '^[Ss]') { $done = $true }
            } else {
                Write-Host "  That doesn't look like a valid key. It should only contain letters, numbers and dashes." -ForegroundColor Red
                $again = Read-Host "  Press Enter to try again, or type S to skip"
                if ($again -match '^[Ss]') { $done = $true }
            }
        }
        if ($key) {
            Set-Content -LiteralPath ($ServerDir + '.env') -Value ("BEAMMP_AUTHKEY=" + $key)
            Write-Host "  Saved. I will never show your key again." -ForegroundColor Green
        }
    }

    # --- Step 2: auto-configure the server ---------------------------------
    Write-Host ""
    Write-Host "  STEP 2 of 2: Server settings" -ForegroundColor Green
    Write-Host "  I'm now setting up the server with sensible defaults..."
    $cfgPath = $ServerDir + 'ServerConfig.toml'
    $backupDir = $ServerDir + 'Backups'
    if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    Copy-Item -LiteralPath $cfgPath -Destination (Join-Path $backupDir ("ServerConfig-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".toml")) -Force
    $port = Get-FreePort
    $lines = @(Get-Content -LiteralPath $cfgPath)
    $lines = $lines | ForEach-Object {
        if ($_ -match '^\s*Name\s*=') { 'Name = "K BNG M Server"' }
        elseif ($_ -match '^\s*Port\s*=') { "Port = $port" }
        elseif ($_ -match '^\s*MaxPlayers\s*=') { 'MaxPlayers = 10' }
        elseif ($_ -match '^\s*IP\s*=') { 'IP = "0.0.0.0"' }
        else { $_ }
    }
    Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
    Write-Log "Setup wizard finished (port $port)"
    Write-Host ""
    Write-Host "  All done! Your server will use port $port." -ForegroundColor Green
    Read-Host "  Press Enter to start your server"
    return $true
}

# ---------------------------------------------------------------------------------------
# CHANGE NAME / PLAYERS
# ---------------------------------------------------------------------------------------
function Show-ChangeSettings {
    Clear-Host
    Write-Host "Change your server settings" -ForegroundColor Cyan
    Write-Host ""
    $name = Read-Host "Server name (press Enter to keep current)"
    if ($name) {
        Update-Config -Name $name
        Write-Log "Server name changed to $name"
    }
    $players = Read-Host "Max players (press Enter to keep current)"
    if ($players -match '^\d+$') {
        Update-Config -Players ([int]$players)
        Write-Log "Max players changed to $players"
    }
    Write-Host ""
    Write-Host "Saved." -ForegroundColor Green
    Start-Sleep -Milliseconds 900
}

# ---------------------------------------------------------------------------------------
# MOD MANAGER
# ---------------------------------------------------------------------------------------
function Show-ModManager {
    $client = $ServerDir + 'Resources\Client'
    $backup = $ServerDir + 'Backups\mods'
    $qroot = $ServerDir + 'Quarantine'
    if (-not (Test-Path -LiteralPath $client)) {
        Write-Host "[ERROR] Resources\Client folder not found." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    $mj = $client + '\mods.json'
    if (Test-Path -LiteralPath $mj) {
        $raw = Get-Content -LiteralPath $mj -Raw
        if ($raw -match '^\s*null\s*$') { Set-Content -LiteralPath $mj -Value '[]' }
    }
    do {
        Clear-Host
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "   K BNG M Hoster v0.5 - Mod Manager (Resources\Client)" -ForegroundColor Cyan
        Write-Host "============================================================" -ForegroundColor Cyan
        $mods = @(Get-ChildItem -LiteralPath $client -File -ErrorAction SilentlyContinue)
        if ($mods.Count -eq 0) { Write-Host "   (no mods installed)" -ForegroundColor DarkGray }
        for ($i = 0; $i -lt $mods.Count; $i++) {
            $mb = '{0:N1}' -f ($mods[$i].Length / 1MB)
            $fl = ''
            if ($mods[$i].Extension -in '.exe', '.vbs', '.cmd', '.scr', '.pif') { $fl = '   <-- SUSPICIOUS' }
            Write-Host ("   [{0,2}] {1}  ({2} MB){3}" -f ($i + 1), $mods[$i].Name, $mb, $fl)
        }
        $dis = @()
        if (Test-Path -LiteralPath $backup) { $dis = @(Get-ChildItem -LiteralPath $backup -File -ErrorAction SilentlyContinue) }
        if ($dis.Count -gt 0) {
            Write-Host "   -- Disabled (in Backups\mods) --"
            for ($i = 0; $i -lt $dis.Count; $i++) { Write-Host ("   [E{0}] {1}" -f ($i + 1), $dis[$i].Name) }
        }
        Write-Host ""
        Write-Host "   D<n> disable  |  E<n> enable  |  S scan  |  O open folder  |  X exit"
        $c = Read-Host "   Choice"
        if ($c -match '^[Dd](\d+)$') {
            $n = [int]$Matches[1]
            if ($n -ge 1 -and $n -le $mods.Count) {
                if (-not (Test-Path -LiteralPath $backup)) { New-Item -ItemType Directory -Path $backup -Force | Out-Null }
                try {
                    Move-Item -LiteralPath $mods[$n - 1].FullName -Destination (Join-Path $backup $mods[$n - 1].Name) -Force
                    Write-Host "Disabled: $($mods[$n - 1].Name)" -ForegroundColor Green
                } catch { Write-Host "Could not move file (is it in use?)." -ForegroundColor Red }
                Start-Sleep -Milliseconds 600
            }
        } elseif ($c -match '^[Ee](\d+)$') {
            $n = [int]$Matches[1]
            if ($n -ge 1 -and $n -le $dis.Count) {
                try {
                    Move-Item -LiteralPath $dis[$n - 1].FullName -Destination $client -Force
                    Write-Host "Enabled: $($dis[$n - 1].Name)" -ForegroundColor Green
                } catch { Write-Host "Could not move file." -ForegroundColor Red }
                Start-Sleep -Milliseconds 600
            }
        } elseif ($c -match '^[Ss]') {
            Write-Host "Scanning Resources\Client..."
            $s = @()
            $s += Get-ChildItem -LiteralPath $client -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in '.exe', '.vbs', '.cmd', '.scr', '.pif' }
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath $client -Recurse -Filter *.zip -File -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Length -eq 0) { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue; return }
                try {
                    $a = [IO.Compression.ZipFile]::OpenRead($_.FullName)
                    $bad = $false
                    foreach ($e in $a.Entries) { if ($e.FullName -match '\.(exe|vbs|cmd|scr|pif)$') { $bad = $true; break } }
                    $a.Dispose()
                    if ($bad) { $s += $_ }
                } catch { }
            }
            if ($s.Count) {
                $q = Join-Path $qroot ('modscan-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
                New-Item -ItemType Directory -Path $q -Force | Out-Null
                foreach ($f in $s) { try { Move-Item -LiteralPath $f.FullName -Destination $q -Force -ErrorAction Stop } catch { } }
                Write-Host "[SECURITY] $($s.Count) suspect file(s) quarantined." -ForegroundColor Yellow
            } else {
                Write-Host "Scan clean - no suspicious files found." -ForegroundColor Green
            }
            Start-Sleep -Milliseconds 1000
        } elseif ($c -match '^[Oo]') {
            Start-Process explorer.exe -ArgumentList ('"' + $client + '"')
        } elseif ($c -match '^[Xx]') {
            break
        } else {
            Write-Host "Invalid choice." -ForegroundColor Yellow
            Start-Sleep -Milliseconds 400
        }
    } while ($true)
}

# ---------------------------------------------------------------------------------------
# UPDATE CHECKER (cached 24h, never blocks startup)
# ---------------------------------------------------------------------------------------
function Check-ForUpdates {
    $cache = $ServerDir + 'Logs\update_check.json'
    $msg = ''
    $run = $true
    if (Test-Path -LiteralPath $cache) {
        try {
            $j = Get-Content -LiteralPath $cache -Raw | ConvertFrom-Json
            if ($j.checked -and ((Get-Date) - [datetime]$j.checked).TotalHours -lt 24) { $run = $false; $msg = $j.msg }
        } catch { }
    }
    if ($run) {
        try {
            $r = Invoke-RestMethod -Uri 'https://api.github.com/repos/BeamMP/BeamMP-Server/releases/latest' -Headers @{ 'User-Agent' = 'K-BNG-M-Hoster' } -TimeoutSec 8
            $local = (Get-Item -LiteralPath ($ServerDir + 'BeamMP-Server.exe')).LastWriteTime
            $remote = [datetime]$r.published_at
            if ($remote -gt $local) {
                $msg = "[UPDATE] New BeamMP-Server $($r.tag_name) is available (published $($r.published_at)). Download: $($r.html_url)"
            }
            @{ checked = (Get-Date).ToString('o'); msg = $msg } | ConvertTo-Json | Set-Content -LiteralPath $cache
        } catch { $msg = '' }
    }
    if ($msg) { Write-Host $msg -ForegroundColor Yellow }
}

# ---------------------------------------------------------------------------------------
# STARTUP DIAGNOSTICS (explains why the server failed)
# ---------------------------------------------------------------------------------------
function Show-ServerDiagnostics {
    $log = $ServerDir + 'Server.log'
    $c = @()
    if (Test-Path -LiteralPath $log) { $c = Get-Content -LiteralPath $log -Tail 20 }
    $txt = $c -join ' '
    if ($c.Count -eq 0) {
        Write-Host "[DIAG] The server exited without writing a log. This usually means the Visual C++ runtime is missing - run 'Help / Fix Problems' to fix it." -ForegroundColor Yellow
    } elseif ($txt -match '(?i)(invalid auth|authentication failed|auth.*(invalid|wrong|rejected|missing))') {
        Write-Host "[DIAG] Your server key is wrong or missing. Run 'Help / Fix Problems' -> 'Set up my server key'." -ForegroundColor Yellow
    } elseif ($txt -match '(?i)(bind|already in use|address already|access denied|permission denied)') {
        Write-Host "[DIAG] Port $serverPort is already in use. Run 'Help / Fix Problems' -> 'Use a free port automatically'." -ForegroundColor Yellow
    } elseif ($txt -match '(?i)(0xc000007b|vcruntime140|msvcp|vc_redist)') {
        Write-Host "[DIAG] Visual C++ runtime is missing. Run 'Help / Fix Problems' -> 'Install Visual C++'." -ForegroundColor Yellow
    } elseif ($txt -match '(?i)(keymaster|backend|timeout|unreachable)') {
        Write-Host "[DIAG] I could not reach BeamMP's servers. Check your internet connection." -ForegroundColor Yellow
    } elseif ($txt -match '(?i)(map|level).*(missing|invalid|not found)') {
        Write-Host "[DIAG] The chosen map is missing. Change the Map setting in ServerConfig.toml." -ForegroundColor Yellow
    } else {
        Write-Host "[DIAG] Unknown error. Last server log lines:" -ForegroundColor Yellow
        $c | Select-Object -Last 5 | ForEach-Object { Write-Host "    $_" }
    }
}

# ---------------------------------------------------------------------------------------
# CONNECTION INFO FOR FRIENDS
# ---------------------------------------------------------------------------------------
function Get-ConnectionInfo {
    $port = Get-ServerPort
    $tail = ''
    try {
        $tailExe = 'C:\Program Files\Tailscale\tailscale.exe'
        if (Test-Path -LiteralPath $tailExe) { $tail = (& $tailExe ip -4 2>$null | Select-Object -First 1).Trim() }
        elseif (Get-Command tailscale -ErrorAction SilentlyContinue) { $tail = (& tailscale ip -4 2>$null | Select-Object -First 1).Trim() }
    } catch { }
    $public = ''
    $cache = $ServerDir + 'Logs\publicip.json'
    if (Test-Path -LiteralPath $cache) {
        try {
            $j = Get-Content -LiteralPath $cache -Raw | ConvertFrom-Json
            if ($j.ip -and ((Get-Date) - [datetime]$j.checked).TotalHours -lt 24) { $public = $j.ip }
        } catch { }
    }
    if (-not $public) {
        try {
            $public = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 8).ToString().Trim()
            @{ ip = $public; checked = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $cache
        } catch { }
    }
    return [pscustomobject]@{ Port = $port; Tailscale = $tail; Public = $public }
}

# Returns $true if we can reach our own server over IPv4 loopback (127.0.0.1).
function Test-Loopback([int]$Port) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect('127.0.0.1', $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(3000, $false)
        if ($ok -and $c.Connected) { $c.Close(); return $true }
        $c.Close()
        return $false
    } catch { return $false }
}

# ---------------------------------------------------------------------------------------
# MAIN MENU (auto-starts the server after 8 seconds)
# ---------------------------------------------------------------------------------------
function Show-MainMenu {
    Clear-Host
    Show-Banner
    Write-Host "  ==========================================================" -ForegroundColor Green
    Write-Host "   What do you want to do?" -ForegroundColor Green
    Write-Host "  ==========================================================" -ForegroundColor Green
    Write-Host "   1.  Start Server & Play"
    Write-Host "   2.  Change Server Name / Players"
    Write-Host "   3.  Mod Manager"
    Write-Host "   4.  Help / Fix Problems"
    Write-Host "   5.  Exit"
    Write-Host ""
    $k = Wait-OrKey 8 "  Press ENTER to start now (auto-starts in 8 seconds)..."
    if ($k -eq '2') { return 2 }
    if ($k -eq '3') { return 3 }
    if ($k -eq '4') { return 4 }
    if ($k -eq '5') { return 5 }
    return 1
}

# ---------------------------------------------------------------------------------------
# HELP / FIX PROBLEMS
# ---------------------------------------------------------------------------------------
function Show-FixMenu {
    do {
        Clear-Host
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "   K BNG M Hoster - Help / Fix Problems" -ForegroundColor Cyan
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Checking everything for you..."
        Write-Host ""
        $issues = @()

        if (Test-AuthKeyConfigured) { Write-Host "  [OK] Server key: present" -ForegroundColor Green } else { $issues += 'AUTHKEY'; Write-Host "  [X] Server key: missing" -ForegroundColor Red }

        if (Test-Path -LiteralPath $launcherPath) { Write-Host "  [OK] BeamMP Launcher: installed" -ForegroundColor Green } else { $issues += 'LAUNCHER'; Write-Host "  [X] BeamMP Launcher: not installed" -ForegroundColor Red }

        $game = Get-BeamNGPath
        if ($game) { Write-Host "  [OK] BeamNG.drive found" -ForegroundColor Green } else { $issues += 'BEAMNG'; Write-Host "  [X] BeamNG.drive: not found" -ForegroundColor Red }

        $port = Get-ServerPort
        $busy = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($busy) { $issues += 'PORT'; Write-Host "  [X] Port $port is in use by another program" -ForegroundColor Red } else { Write-Host "  [OK] Port $port is free" -ForegroundColor Green }

        if (Test-Path -LiteralPath "$env:WINDIR\System32\vcruntime140.dll") { Write-Host "  [OK] Visual C++ runtime: present" -ForegroundColor Green } else { $issues += 'VC'; Write-Host "  [X] Visual C++ runtime: missing" -ForegroundColor Red }

        if (Test-FirewallRule) { Write-Host "  [OK] Firewall: BeamMP-Server is allowed" -ForegroundColor Green } else { $issues += 'FW'; Write-Host "  [?] Firewall: BeamMP-Server may be blocked" -ForegroundColor Yellow }

        if (Test-Path -LiteralPath 'C:\Program Files\Tailscale\tailscale.exe') { Write-Host "  [OK] Tailscale: installed" -ForegroundColor Green } else { Write-Host "  [..] Tailscale: not installed (friends can still join via public IP)" -ForegroundColor DarkGray }

        Write-Host ""
        Write-Host "  Actions:"
        if ($issues -contains 'AUTHKEY') { Write-Host "   1.  Set up my server key" }
        if ($issues -contains 'LAUNCHER') { Write-Host "   2.  Open the BeamMP Launcher download" }
        if ($issues -contains 'PORT') { Write-Host "   3.  Use a free port automatically" }
        if ($issues -contains 'FW') { Write-Host "   4.  Add a firewall rule (asks for admin)" }
        if ($issues -contains 'VC') { Write-Host "   5.  Open the Visual C++ installer" }
        if ($issues -contains 'BEAMNG') { Write-Host "   6.  Open BeamNG.drive download" }
        Write-Host "   X.  Back to main menu"
        Write-Host ""
        $c = Read-Host "  Your choice"
        if ($c -eq '1') {
            $null = Show-SetupWizard
        } elseif ($c -eq '2') {
            Start-Process 'https://beammp.com'
        } elseif ($c -eq '3') {
            $np = Get-FreePort
            $cfgPath = $ServerDir + 'ServerConfig.toml'
            $lines = @(Get-Content -LiteralPath $cfgPath) | ForEach-Object {
                if ($_ -match '^\s*Port\s*=') { "Port = $np" } else { $_ }
            }
            Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
            Write-Log "Port changed to $np"
            Write-Host "  Done! Port changed to $np." -ForegroundColor Green
            Start-Sleep -Milliseconds 1000
        } elseif ($c -eq '4') {
            Add-FirewallRule
        } elseif ($c -eq '5') {
            Start-Process 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
        } elseif ($c -eq '6') {
            Start-Process 'https://www.beamng.com/game/'
        } elseif ($c -eq 'X' -or $c -eq 'x') {
            break
        }
    } while ($true)
}

# ---------------------------------------------------------------------------------------
# START OF THE ACTUAL PROGRAM
# ---------------------------------------------------------------------------------------
Write-Log "===== Launcher started ====="
if (-not (Test-Path -LiteralPath ($ServerDir + 'Logs'))) { New-Item -ItemType Directory -Path ($ServerDir + 'Logs') -Force | Out-Null }

# Utility switches (no EULA needed for these)
if ($Mods) { Show-ModManager; exit 0 }
if ($Fix)  { Show-FixMenu;  exit 0 }
if ($Help) { Show-Usage;    exit 0 }

$null = Show-Eula

if ($Setup) {
    $null = Show-SetupWizard
} elseif (-not (Test-AuthKeyConfigured)) {
    Write-Host ""
    Write-Host "  It looks like this is your first time here. Let me set everything up for you." -ForegroundColor Yellow
    Start-Sleep -Milliseconds 1200
    $null = Show-SetupWizard
}

# Main menu loop
while ($true) {
    $choice = Show-MainMenu
    if ($choice -eq 2) { Show-ChangeSettings; continue }
    if ($choice -eq 3) { Show-ModManager; continue }
    if ($choice -eq 4) { Show-FixMenu; continue }
    if ($choice -eq 5) { exit 0 }
    # choice 1 -> start the server
    break
}

# (internal testing hook - lets tests verify wizard/menu/config without a real server)
if ($env:KBNG_TEST -eq '1') { Write-Host "[TEST] launch flow complete - exiting."; exit 0 }

# ========================================================================================
# START SERVER
# ========================================================================================
if (-not (Test-Path -LiteralPath $launcherPath)) {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "  I need the free BeamMP Launcher to detect your game session." -ForegroundColor Yellow
    Write-Host "  I'll open the download page for you." -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Start-Process 'https://beammp.com'
    Read-Host "  Install it, then press Enter to continue"
}

# Auto-fix: busy port
$serverPort = Get-ServerPort
$busy = Get-NetTCPConnection -LocalPort $serverPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($busy) {
    $np = Get-FreePort
    Write-Host "  Port $serverPort was in use, switching to port $np automatically." -ForegroundColor Yellow
    $cfgPath = $ServerDir + 'ServerConfig.toml'
    $lines = @(Get-Content -LiteralPath $cfgPath) | ForEach-Object {
        if ($_ -match '^\s*Port\s*=') { "Port = $np" } else { $_ }
    }
    Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
    $serverPort = $np
}

# Auto-fix: server already running
if (Get-Process -Name 'BeamMP-Server' -ErrorAction SilentlyContinue) {
    Write-Host "  A BeamMP server is already running. Close it first, then try again." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Server name for the live screen
$serverName = 'K BNG M Server'
$m = Select-String -LiteralPath ($ServerDir + 'ServerConfig.toml') -Pattern '^\s*Name\s*=\s*"(.*)"' | Select-Object -First 1
if ($m) { $serverName = $m.Matches[0].Groups[1].Value }

# Security scan (quick, silent)
$clientDir = $ServerDir + 'Resources\Client'
$quarantineDir = $ServerDir + 'Quarantine'
if (-not (Test-Path -LiteralPath $quarantineDir)) { New-Item -ItemType Directory -Path $quarantineDir -Force | Out-Null }
if (Test-Path -LiteralPath $clientDir) {
    Write-Host "  [*] Quick safety check of your mods..."
    $suspects = @()
    $suspects += Get-ChildItem -Path $clientDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.exe', '.vbs', '.cmd', '.scr', '.pif' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $zips = Get-ChildItem -Path $clientDir -Recurse -Filter *.zip -File -ErrorAction SilentlyContinue
    foreach ($z in $zips) {
        if ($z.Length -eq 0) { Remove-Item -LiteralPath $z.FullName -Force -ErrorAction SilentlyContinue; continue }
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
        Write-Host "  [SECURITY] Moved $($suspects.Count) suspicious file(s) out of the mods folder." -ForegroundColor Yellow
    }
}

# AuthKey injection (from .env / env var) - same as before, silent
$authKey = $env:BEAMMP_AUTHKEY
$authSource = 'BEAMMP_AUTHKEY env var'
$envFile = $ServerDir + '.env'
if (-not $authKey) {
    if (Test-Path -LiteralPath $envFile) {
        $authKey = Get-Content -LiteralPath $envFile | Where-Object { $_ -match '^\s*BEAMMP_AUTHKEY\s*=' } | Select-Object -First 1 |
            ForEach-Object { ($_ -replace '^\s*BEAMMP_AUTHKEY\s*=', '').Trim().Trim('"', "'") }
        if ($authKey) { $authSource = '.env file' }
    }
}
$cfgPath = $ServerDir + 'ServerConfig.toml'
if ($authKey) {
    $lines = Get-Content -LiteralPath $cfgPath
    $lines = $lines | ForEach-Object {
        if ($_ -match '^\s*AuthKey\s*=') { 'AuthKey = "' + $authKey + '"' } else { $_ }
    }
    Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
    Write-Log "AuthKey injected from $authSource"
} else {
    Write-Host "  No server key found. Run 'Help / Fix Problems' -> 'Set up my server key'." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Start the server
Write-Host "  Starting your server..."
$startTime = Get-Date
$server = Start-Process -FilePath ($ServerDir + 'BeamMP-Server.exe') -WorkingDirectory $ServerDir -WindowStyle Minimized -PassThru
Write-Log "Server process started (PID $($server.Id))"

# Wait up to 40s for the server to listen
$ready = $false
for ($i = 0; $i -lt 40; $i++) {
    if ($server.HasExited) { break }
    if (Get-NetTCPConnection -LocalPort $serverPort -State Listen -ErrorAction SilentlyContinue) { $ready = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $ready) {
    Write-Host ""
    Write-Host "  Your server did not start. Let me check why..." -ForegroundColor Red
    Write-Log "Server failed to listen (PID $($server.Id))"
    Show-ServerDiagnostics
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
    Write-Host ""
    Read-Host "Press Enter to return to the main menu"
    exit 1
}
Write-Log "Server is live (PID $($server.Id))"

# Self-check: make sure the server can be reached over IPv4 (127.0.0.1).
# If not, the config may still be binding IPv6-only (IP = "::") - fix it and restart.
if (-not (Test-Loopback $serverPort)) {
    Write-Host ""
    Write-Host "  I can't reach my own server over IPv4. Fixing the bind address and restarting..." -ForegroundColor Yellow
    Write-Log "Loopback check failed - rewriting IP to 0.0.0.0"
    $cfgPath = $ServerDir + 'ServerConfig.toml'
    $lines = @(Get-Content -LiteralPath $cfgPath) | ForEach-Object {
        if ($_ -match '^\s*IP\s*=') { 'IP = "0.0.0.0"' } else { $_ }
    }
    Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
    Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $server = Start-Process -FilePath ($ServerDir + 'BeamMP-Server.exe') -WorkingDirectory $ServerDir -WindowStyle Minimized -PassThru
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        if ($server.HasExited) { break }
        if (Get-NetTCPConnection -LocalPort $serverPort -State Listen -ErrorAction SilentlyContinue) { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        Write-Host "  The server still did not start after the fix. Check Help / Fix Problems." -ForegroundColor Red
        Show-ServerDiagnostics
        Read-Host "Press Enter to return to the main menu"
        exit 1
    }
    if (Test-Loopback $serverPort) {
        Write-Host "  Fixed! Your server is now reachable on 127.0.0.1:$serverPort." -ForegroundColor Green
    } else {
        Write-Host "  Warning: the server is running but 127.0.0.1 could not be reached. Check Help / Fix Problems -> firewall." -ForegroundColor Yellow
    }
}

# Watchdog (kills the server with the session)
$watchdogCmd = '$seen=$false; $t0=[datetime]::Now; while($true){ $running=[bool](Get-Process -Name BeamMP-Launcher -ErrorAction SilentlyContinue); if($running){$seen=$true}; if($seen -and -not $running){Stop-Process -Id ' + $server.Id + ' -Force -ErrorAction SilentlyContinue; break}; if(-not (Get-Process -Id ' + $server.Id + ' -ErrorAction SilentlyContinue)){break}; if(-not $seen -and ([datetime]::Now-$t0).TotalMinutes -gt 60){break}; Start-Sleep -Seconds 2 }'
Start-Process powershell -WindowStyle Hidden -ArgumentList ('-NoProfile -Command "' + $watchdogCmd + '"') | Out-Null

# Player activity tracker
$trackerJob = Start-Job -ScriptBlock {
    param($ServerDir, $ServerId)
    $posF = $ServerDir + 'Logs\serverlog.pos'
    $stateF = $ServerDir + 'Logs\players.tmp'
    $logF = $ServerDir + 'Server.log'
    $whF = $ServerDir + 'webhook.txt'
    function Send-Event([string]$Text, [int]$Color) {
        if (-not (Test-Path -LiteralPath $whF)) { return }
        $u = (Get-Content -LiteralPath $whF -Raw).Trim()
        if ($u -notlike 'https://discord.com/api/webhooks/*') { return }
        $b = @{ embeds = @(@{ title = 'K BNG M Hoster'; description = $Text; color = $Color }) } | ConvertTo-Json -Depth 10
        try { Invoke-RestMethod -Uri $u -Method Post -Body $b -ContentType 'application/json' | Out-Null } catch { }
    }
    $players = @{}
    $off = 0
    if (Test-Path -LiteralPath $posF) { $off = [long](Get-Content -LiteralPath $posF -Raw) }
    while ($true) {
        if ($ServerId -and -not (Get-Process -Id $ServerId -ErrorAction SilentlyContinue)) { break }
        if (Test-Path -LiteralPath $logF) {
            try {
                $fs = [IO.File]::Open($logF, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                if ($fs.Length -lt $off) { $off = 0 }
                $fs.Position = $off
                $sr = New-Object IO.StreamReader($fs)
                $t = $sr.ReadToEnd()
                $off = $fs.Position
                $sr.Close()
                $fs.Dispose()
                if ($t) {
                    foreach ($ln in ($t -split ([string][char]10))) {
                        if ($ln -match 'Player "(.+?)".*?joined') {
                            $nm = $Matches[1]
                            if (-not $players.ContainsKey($nm)) {
                                $players[$nm] = $true
                                Send-Event "Player joined: $nm" 3066993
                            }
                            continue
                        }
                        if ($ln -match 'Player "(.+?)".*?left') {
                            $nm = $Matches[1]
                            if ($players.ContainsKey($nm)) {
                                $players.Remove($nm)
                                Send-Event "Player left: $nm" 15158332
                            }
                        }
                    }
                }
                Set-Content -LiteralPath $posF -Value $off
                $last = if ($players.Count) { ($players.Keys -join ', ') } else { '-' }
                Set-Content -LiteralPath $stateF -Value ("Players online: {0} - in-game: {1}" -f $players.Count, $last)
            } catch { }
        }
        Start-Sleep -Seconds 3
    }
} -ArgumentList $ServerDir, $server.Id

# Webhook: online
Send-Webhook 'K BNG M Hoster [ONLINE]' 'Server is now live.' 3066993

# Live screen + how friends join
Clear-Host
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "    YOUR SERVER IS LIVE!" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "    Server Name : $serverName"
Write-Host "    Port        : $serverPort"
Write-Host ""
Write-Host "    How to connect:" -ForegroundColor Cyan
$conn = Get-ConnectionInfo
$copyLine = "127.0.0.1:$($conn.Port)"
Write-Host "      THIS PC (test now): 127.0.0.1:$($conn.Port)"
if ($conn.Tailscale) {
    Write-Host "      Same WiFi / Tailscale: $($conn.Tailscale):$($conn.Port)"
    $copyLine = "$($conn.Tailscale):$($conn.Port)"
}
if ($conn.Public) {
    Write-Host "      Anywhere (internet): $($conn.Public):$($conn.Port)"
} else {
    Write-Host "      Anywhere (internet): (could not detect your public IP)"
}
Write-Host ""
Write-Host "      Press C at any time to copy the connection line to your clipboard."
Write-Host ""
Write-Host "    Leave this window open. Closing it stops the server."
Write-Host "=================================================================" -ForegroundColor Green

# Voice
Speak 'K BNG M Hoster is online.'

# Launch the BeamMP Launcher + wait for the session
$lastPlayerState = ''
Start-Process -FilePath $launcherPath | Out-Null
while (Get-Process -Name 'BeamMP-Launcher' -ErrorAction SilentlyContinue) {
    Start-Sleep -Seconds 3
    try {
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.KeyChar -eq 'c' -or $k.KeyChar -eq 'C') {
                Set-Clipboard -Value $copyLine
                Write-Host ""
                Write-Host "  Copied! Send this to your friends: $copyLine" -ForegroundColor Green
            }
        }
    } catch { }
    $stateFile = $ServerDir + 'Logs\players.tmp'
    if (Test-Path -LiteralPath $stateFile) {
        $state = (Get-Content -LiteralPath $stateFile -Raw).Trim()
        if ($state -and $state -ne $lastPlayerState) {
            $lastPlayerState = $state
            Write-Host "  $state"
            $host.UI.RawUI.WindowTitle = "K BNG M Hoster - $state"
        }
    }
}

# ========================================================================================
# SESSION ENDED
# ========================================================================================
Write-Host ""
Write-Host "=================================================================" -ForegroundColor Red
Write-Host " Game session ended. Stopping your server..." -ForegroundColor Red
Write-Host "=================================================================" -ForegroundColor Red
Write-Log "Session ended"
Stop-Job $trackerJob -ErrorAction SilentlyContinue
if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
Write-Log "Server stopped"
$uptimeMin = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
Write-Host ""
Write-Host "  Your server ran for $uptimeMin minute(s). Thanks for using K BNG M Hoster!" -ForegroundColor Green
Write-Host "  Made by Kinan (Discord: @raed713)"
Send-Webhook 'K BNG M Hoster [OFFLINE]' 'Server is now offline.' 15158332
Speak 'Session closed.'
Read-Host "Press Enter to close"
exit 0
