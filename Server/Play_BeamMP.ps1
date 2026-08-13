# ========================================================================================
# K BNG M Hoster v0.5 - Simplest Edition
# Purpose: let anyone with zero technical skill host a BeamMP server.
#
# This file is the SINGLE source of truth. Start_Here.bat only launches this file.
#
# Folder layout (public release):
#   Top level (visible):  Start_Here.bat, README.md, README.txt,
#                         ServerConfig.toml, Resources\
#   Server\ (engine):     this file, BeamMP-Server.exe, Launcher.cfg, logs,
#                         .env (your key), webhook.txt - everything else.
#
# The server process runs FROM the top-level folder, so the visible
# ServerConfig.toml and Resources\ are the ones it actually uses.
#
# Optional: drop your Discord webhook URL into "Server\webhook.txt"
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

# Accept friendly mode names passed by the .bat launchers (e.g. "Start_Here.bat fix")
if ($Mode -eq 'mods') { $Mods = $true }
elseif ($Mode -eq 'fix') { $Fix = $true }
elseif ($Mode -eq 'help') { $Help = $true }
elseif ($Mode -eq 'setup') { $Setup = $true }

# ---------------------------------------------------------------------------------------
# 1. RESOLVE THE REAL SERVER DIRECTORIES
#    $ServerDir = engine folder (BeamMP-Server.exe, logs, .env) - usually Server\
#    $RootDir   = visible top level (ServerConfig.toml + Resources\) - usually the parent
# ---------------------------------------------------------------------------------------
$ServerDir = $PSScriptRoot.TrimEnd('\') + '\'
if (-not (Test-Path -LiteralPath ($ServerDir + 'BeamMP-Server.exe'))) {
    $ServerDir = (Get-Location).Path.TrimEnd('\') + '\'
}
if (-not (Test-Path -LiteralPath ($ServerDir + 'BeamMP-Server.exe'))) {
    Write-Host "I could not find the server program (BeamMP-Server.exe)." -ForegroundColor Red
    Write-Host "Make sure you run this from inside the K BNG M Hoster folder."
    Read-Host "Press Enter to exit"
    exit 1
}
# Where is the visible ServerConfig.toml? Next to the exe (flat layout) or one folder up (new layout)?
$RootDir = $ServerDir
if (Test-Path -LiteralPath ($ServerDir + 'ServerConfig.toml')) {
    $RootDir = $ServerDir
} elseif (Test-Path -LiteralPath ((Split-Path -Parent $PSScriptRoot).TrimEnd('\') + '\ServerConfig.toml')) {
    $RootDir = (Split-Path -Parent $PSScriptRoot).TrimEnd('\') + '\'
}
if (-not (Test-Path -LiteralPath ($RootDir + 'ServerConfig.toml'))) {
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
    Write-Host "  Start_Here.bat mods        Mod Manager"
    Write-Host "  Start_Here.bat fix         Help / Fix Problems"
    Write-Host "  Start_Here.bat setup       First-time setup wizard"
    Write-Host ""
    Write-Host "  PowerShell users (inside the Server folder):"
    Write-Host "  .\Play_BeamMP.ps1              Normal start"
    Write-Host "  .\Play_BeamMP.ps1 -Mods        Mod Manager"
    Write-Host "  .\Play_BeamMP.ps1 -Fix         Help / Fix Problems"
    Write-Host "  .\Play_BeamMP.ps1 -Help        This screen"
    Write-Host ""
    Write-Host "  Your key lives in Server\.env (BEAMMP_AUTHKEY=...)."
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
    $cfgPath = $RootDir + 'ServerConfig.toml'
    $m = Select-String -LiteralPath $cfgPath -Pattern '^\s*Port\s*=\s*(\d+)' | Select-Object -First 1
    if ($m) { return [int]$m.Matches[0].Groups[1].Value }
    return 30814
}

function Get-FreePort {
    $start = 30814
    for ($p = $start; $p -lt ($start + 200); $p++) {
        if (-not (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)) { return $p }
    }
    return $start
}

function Test-AuthKeyConfigured {
    if ($env:BEAMMP_AUTHKEY) { return $true }
    if (Test-Path -LiteralPath ($ServerDir + '.env')) { return $true }
    $m = Select-String -LiteralPath ($RootDir + 'ServerConfig.toml') -Pattern '^\s*AuthKey\s*=\s*"[^"]+"' | Select-Object -First 1
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
        $found = @(netsh advfirewall firewall show rule name=all 2>$null | Select-String -Pattern 'K BNG M Hoster|BeamMP')
        return [bool]$found
    } catch { }
    return $false
}

function Add-FirewallRule {
    $serverExe = $ServerDir + 'BeamMP-Server.exe'
    $port = Get-ServerPort
    # First remove any old/duplicate sets, then add one clean set:
    # program rule (all ports) + explicit TCP/UDP port rules (BeamMP needs both) + outbound.
    $resultFile = Join-Path $env:TEMP ('kbfw-' + [guid]::NewGuid().ToString('N') + '.txt')
    $script = @"
`$resultFile = '$resultFile'
`$lines = @()
`$del = 0
Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object { `$_.DisplayName -like 'K BNG M Hoster*' } | ForEach-Object {
    Remove-NetFirewallRule -DisplayName `$_.DisplayName -ErrorAction SilentlyContinue
    `$del++
}
if (`$del -gt 4) { `$lines += "Removed `$del old/duplicate rules first" }
try { New-NetFirewallRule -DisplayName 'K BNG M Hoster' -Direction Inbound -Action Allow -Program '$serverExe' -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null; `$lines += "[OK] Program rule (inbound, all ports)" } catch { `$lines += "[FAIL] Program rule: " + `$_.Exception.Message }
try { New-NetFirewallRule -DisplayName 'K BNG M Hoster UDP $port' -Direction Inbound -Action Allow -Protocol UDP -LocalPort $port -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null; `$lines += "[OK] UDP $port rule (inbound)" } catch { `$lines += "[FAIL] UDP rule: " + `$_.Exception.Message }
try { New-NetFirewallRule -DisplayName 'K BNG M Hoster TCP $port' -Direction Inbound -Action Allow -Protocol TCP -LocalPort $port -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null; `$lines += "[OK] TCP $port rule (inbound)" } catch { `$lines += "[FAIL] TCP rule: " + `$_.Exception.Message }
try { New-NetFirewallRule -DisplayName 'K BNG M Hoster Out' -Direction Outbound -Action Allow -Program '$serverExe' -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null; `$lines += "[OK] Program rule (outbound, all ports)" } catch { `$lines += "[FAIL] Outbound rule: " + `$_.Exception.Message }
Set-Content -LiteralPath `$resultFile -Value (`$lines -join [Environment]::NewLine)
Write-Host ""
Write-Host "Firewall setup finished - see the result above."
Read-Host "Press Enter to close this window"
"@
    $tmp = Join-Path $env:TEMP ('kbfw-' + [guid]::NewGuid().ToString('N') + '.ps1')
    Set-Content -LiteralPath $tmp -Value $script
    try {
        Write-Host "  A Windows security window will appear. Click 'Yes' to allow the server." -ForegroundColor Yellow
        Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $tmp + '"') -Verb RunAs -Wait | Out-Null
        if (Test-Path -LiteralPath $resultFile) {
            Get-Content -LiteralPath $resultFile | ForEach-Object { Write-Host "  $_" }
            if (Select-String -LiteralPath $resultFile -Pattern '\[FAIL\]' -Quiet) {
                Write-Host "  Some rules could not be created - see the messages above." -ForegroundColor Yellow
            } else {
                Write-Host "  Firewall is open for the server (port $port TCP+UDP)." -ForegroundColor Green
            }
        } else {
            Write-Host "  Firewall rule added (port $port TCP+UDP)." -ForegroundColor Green
        }
    } catch {
        Write-Host "  Could not add the firewall rule (was the Windows window cancelled?)." -ForegroundColor Yellow
    }
    Remove-Item -LiteralPath $tmp, $resultFile -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------------------
# STATIC IP LOCK (keeps the LAN IP stable while hosting so router forwards never break)
# ---------------------------------------------------------------------------------------
function Get-PrimaryLanAdapter {
    try {
        $route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $route) { return $null }
        $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.ifIndex -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
        if (-not $ip) { return $null }
        $dns = @(Get-DnsClientServerAddress -AddressFamily IPv4 -InterfaceIndex $route.ifIndex -ErrorAction SilentlyContinue |
            Select-Object -First 1 | ForEach-Object { $_.ServerAddresses })
        return [pscustomobject]@{
            InterfaceIndex = $route.ifIndex
            Alias          = $route.InterfaceAlias
            IP             = $ip.IPAddress
            PrefixLength   = $ip.PrefixLength
            Gateway        = $route.NextHop
            Dns            = ($dns -join ',')
        }
    } catch { return $null }
}

function Get-IPv4Mask([int]$Prefix) {
    $v = [int64]0
    for ($i = 0; $i -lt $Prefix; $i++) { $v = ($v -shl 1) -bor 1 }
    $v = $v -shl (32 - $Prefix)
    return ('{0}.{1}.{2}.{3}' -f (($v -shr 24) -band 255), (($v -shr 16) -band 255), (($v -shr 8) -band 255), ($v -band 255))
}

function Test-StaticIpLocked {
    return (Test-Path -LiteralPath ($ServerDir + 'staticip.cfg'))
}

# Switches the main adapter from DHCP to a static IP (one UAC prompt).
# Saves a backup only when the tool itself does the DHCP->static switch,
# so Restore-DhcpLanIp never undoes an IP the user set manually.
function Set-StaticLanIp {
    $a = Get-PrimaryLanAdapter
    if (-not $a) {
        Write-Host "  Could not detect your main network adapter. Skipping." -ForegroundColor Red
        Write-Log "Static IP lock: adapter detection failed"
        return $false
    }
    $cur = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $a.InterfaceIndex -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq $a.IP } | Select-Object -First 1
    if ($cur -and $cur.PrefixOrigin -ne 'Dhcp') {
        Set-Content -LiteralPath ($ServerDir + 'staticip.cfg') -Value $a.Alias -ErrorAction SilentlyContinue
        Write-Host "  Your IP is already static ($($a.IP)) - I will leave it untouched." -ForegroundColor Green
        Write-Log "Static IP lock: already static, left untouched ($($a.Alias): $($a.IP))"
        return $true
    }
    $mask = Get-IPv4Mask $a.PrefixLength
    $backup = $ServerDir + 'Logs\staticip.undo.json'
    if (-not (Test-Path -LiteralPath $backup)) {
        [pscustomobject]@{
            Adapter = $a.Alias
            IP      = $a.IP
            Mask    = $mask
            Gateway = $a.Gateway
            Dns     = $a.Dns
            Saved   = (Get-Date).ToString('o')
        } | ConvertTo-Json | Set-Content -LiteralPath $backup
    }
    $tmp = Join-Path $env:TEMP ('kbip-' + [guid]::NewGuid().ToString('N') + '.ps1')
    $result = $tmp + '.out'
    $dnsCmd = ''
    if ($a.Dns) { $dnsCmd = "netsh interface ipv4 set dns name=`"$($a.Alias)`" static $($a.Dns) 2>&1 | ForEach-Object { if (`$_ -match 'error|fail') { `$err += `$_ } }" }
    $script = @"
`$err = @()
netsh interface ipv4 set address name="$($a.Alias)" static $($a.IP) $mask $($a.Gateway) 2>&1 | ForEach-Object { if (`$_ -match 'error|fail') { `$err += `$_ } }
$dnsCmd
if (`$err.Count) { Set-Content -LiteralPath '$result' -Value (`$err -join '; ') } else { Set-Content -LiteralPath '$result' -Value 'OK' }
"@
    Set-Content -LiteralPath $tmp -Value $script
    try {
        Write-Host "  A Windows security window will appear. Click 'Yes' to lock your IP." -ForegroundColor Yellow
        Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $tmp + '"') -Verb RunAs -Wait | Out-Null
        $res = (Get-Content -LiteralPath $result -Raw -ErrorAction SilentlyContinue).Trim()
        if ($res -eq 'OK') {
            Set-Content -LiteralPath ($ServerDir + 'staticip.cfg') -Value $a.Alias
            Write-Host "  IP locked: $($a.IP) (stays fixed while hosting)." -ForegroundColor Green
            Write-Log "Static IP lock applied ($($a.Alias): $($a.IP))"
            return $true
        }
        Write-Host "  Could not lock the IP ($res). Was the Windows window cancelled?" -ForegroundColor Yellow
        Write-Log "Static IP lock failed: $res"
        return $false
    } catch {
        Write-Host "  Could not lock the IP (was the Windows window cancelled?)." -ForegroundColor Yellow
        Write-Log "Static IP lock failed (exception: $_)"
        return $false
    } finally {
        Remove-Item -LiteralPath $tmp, $result -Force -ErrorAction SilentlyContinue
    }
}

# Restores DHCP only if the tool itself made the DHCP->static switch
# (a backup exists). Leaves manually-set static IPs untouched, and keeps
# the ON marker so the lock persists across sessions.
function Restore-DhcpLanIp {
    $backup = $ServerDir + 'Logs\staticip.undo.json'
    if (-not (Test-Path -LiteralPath $backup)) {
        Write-Host "  IP was not changed by the tool - nothing to restore." -ForegroundColor DarkGray
        return $true
    }
    $alias = ''
    try { $alias = ((Get-Content -LiteralPath $backup -Raw | ConvertFrom-Json).Adapter).Trim() } catch { }
    if (-not $alias) { return $false }
    $tmp = Join-Path $env:TEMP ('kbip-' + [guid]::NewGuid().ToString('N') + '.ps1')
    $result = $tmp + '.out'
    $script = @"
`$err = @()
netsh interface ipv4 set address name="$alias" source=dhcp 2>&1 | ForEach-Object { if (`$_ -match 'error|fail') { `$err += `$_ } }
netsh interface ipv4 set dns name="$alias" source=dhcp 2>&1 | ForEach-Object { if (`$_ -match 'error|fail') { `$err += `$_ } }
if (`$err.Count) { Set-Content -LiteralPath '$result' -Value (`$err -join '; ') } else { Set-Content -LiteralPath '$result' -Value 'OK' }
"@
    Set-Content -LiteralPath $tmp -Value $script
    try {
        Write-Host "  A Windows security window will appear. Click 'Yes' to restore your IP." -ForegroundColor Yellow
        Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $tmp + '"') -Verb RunAs -Wait | Out-Null
        $res = (Get-Content -LiteralPath $result -Raw -ErrorAction SilentlyContinue).Trim()
        if ($res -eq 'OK') {
            Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
            Write-Host "  IP restored to DHCP." -ForegroundColor Green
            Write-Log "Static IP lock released (back to DHCP)"
            return $true
        }
        Write-Log "Static IP restore failed: $res (retry on next run)"
        return $false
    } catch {
        Write-Log "Static IP restore failed (exception: $_; retry on next run)"
        return $false
    } finally {
        Remove-Item -LiteralPath $tmp, $result -Force -ErrorAction SilentlyContinue
    }
}

# Main-menu toggle for the IP lock.
function Toggle-StaticIpLock {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   Lock my IP while hosting" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    if (Test-StaticIpLocked) {
        Write-Host "  Currently: LOCKED - your IP stays fixed while hosting." -ForegroundColor Green
        $a = Get-PrimaryLanAdapter
        if ($a) { Write-Host "  Adapter: $($a.Alias) - $($a.IP)" -ForegroundColor Cyan }
        Write-Host ""
        Write-Host "  Why: your router's TCP+UDP forward keeps working even when the" -ForegroundColor DarkGray
        Write-Host "  DHCP lease renews, because your IP never changes anymore." -ForegroundColor DarkGray
        Write-Host ""
        $ans = Read-Host "  Disable the lock now? (Y/N)"
        if ($ans -match '^\s*[Yy]') {
            if (Restore-DhcpLanIp) {
                Remove-Item -LiteralPath ($ServerDir + 'staticip.cfg') -Force -ErrorAction SilentlyContinue
                Write-Host "  Lock disabled - your IP returns to DHCP now." -ForegroundColor Green
                Write-Log "Static IP lock disabled from menu"
            } else {
                Write-Host "  Could not disable it (was the Windows window cancelled?)." -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "  This keeps your PC's IP fixed while you host, so the router's" -ForegroundColor Cyan
        Write-Host "  TCP+UDP port forward never breaks when the DHCP lease renews." -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  When enabled: the IP locks at server start and automatically" -ForegroundColor DarkGray
        Write-Host "  returns to DHCP when your session ends. No manual router work." -ForegroundColor DarkGray
        Write-Host ""
        $ans = Read-Host "  Enable the lock? (Y/N)"
        if ($ans -match '^\s*[Yy]') {
            if (Set-StaticLanIp) {
                Write-Host "  Lock enabled - it will be applied on the next server start." -ForegroundColor Green
                Write-Log "Static IP lock enabled from menu"
            } else {
                Write-Host "  Could not enable it (was the Windows window cancelled?)." -ForegroundColor Yellow
            }
        }
    }
    Read-Host "Press Enter to continue"
}

function Update-Config {
    param([string]$Name = '', [int]$Players = 0)
    $cfgPath = $RootDir + 'ServerConfig.toml'
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
    Write-Host " Proprietary License Agreement (EULA)" -ForegroundColor Cyan
    Write-Host " Product: K BNG M Hoster"
    Write-Host " Licensor / Copyright Holder: Kinan (@raed713) - Copyright (c) 2026. All Rights Reserved."
    Write-Host ""
    Write-Host " IMPORTANT: BY DOWNLOADING, INSTALLING, ACCESSING, OR USING THE SOFTWARE, YOU" -ForegroundColor Yellow
    Write-Host " ACCEPT AND AGREE TO THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT USE THE SOFTWARE." -ForegroundColor Yellow
    Write-Host ""
    Write-Host " 1. LICENSE GRANT - LIMITED USE"
    Write-Host "    You may: (a) run the unmodified Software on your devices for personal," -ForegroundColor Gray
    Write-Host "    non-commercial use; (b) edit Configuration Files where the documentation" -ForegroundColor Gray
    Write-Host "    permits (e.g. AuthKey in ServerConfig.toml); (c) add user mod archives" -ForegroundColor Gray
    Write-Host "    into Resources/Client/ for server-side mod syncing. All other rights are reserved." -ForegroundColor Gray
    Write-Host ""
    Write-Host " 2. PROHIBITED CONDUCT"
    Write-Host "    You shall NOT: (a) modify, patch, adapt, translate, or create derivative works" -ForegroundColor Gray
    Write-Host "    of the Software; (b) decompile, disassemble, or reverse-engineer it;" -ForegroundColor Gray
    Write-Host "    (c) redistribute, reupload, mirror, fork, publish, share, sell, sublicense," -ForegroundColor Gray
    Write-Host "    lease, rent, or transfer the Software, except by directing others to the" -ForegroundColor Gray
    Write-Host "    official GitHub Releases page; (d) use it for paid hosting or commercial" -ForegroundColor Gray
    Write-Host "    services without prior written permission; (e) remove, alter, or obscure" -ForegroundColor Gray
    Write-Host "    any attribution identifying the Licensor (Kinan / @raed713)." -ForegroundColor Gray
    Write-Host ""
    Write-Host " 3. TERMINATION"
    Write-Host "    This license may be terminated immediately upon notice for any breach." -ForegroundColor Gray
    Write-Host "    Upon termination you must cease use and delete all copies of the Software." -ForegroundColor Gray
    Write-Host ""
    Write-Host " 4. DISCLAIMER OF WARRANTY"
    Write-Host "    THE SOFTWARE IS PROVIDED 'AS IS' AND 'AS AVAILABLE', WITHOUT WARRANTY OF ANY" -ForegroundColor Gray
    Write-Host "    KIND, EXPRESS OR IMPLIED. THE ENTIRE RISK ARISING OUT OF ITS USE REMAINS WITH YOU." -ForegroundColor Gray
    Write-Host ""
    Write-Host " 5. LIMITATION OF LIABILITY"
    Write-Host "    TO THE MAXIMUM EXTENT PERMITTED BY LAW, THE LICENSOR SHALL NOT BE LIABLE FOR" -ForegroundColor Gray
    Write-Host "    ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY" -ForegroundColor Gray
    Write-Host "    LOSS OF PROFITS, DATA, OR GOODWILL, ARISING OUT OF OR RELATED TO THE USE OF" -ForegroundColor Gray
    Write-Host "    OR INABILITY TO USE THE SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES." -ForegroundColor Gray
    Write-Host ""
    Write-Host " 6. GOVERNING LAW"
    Write-Host "    This Agreement is governed by the laws of Sweden, without regard to its" -ForegroundColor Gray
    Write-Host "    conflict-of-law provisions. The Licensor may also seek to enforce this" -ForegroundColor Gray
    Write-Host "    Agreement in any jurisdiction where the Software is used or a breach has occurred." -ForegroundColor Gray
    Write-Host ""
    Write-Host " 7. CONTACT"
    Write-Host "    Legal inquiries, permissions requests, and DMCA notices: open an issue at" -ForegroundColor Gray
    Write-Host "    https://github.com/Kinan0713/K-BNG-M-Hoster/issues" -ForegroundColor Gray
    Write-Host ""
    Write-Host " 8. GENERAL"
    Write-Host "    Sections 2-8 survive termination. This is the entire agreement regarding the" -ForegroundColor Gray
    Write-Host "    Software and supersedes any prior agreements or understandings." -ForegroundColor Gray
    Write-Host ""
    Write-Host " The full agreement is available in the LICENSE file shipped with this tool." -ForegroundColor Cyan
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
    $cfgPath = $RootDir + 'ServerConfig.toml'
    $backupDir = $ServerDir + 'Backups'
    if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    Copy-Item -LiteralPath $cfgPath -Destination (Join-Path $backupDir ("ServerConfig-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".toml")) -Force
    $port = Get-FreePort
    $lines = @(Get-Content -LiteralPath $cfgPath)
    $lines = $lines | ForEach-Object {
        if ($_ -match '^\s*Name\s*=') { 'Name = "K BNG M Server"' }
        elseif ($_ -match '^\s*Port\s*=') { "Port = $port" }
        elseif ($_ -match '^\s*MaxPlayers\s*=') { 'MaxPlayers = 10' }
        elseif ($_ -match '^\s*IP\s*=') { 'IP = "::"' }
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
    $client = $RootDir + 'Resources\Client'
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
    $log = $RootDir + 'Server.log'
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
function Get-LanIp {
    try {
        $addrs = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' })
        $lan = ($addrs | Where-Object { $_.IPAddress -like '10.*' -or $_.IPAddress -like '192.168.*' -or ($_.IPAddress -like '172.*' -and [int]($_.IPAddress.Split('.')[1]) -ge 16 -and [int]($_.IPAddress.Split('.')[1]) -le 31) } | Select-Object -First 1).IPAddress
        if (-not $lan) { $lan = ($addrs | Select-Object -First 1).IPAddress }
        return $lan
    } catch { return '' }
}

# CGNAT check: carrier-grade NAT public IPs live in 100.64.0.0/10 (RFC 6598).
function Test-Cgnat([string]$PublicIp) {
    if (-not $PublicIp) { return $false }
    $o = $PublicIp.Split('.')
    if ($o.Count -ne 4) { return $false }
    return ([int]$o[0] -eq 100 -and [int]$o[1] -ge 64 -and [int]$o[1] -le 127)
}

# Discovers the router's UPnP InternetGatewayDevice and returns
# @{ ServiceType = ...; ControlUrl = ... } or $null.
function Get-UpnpControlUrl {
    $client = New-Object System.Net.Sockets.UdpClient
    $client.Client.ReceiveTimeout = 2000
    $search = "M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: `"ssdp:discover`"`r`nMX: 2`r`nST: urn:schemas-upnp-org:device:InternetGatewayDevice:1`r`n`r`n"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($search)
    $endpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse('239.255.255.250'), 1900)
    $locations = @{}
    try {
        $client.Send($bytes, $bytes.Length, $endpoint) | Out-Null
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt 6000) {
            try {
                $resp = $client.Receive([ref]$endpoint)
                $text = [System.Text.Encoding]::ASCII.GetString($resp)
                $locLine = $text -split "`r?`n" | Where-Object { $_ -match '^LOCATION:\s*(.+)$' } | Select-Object -First 1
                if ($locLine -and $locLine -match '^LOCATION:\s*(.+)$') { $locations[$Matches[1].Trim()] = $true }
            } catch { break }
        }
    } catch { }
    $client.Close()
    foreach ($url in $locations.Keys) {
        try {
            $xml = [xml](Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5).Content
            foreach ($svc in $xml.SelectNodes('//*[local-name()="service"]')) {
                $stNode = $svc.SelectSingleNode('*[local-name()="serviceType"]')
                $cuNode = $svc.SelectSingleNode('*[local-name()="controlURL"]')
                if (-not $stNode -or -not $cuNode) { continue }
                $st = $stNode.InnerText.Trim()
                if ($st -notmatch 'WAN(IP|PPP)Connection') { continue }
                $ctrl = $cuNode.InnerText.Trim()
                if ($ctrl -notmatch '^https?://') {
                    if ($ctrl -match '^/') { $ctrl = ($url -replace '^(https?://[^/]+).*$', '$1') + $ctrl }
                    else { $ctrl = $url.Substring(0, $url.LastIndexOf('/') + 1) + $ctrl }
                }
                return @{ ServiceType = $st; ControlUrl = $ctrl }
            }
        } catch { }
    }
    return $null
}

# Sends one SOAP AddPortMapping request to the router. Returns $true on success
# (also when the mapping already exists - error 718 means it is already open).
function Invoke-UpnpAddMapping {
    param($Igd, [string]$Protocol, [int]$Port, [string]$LanIp)
    $body = @"
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
 <s:Body>
  <u:AddPortMapping xmlns:u="$($Igd.ServiceType)">
   <NewRemoteHost></NewRemoteHost>
   <NewExternalPort>$Port</NewExternalPort>
   <NewProtocol>$Protocol</NewProtocol>
   <NewInternalPort>$Port</NewInternalPort>
   <NewInternalClient>$LanIp</NewInternalClient>
   <NewEnabled>1</NewEnabled>
   <NewPortMappingDescription>K BNG M Hoster</NewPortMappingDescription>
   <NewLeaseDuration>0</NewLeaseDuration>
  </u:AddPortMapping>
 </s:Body>
</s:Envelope>
"@
    try {
        $r = Invoke-WebRequest -Uri $Igd.ControlUrl -Method Post -Body $body -ContentType 'text/xml; charset="utf-8"' -Headers @{ SOAPACTION = ('"{0}#AddPortMapping"' -f $Igd.ServiceType) } -UseBasicParsing -TimeoutSec 8
        return $true
    } catch {
        if ($_.Exception.Message -match '718') { return $true }
        return $false
    }
}

# Opens the server port on the router via UPnP (no admin needed).
# Tries the Windows UPnP COM API first, then raw IGD/SSDP+SOAP discovery.
function Add-UpnpPortForward {
    param([int]$Port)
    $lan = Get-LanIp
    if (-not $lan) { return $false }
    try {
        $upnp = New-Object -ComObject HNetCfg.UPnPNAT
        $map = $upnp.StaticPortMappingCollection
        if ($map) {
            $added = $false
            foreach ($proto in 'TCP', 'UDP') {
                try { $map.Add($Port, $proto, $Port, $lan, $true, 'K BNG M Hoster'); $added = $true } catch { }
            }
            if ($added) { return $true }
        }
    } catch { }
    $igd = Get-UpnpControlUrl
    if (-not $igd) { return $false }
    $ok = $false
    foreach ($proto in 'TCP', 'UDP') {
        if (Invoke-UpnpAddMapping -Igd $igd -Protocol $proto -Port $Port -LanIp $lan) { $ok = $true }
    }
    return $ok
}

# Asks an external service whether the public IP:port is reachable from the internet.
function Test-ExternalReachability {
    param([string]$PublicIp, [int]$Port)
    try {
        $r = Invoke-RestMethod -Uri "https://ifconfig.co/port/$Port" -Headers @{ 'User-Agent' = 'K-BNG-M-Hoster' } -TimeoutSec 10
        if ($null -ne $r.reachable) { return [bool]$r.reachable }
    } catch { }
    return $null
}

function Get-ConnectionInfo {
    $port = Get-ServerPort
    $lan = Get-LanIp
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
    return [pscustomobject]@{ Port = $port; LAN = $lan; Tailscale = $tail; Public = $public; Cgnat = (Test-Cgnat $public) }
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
# CLEAN FOR SHARING (removes every personal/runtime file before zipping the folder)
# ---------------------------------------------------------------------------------------
function Show-CleanForSharing {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   Clean personal info (prepare the folder for sharing)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  This removes anything personal or temporary:" -ForegroundColor Yellow
    Write-Host "   - .env            (your secret server key)" -ForegroundColor Yellow
    Write-Host "   - webhook.txt     (your Discord webhook URL)" -ForegroundColor Yellow
    Write-Host "   - Logs\, Server.log (IP caches, player names, logs)" -ForegroundColor Yellow
    Write-Host "   - CONNECTING.txt  (contains your IP addresses)" -ForegroundColor Yellow
    Write-Host "   - Backups\, Quarantine\  - AuthKey inside ServerConfig.toml" -ForegroundColor Yellow
    Write-Host "   - staticip.cfg  (your IP-lock marker, restored to DHCP first)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Run this BEFORE zipping the folder to give to someone else." -ForegroundColor Cyan
    Write-Host ""
    $answer = Read-Host "  Type Y to clean, or N to cancel"
    if ($answer -match '^\s*[Yy]') {
        $removed = @()
        if (Test-StaticIpLocked) {
            Write-Host "  IP lock is on - restoring DHCP first..." -ForegroundColor Yellow
            $null = Restore-DhcpLanIp
        }
        foreach ($p in @('Logs', 'Backups', 'Quarantine', 'CONNECTING.txt', 'Server.log', '.env', 'webhook.txt', 'staticip.cfg')) {
            $full = $ServerDir + $p
            if (Test-Path -LiteralPath $full) {
                try {
                    Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
                    $removed += $p
                } catch {
                    Write-Host "  Could not remove $p (is it in use?)." -ForegroundColor Red
                }
            }
        }
        $rootLog = $RootDir + 'Server.log'
        if (Test-Path -LiteralPath $rootLog) {
            try { Remove-Item -LiteralPath $rootLog -Force -ErrorAction Stop; $removed += '(top) Server.log' } catch { }
        }
        $cfgPath = $RootDir + 'ServerConfig.toml'
        $lines = @(Get-Content -LiteralPath $cfgPath) | ForEach-Object {
            if ($_ -match '^\s*AuthKey\s*=') { 'AuthKey = ""' } else { $_ }
        }
        Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
        Write-Host ""
        if ($removed.Count) {
            Write-Host "  Removed: $($removed -join ', ')" -ForegroundColor Green
        } else {
            Write-Host "  Nothing to clean - the folder was already clean." -ForegroundColor Green
        }
        Write-Host "  ServerConfig.toml: AuthKey cleared." -ForegroundColor Green
        Write-Host "  The folder is now safe to zip and share." -ForegroundColor Green
        Write-Log "Clean-for-sharing: removed $($removed -join ', ')"
    }
    Read-Host "Press Enter to continue"
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
    Write-Host "   5.  Clean personal info (before sharing)"
    Write-Host "   6.  Lock my IP while hosting  (currently $(if (Test-StaticIpLocked) { 'ON' } else { 'OFF' }))"
    Write-Host "   7.  Exit"
    Write-Host ""
    $k = Wait-OrKey 8 "  Press ENTER to start now (auto-starts in 8 seconds)..."
    if ($k -eq '2') { return 2 }
    if ($k -eq '3') { return 3 }
    if ($k -eq '4') { return 4 }
    if ($k -eq '5') { return 5 }
    if ($k -eq '6') { return 6 }
    if ($k -eq '7') { return 7 }
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

        $badVpn = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -match 'Radmin|Hamachi|LogMeIn|ZeroTier' -and $_.Status -eq 'Up' })
        if ($badVpn) {
            $issues += 'VPN'
            Write-Host "  [X] Unsupported VPN active ($($badVpn.InterfaceAlias -join ', ')) - BeamMP says these break UDP. Close it while hosting." -ForegroundColor Red
        }

        $pubIp = ''
        try { $pubIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 8).ToString().Trim() } catch { }
        if (Test-Cgnat $pubIp) {
            $issues += 'CGNAT'
            Write-Host "  [X] CGNAT detected (public IP $pubIp is a carrier NAT) - port forwarding can't work" -ForegroundColor Red
        } elseif ($pubIp) {
            Write-Host "  [OK] Public IP: $pubIp" -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "  Actions:"
        if ($issues -contains 'AUTHKEY') { Write-Host "   1.  Set up my server key" }
        if ($issues -contains 'LAUNCHER') { Write-Host "   2.  Open the BeamMP Launcher download" }
        if ($issues -contains 'PORT') { Write-Host "   3.  Use a free port automatically" }
        if ($issues -contains 'FW') { Write-Host "   4.  Add a firewall rule (asks for admin)" }
        if ($issues -contains 'VC') { Write-Host "   5.  Open the Visual C++ installer" }
        if ($issues -contains 'BEAMNG') { Write-Host "   6.  Open BeamNG.drive download" }
        Write-Host "   7.  Open port $port on the router via UPnP (no admin needed)"
        Write-Host "   X.  Back to main menu"
        Write-Host ""
        $c = Read-Host "  Your choice"
        if ($c -eq '1') {
            $null = Show-SetupWizard
        } elseif ($c -eq '2') {
            Start-Process 'https://beammp.com'
        } elseif ($c -eq '3') {
            $np = Get-FreePort
            $cfgPath = $RootDir + 'ServerConfig.toml'
            $lines = @(Get-Content -LiteralPath $cfgPath) | ForEach-Object {
                if ($_ -match '^\s*Port\s*=') { "Port = $np" } else { $_ }
            }
            Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
            Write-Log "Port changed to $np"
            Write-Host "  Done! Port changed to $np. Remember: the router must forward $np (TCP+UDP)." -ForegroundColor Green
            Start-Sleep -Milliseconds 1500
        } elseif ($c -eq '4') {
            Add-FirewallRule
        } elseif ($c -eq '5') {
            Start-Process 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
        } elseif ($c -eq '6') {
            Start-Process 'https://www.beamng.com/game/'
        } elseif ($c -eq '7') {
            if (Add-UpnpPortForward $port) {
                Write-Host "  UPnP: port $port (TCP+UDP) forwarded on the router. Friends can now connect!" -ForegroundColor Green
                Write-Log "UPnP port-forward OK (port $port, fix menu)"
            } else {
                Write-Host "  UPnP failed. Enable UPnP in your router settings, or forward port $port (TCP+UDP) manually." -ForegroundColor Yellow
                Write-Log "UPnP port-forward failed (port $port, fix menu)"
            }
            Start-Sleep -Milliseconds 1500
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
    if ($choice -eq 5) { Show-CleanForSharing; continue }
    if ($choice -eq 6) { Toggle-StaticIpLock; continue }
    if ($choice -eq 7) { exit 0 }
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
    $cfgPath = $RootDir + 'ServerConfig.toml'
    $lines = @(Get-Content -LiteralPath $cfgPath) | ForEach-Object {
        if ($_ -match '^\s*Port\s*=') { "Port = $np" } else { $_ }
    }
    Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
    $serverPort = $np
    Write-Host "  IMPORTANT: your router/UPnP must forward the NEW port $np (TCP+UDP)." -ForegroundColor Red
    Write-Host "  I am trying to open it automatically now..." -ForegroundColor Yellow
    if (Add-UpnpPortForward $np) {
        Write-Host "  UPnP: port $np (TCP+UDP) forwarded on the router." -ForegroundColor Green
        Write-Log "UPnP forwarded new port $np after busy-port switch"
    } else {
        Write-Host "  UPnP unavailable - forward port $np (TCP+UDP) manually in your router." -ForegroundColor Red
        Write-Log "UPnP failed for new port $np after busy-port switch"
    }
}

# Auto-fix: server already running
if (Get-Process -Name 'BeamMP-Server' -ErrorAction SilentlyContinue) {
    Write-Host "  A BeamMP server is already running. Close it first, then try again." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Server name for the live screen
$serverName = 'K BNG M Server'
$m = Select-String -LiteralPath ($RootDir + 'ServerConfig.toml') -Pattern '^\s*Name\s*=\s*"(.*)"' | Select-Object -First 1
if ($m) { $serverName = $m.Matches[0].Groups[1].Value }

# Security scan (quick, silent)
$clientDir = $RootDir + 'Resources\Client'
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
$cfgPath = $RootDir + 'ServerConfig.toml'
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

# Auto-fix: firewall (asks for admin ONCE - needed so friends can join; no nagging afterwards)
$fwDeclined = $ServerDir + 'Logs\fw.declined'
if (-not (Test-FirewallRule) -and -not (Test-Path -LiteralPath $fwDeclined)) {
    Write-Host "  Opening Windows Firewall for the server (needed so friends can join)..." -ForegroundColor Yellow
    Write-Host "  A Windows security window will appear - click 'Yes' (only happens once)." -ForegroundColor Yellow
    Add-FirewallRule
    if (Test-FirewallRule) {
        Write-Host "  Firewall is open for the server." -ForegroundColor Green
        Write-Log "Firewall rule added automatically"
    } else {
        Set-Content -LiteralPath $fwDeclined -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Write-Log "Firewall rule declined - marker written (fix via Help / Fix Problems later)"
    }
}

# Auto-lock: if the user enabled 'Lock my IP while hosting', keep the LAN IP
# static for the whole session so router forwards never break. Undone at exit.
$ipLockedBefore = $false
if (Test-StaticIpLocked) {
    Write-Host "  Locking your IP for the session (option 6 is ON)..." -ForegroundColor Yellow
    $ipLockedBefore = Set-StaticLanIp
}

# Start the server (working dir = the visible top level, so the server uses the
# ServerConfig.toml and Resources\ folder everyone can see and edit)
Write-Host "  Starting your server..."
$startTime = Get-Date
$server = Start-Process -FilePath ($ServerDir + 'BeamMP-Server.exe') -WorkingDirectory $RootDir -WindowStyle Minimized -PassThru
Write-Log "Server process started (PID $($server.Id), working dir $RootDir)"

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

# Try to open the port on the router via UPnP (TCP+UDP) - the key to letting friends in.
$upnpOk = $false
Write-Host "  Opening port $serverPort (TCP+UDP) on your router via UPnP..."
$upnpOk = Add-UpnpPortForward $serverPort
if ($upnpOk) {
    Write-Host "  UPnP: port $serverPort forwarded automatically." -ForegroundColor Green
    Write-Log "UPnP port-forward OK (port $serverPort)"
} else {
    Write-Host "  UPnP: not available (router setting off, or unsupported)." -ForegroundColor Yellow
    Write-Host "  You must forward port $serverPort (TCP+UDP) manually, or use Tailscale." -ForegroundColor Yellow
    Write-Log "UPnP port-forward unavailable (port $serverPort)"
}

# Health check (non-destructive): confirm the server answers on 127.0.0.1.
# Never rewrites the config - BeamMP requires the IPv6 dual-stack bind (IP = "::").
if (-not (Test-Loopback $serverPort)) {
    Write-Host ""
    Write-Host "  Warning: I could not reach 127.0.0.1:$serverPort. If friends can't connect," -ForegroundColor Yellow
    Write-Host "  run Help / Fix Problems -> firewall, or check your antivirus." -ForegroundColor Yellow
    Write-Log "Loopback check failed (diagnostic only - config left untouched)"
}

# Watchdog (kills the server with the session)
$watchdogCmd = '$seen=$false; $t0=[datetime]::Now; while($true){ $running=[bool](Get-Process -Name BeamMP-Launcher -ErrorAction SilentlyContinue); if($running){$seen=$true}; if($seen -and -not $running){Stop-Process -Id ' + $server.Id + ' -Force -ErrorAction SilentlyContinue; break}; if(-not (Get-Process -Id ' + $server.Id + ' -ErrorAction SilentlyContinue)){break}; if(-not $seen -and ([datetime]::Now-$t0).TotalMinutes -gt 60){break}; Start-Sleep -Seconds 2 }'
Start-Process powershell -WindowStyle Hidden -ArgumentList ('-NoProfile -Command "' + $watchdogCmd + '"') | Out-Null

# Player activity tracker
$trackerJob = Start-Job -ScriptBlock {
    param($ServerDir, $RootDir, $ServerId)
    $posF = $ServerDir + 'Logs\serverlog.pos'
    $stateF = $ServerDir + 'Logs\players.tmp'
    $logF = $RootDir + 'Server.log'
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
} -ArgumentList $ServerDir, $RootDir, $server.Id

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
Write-Host "    How to connect (BeamNG -> More... -> BeamMP -> Direct Connect):" -ForegroundColor Cyan
$conn = Get-ConnectionInfo
$copyLine = "127.0.0.1:$($conn.Port)"
Write-Host "      THIS PC (test it now):  127.0.0.1  :  $($conn.Port)"
if ($conn.LAN) {
    Write-Host "      Friends (same WiFi):    $($conn.LAN)  :  $($conn.Port)"
    $copyLine = "$($conn.LAN):$($conn.Port)"
} elseif ($conn.Tailscale) {
    Write-Host "      Friends (Tailscale):    $($conn.Tailscale)  :  $($conn.Port)"
    $copyLine = "$($conn.Tailscale):$($conn.Port)"
}
if ($conn.Public) {
    Write-Host "      Anyone (internet):      $($conn.Public)  :  $($conn.Port)"
} else {
    Write-Host "      Anyone (internet):      (public IP not detected)"
}
Write-Host ""
if ($upnpOk) {
    Write-Host "      Router (UPnP):       port $serverPort forwarded - internet players CAN connect." -ForegroundColor Green
} else {
    Write-Host "      Router (UPnP):       NOT forwarded - forward port $serverPort (TCP+UDP) manually" -ForegroundColor Yellow
    Write-Host "                          or use Tailscale (check Tailscale is running on both sides)." -ForegroundColor Yellow
}
if ($conn.Cgnat) {
    Write-Host "      [WARNING] Your ISP uses CGNAT ($($conn.Public)) - port forwarding CANNOT work." -ForegroundColor Red
    Write-Host "      Use Tailscale instead, or rent a cheap VPS for the server." -ForegroundColor Red
} elseif ($conn.Public) {
    $reachable = Test-ExternalReachability -PublicIp $conn.Public -Port $conn.Port
    if ($reachable -eq $true) {
        Write-Host "      External test:       $($conn.Public):$($conn.Port) IS reachable from the internet." -ForegroundColor Green
    } elseif ($reachable -eq $false) {
        Write-Host "      External test:       $($conn.Public):$($conn.Port) NOT reachable - check forwarding/firewall." -ForegroundColor Red
    } else {
        Write-Host "      External test:       could not verify (check https://checkbeammp.beammp.com manually)." -ForegroundColor DarkGray
    }
}
$badVpn = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -match 'Radmin|Hamachi|LogMeIn|ZeroTier' -and $_.Status -eq 'Up' })
if ($badVpn) {
    Write-Host "      [WARNING] Unsupported VPN active ($($badVpn.InterfaceAlias -join ', ')) - close it while hosting," -ForegroundColor Yellow
    Write-Host "      it can block the UDP traffic friends need to join." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "      IMPORTANT: do NOT click your own server in the server list - it uses your"
Write-Host "      public IP and fails from inside your own network. Always use Direct Connect."
Write-Host ""
Write-Host "      Press C at any time to copy the connection line for your friends."
Write-Host ""
Write-Host "    Leave this window open. Closing it stops the server."
Write-Host "=================================================================" -ForegroundColor Green

# Write a plain-language 'how to connect' file next to the launcher
$connectDoc = @"
HOW TO CONNECT TO YOUR SERVER
=============================

1) ON THIS PC (test it here):
   In BeamNG: More... -> BeamMP -> Direct Connect
   IP: 127.0.0.1     Port: $($conn.Port)
   Press Connect.

2) FRIENDS ON THE SAME WIFI:
   BeamNG -> More... -> BeamMP -> Direct Connect
   IP: $(if ($conn.LAN) { "$($conn.LAN)   Port: $($conn.Port)" } else { '(LAN IP not detected - run ipconfig to find yours)' })

3) FRIENDS ANYWHERE (internet):
   IP: $(if ($conn.Public) { "$($conn.Public)   Port: $($conn.Port)" } else { '(public IP not detected)' })

   Router port forwarding status: $(if ($upnpOk) { 'OPENED AUTOMATICALLY via UPnP - friends can join' } else { 'NOT OPENED - forward port ' + $conn.Port + ' (TCP+UDP) in your router, or use Tailscale' })
   $(if ($conn.Cgnat) { "WARNING: your ISP uses CGNAT ($($conn.Public)) - public port forwarding can never work. Use Tailscale or a VPS." })

IMPORTANT: Do NOT click your own server in the BeamMP server list.
It uses your public IP, which fails from inside your own network.
Always use Direct Connect with the correct address above.
"@
Set-Content -LiteralPath ($ServerDir + 'CONNECTING.txt') -Value $connectDoc

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
# Remove the injected key so the config is always safe to share (re-injected on next start)
$lines = @(Get-Content -LiteralPath $cfgPath) | ForEach-Object {
    if ($_ -match '^\s*AuthKey\s*=') { 'AuthKey = ""' } else { $_ }
}
Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
Write-Log "AuthKey removed from ServerConfig.toml (re-injected on next start)"
# Undo the IP lock: restore DHCP exactly like the AuthKey is removed.
if (Test-StaticIpLocked) {
    Write-Host "  Releasing the IP lock for this session..." -ForegroundColor Yellow
    if (Restore-DhcpLanIp) {
        Write-Host "  IP lock released - your network is back to normal." -ForegroundColor Green
    } else {
        Write-Host "  WARNING: could not restore DHCP. Run the tool again later - it retries automatically." -ForegroundColor Yellow
    }
}
# The server writes Server.log to its working folder (the visible top level) -
# tuck it away into Server\ so the top level stays tidy.
$rootLog = $RootDir + 'Server.log'
if (Test-Path -LiteralPath $rootLog) {
    Move-Item -LiteralPath $rootLog -Destination ($ServerDir + 'Server.log') -Force -ErrorAction SilentlyContinue
}
$uptimeMin = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
Write-Host ""
Write-Host "  Your server ran for $uptimeMin minute(s). Thanks for using K BNG M Hoster!" -ForegroundColor Green
Write-Host "  Made by Kinan (Discord: @raed713)"
Send-Webhook 'K BNG M Hoster [OFFLINE]' 'Server is now offline.' 15158332
Speak 'Session closed.'
Read-Host "Press Enter to close"
exit 0
