# ========================================================================================
# K BNG M Hoster v0.4 - PowerShell launcher (user-friendly rewrite)
# Purpose: start a BeamMP server and stop it the moment the game session ends.
#
# Optional: drop your Discord webhook URL into "webhook.txt" (next to this file)
# to announce server online/offline and player join/leave events.
# ========================================================================================

[CmdletBinding()]
param(
    [switch]$Mods,   # open the Mod Manager
    [switch]$Help    # show usage
)

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

function Show-Usage {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  K BNG M Hoster v0.4 - Usage" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  .\Play_BeamMP.ps1            Start the server and host a session"
    Write-Host "  .\Play_BeamMP.ps1 -Mods      Open the Mod Manager"
    Write-Host "  .\Play_BeamMP.ps1 -Help      Show this help"
    Write-Host ""
    Write-Host "  Setup: copy .env.example to .env and set BEAMMP_AUTHKEY"
    Write-Host "  (or set the BEAMMP_AUTHKEY environment variable)."
    Write-Host "  One-time key: https://keymaster.beammp.com"
    Read-Host "Press Enter to exit"
}

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

function Show-ServerDiagnostics {
    $log = $ServerDir + 'Server.log'
    $c = @()
    if (Test-Path -LiteralPath $log) { $c = Get-Content -LiteralPath $log -Tail 20 }
    $txt = $c -join ' '
    if ($c.Count -eq 0) {
        Write-Host "[DIAG] The server exited without writing Server.log. This usually means the Visual C++ Redistributable is missing - install from https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Yellow
    } elseif ($txt -match '(?i)(invalid auth|authentication failed|auth.*(invalid|wrong|rejected|missing))') {
        Write-Host "[DIAG] AuthKey is invalid or empty. Get one at https://keymaster.beammp.com and set it in your .env file (BEAMMP_AUTHKEY=...)." -ForegroundColor Yellow
    } elseif ($txt -match '(?i)(bind|already in use|address already|access denied|permission denied)') {
        Write-Host "[DIAG] Port $serverPort is already in use. Close the other program or change Port in ServerConfig.toml." -ForegroundColor Yellow
    } elseif ($txt -match '(?i)(0xc000007b|vcruntime140|msvcp|vc_redist)') {
        Write-Host "[DIAG] Visual C++ Redistributable is missing - install from https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Yellow
    } elseif ($txt -match '(?i)(keymaster|backend|timeout|unreachable)') {
        Write-Host "[DIAG] Could not reach the BeamMP backend. Check your internet connection and firewall." -ForegroundColor Yellow
    } elseif ($txt -match '(?i)(map|level).*(missing|invalid|not found)') {
        Write-Host "[DIAG] The configured map or level was not found. Check the Map setting in ServerConfig.toml." -ForegroundColor Yellow
    } else {
        Write-Host "[DIAG] Unknown error. Last server log lines:" -ForegroundColor Yellow
        $c | Select-Object -Last 5 | ForEach-Object { Write-Host "    $_" }
    }
}

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
        Write-Host "   K BNG M Hoster v0.4 - Mod Manager (Resources\Client)" -ForegroundColor Cyan
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

Write-Log "===== Launcher started ====="

# ---------------------------------------------------------------------------------------
# 2. ARGUMENT DISPATCH (utility modes, no EULA required)
# ---------------------------------------------------------------------------------------
if ($Help) { Show-Usage; exit 0 }
if ($Mods) { Show-ModManager; exit 0 }

# ---------------------------------------------------------------------------------------
# 3. EULA GATEWAY
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
# 4. BANNER
# ---------------------------------------------------------------------------------------
Clear-Host
Write-Host "==================================================================================================" -ForegroundColor Cyan
Write-Host "    K   K   BBB   N   N   GGG     M   M   H   H   OOO   SSS  TTTTT  EEE  RRRR" -ForegroundColor Cyan
Write-Host "    K  K    B  B  NN  N  G        MM MM   H   H  O   O S       T    E    R   R" -ForegroundColor Cyan
Write-Host "    KKK     BBB   N N N  G  GG    M M M   HHHHH  O   O  SSS    T    EEE  RRRR" -ForegroundColor Cyan
Write-Host "    K  K    B  B  N  NN  G   G    M   M   H   H  O   O     S   T    E    R R" -ForegroundColor Cyan
Write-Host "    K   K   BBB   N   N   GGG     M   M   H   H   OOO  SSSS    T    EEE  R  RR" -ForegroundColor Cyan
Write-Host "==================================================================================================" -ForegroundColor Cyan
Write-Host "    K BNG M Hoster v0.4 - Node Architecture"
Write-Host "    Sole Creator: Kinan | Official Discord: @raed713"
Write-Host "==================================================================================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------------------
# 5. UPDATE CHECKER (non-blocking, cached for 24h)
# ---------------------------------------------------------------------------------------
Check-ForUpdates

# ---------------------------------------------------------------------------------------
# 6. SECURITY SCAN (non-destructive, logged)
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
# 7. STABLE SERVER NAME + PORT (read from config, no random node id)
# ---------------------------------------------------------------------------------------
$serverName = 'K BNG M Server'
$serverPort = 30814
$cfgContent = Get-Content -LiteralPath ($ServerDir + 'ServerConfig.toml') -ErrorAction SilentlyContinue
$nameLine = $cfgContent | Select-String -Pattern '^\s*Name\s*=\s*"(.*)"' | Select-Object -First 1
if ($nameLine) { $serverName = $nameLine.Matches[0].Groups[1].Value }
$portLine = $cfgContent | Select-String -Pattern '^\s*Port\s*=\s*(\d+)' | Select-Object -First 1
if ($portLine) { $serverPort = [int]$portLine.Matches[0].Groups[1].Value }

# ---------------------------------------------------------------------------------------
# 8. REPAIR INVALID mods.json (BeamMP expects a JSON array, not "null")
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
# 9. AUTH KEY AUTO-INJECTION (from .env or the BEAMMP_AUTHKEY env var)
# Reads the key from the local .env file (or the BEAMMP_AUTHKEY environment variable)
# and writes it into ServerConfig.toml right before the server starts, so you never
# have to paste it manually. If both are missing, an already-set key is left untouched.
# ---------------------------------------------------------------------------------------
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
    Write-Host "[AUTH] AuthKey injected from $authSource"
    Write-Log "AuthKey injected from $authSource"
} elseif (Select-String -LiteralPath $cfgPath -Pattern '^\s*AuthKey\s*=\s*"[^"]+"' -Quiet) {
    Write-Host "[AUTH] Using AuthKey already present in ServerConfig.toml."
    Write-Log "Using existing AuthKey in ServerConfig.toml"
} else {
    Write-Host "[AUTH] No AuthKey found. Create a .env file next to the launcher with: BEAMMP_AUTHKEY=your_key_here  (or set the BEAMMP_AUTHKEY environment variable)." -ForegroundColor Yellow
    Write-Log "WARNING: no AuthKey found"
}

# ---------------------------------------------------------------------------------------
# 10. SINGLE-INSTANCE + PORT PRE-CHECK (avoid two servers / confusing errors)
# ---------------------------------------------------------------------------------------
if (Get-Process -Name 'BeamMP-Server' -ErrorAction SilentlyContinue) {
    Write-Host "[ERROR] A BeamMP-Server.exe is already running." -ForegroundColor Red
    Write-Host "        Close it before starting a new session, or change Port in ServerConfig.toml."
    Write-Log "Aborted: server already running"
    Read-Host "Press Enter to exit"
    exit 1
}
$portBusy = Get-NetTCPConnection -LocalPort $serverPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($portBusy) {
    $owner = Get-Process -Id $portBusy.OwningProcess -ErrorAction SilentlyContinue
    Write-Host "[ERROR] Port $serverPort is already in use by: $($owner.ProcessName) (PID $($owner.Id))." -ForegroundColor Red
    Write-Host "        Close it or change Port in ServerConfig.toml."
    Read-Host "Press Enter to exit"
    exit 1
}

# ---------------------------------------------------------------------------------------
# 11. START THE SERVER (capture PID so we can kill exactly this instance)
# ---------------------------------------------------------------------------------------
Write-Host "[*] Starting BeamMP server..."
$server = Start-Process -FilePath ($ServerDir + 'BeamMP-Server.exe') -WorkingDirectory $ServerDir -WindowStyle Minimized -PassThru
Write-Log "Server process started (PID $($server.Id))"

# ---------------------------------------------------------------------------------------
# 12. WAIT UNTIL THE SERVER IS ACTUALLY LISTENING (real "LIVE" check, up to 40s)
# ---------------------------------------------------------------------------------------
$ready = $false
for ($i = 0; $i -lt 40; $i++) {
    if ($server.HasExited) { break }
    if (Get-NetTCPConnection -LocalPort $serverPort -State Listen -ErrorAction SilentlyContinue) { $ready = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $ready) {
    Write-Host "[ERROR] Server did not start within 40 seconds. Diagnosing..." -ForegroundColor Red
    Write-Log "Server failed to listen (PID $($server.Id))"
    Show-ServerDiagnostics
    Write-Log "Diagnostic printed"
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Log "Server is live (PID $($server.Id))"

# ---------------------------------------------------------------------------------------
# 13. WATCHDOG: guarantee the server dies with the session even if this window is closed
# Only fires after the launcher has been observed running once (so it never kills the
# server before the game session actually begins). Also exits if the server crashes.
# ---------------------------------------------------------------------------------------
$watchdogCmd = '$seen=$false; $t0=[datetime]::Now; while($true){ $running=[bool](Get-Process -Name BeamMP-Launcher -ErrorAction SilentlyContinue); if($running){$seen=$true}; if($seen -and -not $running){Stop-Process -Id ' + $server.Id + ' -Force -ErrorAction SilentlyContinue; break}; if(-not (Get-Process -Id ' + $server.Id + ' -ErrorAction SilentlyContinue)){break}; if(-not $seen -and ([datetime]::Now-$t0).TotalMinutes -gt 60){break}; Start-Sleep -Seconds 2 }'
Start-Process powershell -WindowStyle Hidden -ArgumentList ('-NoProfile -Command "' + $watchdogCmd + '"') | Out-Null

# ---------------------------------------------------------------------------------------
# 14. PLAYER ACTIVITY TRACKER (background job, reads Server.log)
# Watches for player join/leave events, writes Logs\players.tmp for the LIVE screen,
# and optionally posts join/leave embeds to the Discord webhook.
# ---------------------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------------------
# 15. OPTIONAL DISCORD WEBHOOK (opt-in via webhook.txt)
# ---------------------------------------------------------------------------------------
Send-Webhook 'K BNG M Hoster [ONLINE]' 'Server is now live.' 3066993

# ---------------------------------------------------------------------------------------
# 16. LIVE UI
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
# 17. VOICE ANNOUNCEMENT (best-effort)
# ---------------------------------------------------------------------------------------
Speak 'K BNG M Hoster is online.'

# ---------------------------------------------------------------------------------------
# 18. LAUNCH THE GAME LAUNCHER AND WAIT FOR THE SESSION TO END
# Live player count is shown as soon as the tracker has something to report.
# ---------------------------------------------------------------------------------------
$lastPlayerState = ''
Start-Process -FilePath $launcherPath | Out-Null
while (Get-Process -Name 'BeamMP-Launcher' -ErrorAction SilentlyContinue) {
    Start-Sleep -Seconds 5
    $stateFile = $ServerDir + 'Logs\players.tmp'
    if (Test-Path -LiteralPath $stateFile) {
        $state = (Get-Content -LiteralPath $stateFile -Raw).Trim()
        if ($state -and $state -ne $lastPlayerState) {
            $lastPlayerState = $state
            Write-Host $state -ForegroundColor Green
            $host.UI.RawUI.WindowTitle = "K BNG M Hoster - $state"
        }
    }
}

# ---------------------------------------------------------------------------------------
# 19. SESSION ENDED - STOP ONLY THIS SERVER INSTANCE
# ---------------------------------------------------------------------------------------
Write-Host ""
Write-Host "=================================================================" -ForegroundColor Red
Write-Host " Game session ended. Stopping server..." -ForegroundColor Red
Write-Host "=================================================================" -ForegroundColor Red
Write-Log "Session ended"
Stop-Job $trackerJob -ErrorAction SilentlyContinue
if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
Write-Log "Server stopped"
Send-Webhook 'K BNG M Hoster [OFFLINE]' 'Server is now offline.' 15158332
Speak 'Session closed.'
exit 0
