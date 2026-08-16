# ========================================================================================
# K BNG M Hoster v0.6.8 - HosterCore.ps1
# All logic lives here (single source of truth). The GUI (Play_BeamMP.ps1) and every
# background task load this file and call these functions. No console UI in this file.
#
# Folder layout (public release):
#   Top level (all the user ever needs):  Start_Here.bat, README.md, README.txt,
#                                         CHANGELOG.md, LICENSE
#   Server\ (the engine - users never open it): this file, Play_BeamMP.ps1,
#                         BeamMP-Server.exe, Launcher.cfg, ServerConfig.toml,
#                         Resources\, logs, .env (your key), webhook.txt.
#
# The server process runs FROM the Server\ folder, so the ServerConfig.toml
# and Resources\ it uses live next to it.
#
# Optional: drop your Discord webhook URL into "Server\webhook.txt"
# to announce server online/offline and player join/leave events.
# ========================================================================================

$ErrorActionPreference = 'SilentlyContinue'

# ---------------------------------------------------------------------------------------
# PATHS (computed once, works from any copy / layout)
# ---------------------------------------------------------------------------------------
function Initialize-HosterPaths {
    $src = $null
    if ($PSCommandPath) { $src = $PSCommandPath }
    elseif ($script:CorePath) { $src = $script:CorePath }
    else { $src = $MyInvocation.MyCommand.Path }
    $script:CoreDir = (Split-Path -Parent $src).TrimEnd('\') + '\'
    $script:ServerDir = $script:CoreDir
    if (-not (Test-Path -LiteralPath ($script:ServerDir + 'BeamMP-Server.exe'))) {
        $script:ServerDir = (Get-Location).Path.TrimEnd('\') + '\'
    }
    if (-not (Test-Path -LiteralPath ($script:ServerDir + 'BeamMP-Server.exe'))) {
        $script:ServerDir = $script:CoreDir
    }
    # Where is the visible ServerConfig.toml? Next to the exe (flat layout) or one folder up (new layout)?
    $script:RootDir = $script:ServerDir
    if (Test-Path -LiteralPath ($script:ServerDir + 'ServerConfig.toml')) {
        $script:RootDir = $script:ServerDir
    } elseif (Test-Path -LiteralPath ($script:CoreDir + 'ServerConfig.toml')) {
        $script:RootDir = $script:CoreDir
    } else {
        $parent = (Split-Path -Parent $script:CoreDir.TrimEnd('\')).TrimEnd('\') + '\'
        if (Test-Path -LiteralPath ($parent + 'ServerConfig.toml')) {
            $script:RootDir = $parent
        }
    }
    if (-not (Test-Path -LiteralPath ($script:RootDir + 'ServerConfig.toml'))) {
        $script:RootDir = $script:ServerDir
    }
    $script:LauncherPath = Join-Path $env:APPDATA 'BeamMP-Launcher\BeamMP-Launcher.exe'
}

# ---------------------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------------------
function Write-Log([string]$Message) {
    $logDir = $script:ServerDir + 'Logs'
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

# Reports a line to the GUI log (queue passed in by the host). Never throws.
function Say([string]$Message) {
    if ($script:Q) {
        try { $script:Q.Enqueue($Message) } catch { }
    }
}

function Send-Webhook([string]$Title, [string]$Description, [int]$Color) {
    $whFile = $script:ServerDir + 'webhook.txt'
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

# ---------------------------------------------------------------------------------------
# CONFIG / KEY
# ---------------------------------------------------------------------------------------
function Get-ServerPort {
    $cfgPath = $script:RootDir + 'ServerConfig.toml'
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

function Set-FreePort {
    param([int]$Port)
    $cfgPath = $script:RootDir + 'ServerConfig.toml'
    $lines = @(Get-Content -LiteralPath $cfgPath) | ForEach-Object {
        if ($_ -match '^\s*Port\s*=') { "Port = $Port" } else { $_ }
    }
    Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
    Write-Log "Port changed to $Port"
    return "Port changed to $Port. Remember: the router must forward $Port (TCP+UDP)."
}

function Test-AuthKeyConfigured {
    if ($env:BEAMMP_AUTHKEY) { return $true }
    if (Test-Path -LiteralPath ($script:ServerDir + '.env')) { return $true }
    $m = Select-String -LiteralPath ($script:RootDir + 'ServerConfig.toml') -Pattern '^\s*AuthKey\s*=\s*"[^"]+"' | Select-Object -First 1
    return [bool]$m
}

# Validates and saves the key to Server\.env. Returns an object with Ok / Message.
function Save-AuthKey {
    param([string]$Key)
    $key = $Key.Trim().Trim('"', "'")
    if ($key -and $key -notmatch '^[A-Za-z0-9\-]{8,64}$') {
        return [pscustomobject]@{ Ok = $false; Message = "That doesn't look like a valid key. It should only contain letters, numbers and dashes." }
    }
    if (-not $key) {
        return [pscustomobject]@{ Ok = $false; Message = 'No key was provided.' }
    }
    Set-Content -LiteralPath ($script:ServerDir + '.env') -Value ("BEAMMP_AUTHKEY=" + $key)
    Write-Log "AuthKey saved to .env"
    return [pscustomobject]@{ Ok = $true; Message = 'Key saved. It will never be shown again.' }
}

# Applies recommended server defaults (backup first). Returns the port used.
function New-SetupConfig {
    $cfgPath = $script:RootDir + 'ServerConfig.toml'
    $backupDir = $script:ServerDir + 'Backups'
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
    Write-Log "Setup defaults applied (port $port)"
    return $port
}

function Update-Config {
    param([string]$Name = '', [int]$Players = 0)
    $cfgPath = $script:RootDir + 'ServerConfig.toml'
    $lines = @(Get-Content -LiteralPath $cfgPath)
    $lines = $lines | ForEach-Object {
        if ($Name -and $_ -match '^\s*Name\s*=') { 'Name = "' + $Name + '"' }
        elseif ($Players -gt 0 -and $_ -match '^\s*MaxPlayers\s*=') { "MaxPlayers = $Players" }
        else { $_ }
    }
    Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
    return "Server settings saved."
}

# Reads any key from ServerConfig.toml as a plain string (quotes stripped).
function Get-ConfigValue([string]$Key) {
    $cfgPath = $script:RootDir + 'ServerConfig.toml'
    if (-not (Test-Path -LiteralPath $cfgPath)) { return '' }
    $m = Select-String -LiteralPath $cfgPath -Pattern ("^\s*" + [regex]::Escape($Key) + "\s*=\s*(.+?)\s*$") | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value.Trim().Trim('"') }
    return ''
}

# Writes any set of ServerConfig.toml keys in one go (backup first, idempotent).
# Values must already be TOML-ready: numbers/booleans bare, strings double-quoted.
function Set-ServerConfig {
    param([hashtable]$Values)
    $cfgPath = $script:RootDir + 'ServerConfig.toml'
    if (-not (Test-Path -LiteralPath $cfgPath)) { return "ServerConfig.toml not found - nothing saved." }
    $backupDir = $script:ServerDir + 'Backups'
    if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    Copy-Item -LiteralPath $cfgPath -Destination (Join-Path $backupDir ("ServerConfig-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".toml")) -Force
    $lines = @(Get-Content -LiteralPath $cfgPath)
    $remaining = @($Values.Keys)
    $out = @()
    foreach ($line in $lines) {
        $written = $false
        foreach ($key in $Values.Keys) {
            if ($line -match ("^\s*" + [regex]::Escape($key) + "\s*=")) {
                if ($null -ne $Values[$key]) { $out += "$key = $($Values[$key])" } else { $out += $line }
                $written = $true
                $remaining = @($remaining | Where-Object { $_ -ne $key })
                break
            }
        }
        if (-not $written) { $out += $line }
    }
    foreach ($key in $remaining) {
        if ($null -eq $Values[$key]) { continue }
        $out += "$key = $($Values[$key])"
    }
    Set-Content -LiteralPath $cfgPath -Value $out -Encoding UTF8
    Write-Log "ServerConfig updated: $($Values.Keys -join ', ')"
    return "Server settings saved."
}

# ---------------------------------------------------------------------------------------
# MAPS
# ---------------------------------------------------------------------------------------
# Current Map value from ServerConfig.toml (e.g. /levels/gridmap_v2/info.json).
function Get-ServerMap {
    $cfgPath = $script:RootDir + 'ServerConfig.toml'
    $m = Select-String -LiteralPath $cfgPath -Pattern '^\s*Map\s*=\s*"([^"]+)"' | Select-Object -First 1
    if ($m) { return $m.Matches[0].Groups[1].Value }
    return '/levels/gridmap_v2/info.json'
}

# Map folder name from a Map path (e.g. /levels/gridmap_v2/info.json -> gridmap_v2).
function Get-MapNameFromPath([string]$Map) {
    if ($Map -match '(?:^|/)levels/([^/]+)/info\.json$') { return $Matches[1] }
    return ''
}

# ---------------------------------------------------------------------------------------
# SERVER VISIBILITY (public/private)
# ---------------------------------------------------------------------------------------
# $true when the server is hidden from the BeamMP server list. Private servers are
# still joinable by anyone who has the address (IP:port via Direct Connect).
function Get-ServerPrivate {
    $cfgPath = $script:RootDir + 'ServerConfig.toml'
    if (-not (Test-Path -LiteralPath $cfgPath)) { return $false }
    $m = Select-String -LiteralPath $cfgPath -Pattern '^\s*Private\s*=\s*(true|false)' | Select-Object -First 1
    if ($m) { return ($m.Matches[0].Groups[1].Value -ieq 'true') }
    return $false
}

# Sets Private = true/false in ServerConfig.toml (backup first, idempotent).
function Set-ServerVisibility {
    param([bool]$Private)
    $cfgPath = $script:RootDir + 'ServerConfig.toml'
    if (-not (Test-Path -LiteralPath $cfgPath)) { return "ServerConfig.toml not found - nothing to change." }
    if ((Get-ServerPrivate) -eq $Private) { return "Already $(if ($Private) { 'private' } else { 'public' }) - no change needed." }
    $backupDir = $script:ServerDir + 'Backups'
    if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    Copy-Item -LiteralPath $cfgPath -Destination (Join-Path $backupDir ("ServerConfig-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-vis.toml")) -Force
    $lines = @(Get-Content -LiteralPath $cfgPath)
    $changed = $false
    $tomlPrivate = if ($Private) { 'true' } else { 'false' }
    $lines = $lines | ForEach-Object {
        if ($_ -match '^\s*Private\s*=') { $changed = $true; "Private = $tomlPrivate" } else { $_ }
    }
    if (-not $changed) { $lines += "Private = $tomlPrivate" }
    Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
    Write-Log "Visibility set to $(if ($Private) { 'private' } else { 'public' })"
    return "Server is now $(if ($Private) { 'private - hidden from the server list' } else { 'public - listed for everyone' }). It applies on the next server start."
}

# Level names found inside a mod/map zip (entries look like levels/<name>/info.json).
function Get-MapLevelNames([string]$ZipPath) {
    $names = @()
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        try {
            foreach ($e in $z.Entries) {
                if ($e.FullName -match '^levels[\\/]([^\\/]+)[\\/]info\.json$') {
                    if ($Matches[1] -notin $names) { $names += $Matches[1] }
                }
            }
        } finally { $z.Dispose() }
    } catch { }
    return $names
}

# Every map the host can run: vanilla (from the game install) + map mods
# (from the game's mods/workshop folders and from this server's Resources\Client).
# Returns @{ Name; Map; Kind; Zip } - Zip is set for map mods that must be hosted.
# Signature of everything that can add/remove maps: zip/dir names + sizes + write times.
# Cheap (no zip opening) and catches installs/updates/deletions of maps.
function Get-MapScanSignature {
    $parts = New-Object System.Collections.Generic.List[string]
    $add = {
        param($f)
        try { $parts.Add((Join-Path (Split-Path -Parent $f.FullName) $f.Name) + '|' + $f.Length + '|' + $f.LastWriteTimeUtc.Ticks) } catch { }
    }
    $game = Get-BeamNGPath
    if ($game) {
        $levelsZip = Join-Path (Split-Path -Parent $game) 'content\levels'
        if (Test-Path -LiteralPath $levelsZip) {
            foreach ($f in @(Get-ChildItem -LiteralPath $levelsZip -Filter '*.zip' -File -ErrorAction SilentlyContinue)) { & $add $f }
        }
        $levelsDir = Join-Path (Split-Path -Parent $game) 'levels'
        if (Test-Path -LiteralPath $levelsDir) {
            foreach ($d in @(Get-ChildItem -LiteralPath $levelsDir -Directory -ErrorAction SilentlyContinue)) {
                $info = Join-Path $d.FullName 'info.json'
                if (Test-Path -LiteralPath $info) {
                    $i = Get-Item -LiteralPath $info -ErrorAction SilentlyContinue
                    if ($i) { $parts.Add($d.FullName + '|info|' + $i.Length + '|' + $i.LastWriteTimeUtc.Ticks) }
                }
            }
        }
    }
    $modFolders = @()
    foreach ($root in @((Join-Path $env:LOCALAPPDATA 'BeamNG.drive'), (Join-Path $env:USERPROFILE 'Documents\BeamNG.drive'))) {
        if (Test-Path -LiteralPath $root) {
            $modFolders += @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'mods' })
        }
    }
    $steamRoot = $null
    if ($game) {
        $p = Split-Path -Parent $game
        for ($i = 0; $i -lt 5 -and $p -and $p -ne (Split-Path -Parent $p); $i++) {
            if ((Split-Path -Leaf $p) -eq 'common') { $steamRoot = Split-Path -Parent $p; break }
            $p = Split-Path -Parent $p
        }
    }
    if ($steamRoot) {
        $ws = Join-Path $steamRoot 'workshop\content\284160'
        if (Test-Path -LiteralPath $ws) { $modFolders += (Join-Path $ws '*') }
    }
    foreach ($mf in $modFolders) {
        if ($mf.EndsWith('*')) {
            foreach ($d in @(Get-ChildItem -LiteralPath ($mf.Substring(0, $mf.Length - 1)) -Directory -ErrorAction SilentlyContinue)) {
                foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Filter '*.zip' -File -ErrorAction SilentlyContinue)) { & $add $f }
            }
        } elseif (Test-Path -LiteralPath $mf) {
            foreach ($f in @(Get-ChildItem -LiteralPath $mf -Filter '*.zip' -File -ErrorAction SilentlyContinue)) { & $add $f }
            $lvl = Join-Path $mf 'levels'
            if (Test-Path -LiteralPath $lvl) {
                foreach ($m in @(Get-ChildItem -LiteralPath $lvl -Directory -ErrorAction SilentlyContinue)) {
                    $info = Join-Path $m.FullName 'info.json'
                    if (Test-Path -LiteralPath $info) {
                        $i = Get-Item -LiteralPath $info -ErrorAction SilentlyContinue
                        if ($i) { $parts.Add($m.FullName + '|info|' + $i.Length + '|' + $i.LastWriteTimeUtc.Ticks) }
                    }
                }
            }
        }
    }
    $client = $script:RootDir + 'Resources\Client'
    if (Test-Path -LiteralPath $client) {
        foreach ($f in @(Get-ChildItem -LiteralPath $client -Filter '*.zip' -File -ErrorAction SilentlyContinue)) { & $add $f }
    }
    return [string]::Join(';', $parts)
}

# Disk-cached for 12h (Logs\maps_cache.json). The signature changes on install/update/
# delete of a map file, which invalidates the cache. Safe to call from any runspace.
function Get-AvailableMaps {
    $cacheFile = $script:ServerDir + 'Logs\maps_cache.json'
    $sig = Get-MapScanSignature
    $fresh = $false
    if (Test-Path -LiteralPath $cacheFile) {
        try {
            $j = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
            if ($j.sig -eq $sig -and ((Get-Date) - [datetime]$j.checked).TotalHours -lt 12) {
                $fresh = $true
                return @($j.maps)
            }
        } catch { }
    }
    if (-not $fresh) {
        $result = Get-AvailableMapsRaw
        try {
            @{ sig = $sig; checked = (Get-Date).ToString('o'); maps = @($result) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $cacheFile
        } catch { }
        return $result
    }
}

function Get-AvailableMapsRaw {
    $result = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $push = {
        param($Name, $Kind, $Zip)
        if ($Name -and -not $seen.ContainsKey($Name.ToLowerInvariant())) {
            $seen[$Name.ToLowerInvariant()] = $true
            $result.Add([pscustomobject]@{ Name = $Name; Map = "/levels/$Name/info.json"; Kind = $Kind; Zip = $Zip })
        }
    }

    $game = Get-BeamNGPath
    if ($game) {
        $gameDir = Split-Path -Parent $game
        $levelsZip = Join-Path $gameDir 'content\levels'
        if (Test-Path -LiteralPath $levelsZip) {
            foreach ($f in @(Get-ChildItem -LiteralPath $levelsZip -Filter '*.zip' -File -ErrorAction SilentlyContinue)) {
                foreach ($n in Get-MapLevelNames $f.FullName) { & $push $n 'Vanilla' '' }
            }
        }
        $levelsDir = Join-Path $gameDir 'levels'
        if (Test-Path -LiteralPath $levelsDir) {
            foreach ($d in @(Get-ChildItem -LiteralPath $levelsDir -Directory -ErrorAction SilentlyContinue)) {
                if (Test-Path -LiteralPath (Join-Path $d.FullName 'info.json')) { & $push $d.Name 'Vanilla' '' }
            }
        }
    }

    $modFolders = @()
    foreach ($root in @((Join-Path $env:LOCALAPPDATA 'BeamNG.drive'), (Join-Path $env:USERPROFILE 'Documents\BeamNG.drive'))) {
        if (Test-Path -LiteralPath $root) {
            $modFolders += @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'mods' })
        }
    }
    $steamRoot = $null
    if ($game) {
        $p = Split-Path -Parent $game
        for ($i = 0; $i -lt 5 -and $p -and $p -ne (Split-Path -Parent $p); $i++) {
            if ((Split-Path -Leaf $p) -eq 'common') { $steamRoot = Split-Path -Parent $p; break }
            $p = Split-Path -Parent $p
        }
    }
    if ($steamRoot) {
        $ws = Join-Path $steamRoot 'workshop\content\284160'
        if (Test-Path -LiteralPath $ws) {
            $modFolders += (Join-Path $ws '*')
        }
    }
    foreach ($mf in $modFolders) {
        foreach ($f in @(Get-ChildItem -LiteralPath $mf -Filter '*.zip' -File -ErrorAction SilentlyContinue)) {
            foreach ($n in Get-MapLevelNames $f.FullName) { & $push $n 'Map mod' $f.FullName }
        }
        foreach ($d in @(Get-ChildItem -LiteralPath $mf -Directory -ErrorAction SilentlyContinue)) {
            $lvl = Join-Path $d.FullName 'levels'
            if (Test-Path -LiteralPath $lvl) {
                foreach ($m in @(Get-ChildItem -LiteralPath $lvl -Directory -ErrorAction SilentlyContinue)) {
                    if (Test-Path -LiteralPath (Join-Path $m.FullName 'info.json')) { & $push $m.Name 'Map mod' '' }
                }
            }
        }
    }

    $client = $script:RootDir + 'Resources\Client'
    if (Test-Path -LiteralPath $client) {
        foreach ($f in @(Get-ChildItem -LiteralPath $client -Filter '*.zip' -File -ErrorAction SilentlyContinue)) {
            foreach ($n in Get-MapLevelNames $f.FullName) { & $push $n 'Map mod' $f.FullName }
        }
    }

    return @($result | Sort-Object Kind, Name)
}

# Applies a map (backup first, optional zip hosting for map mods). Returns a message.
function Set-ServerMap {
    param([string]$LevelName, [string]$ZipToHost = '')
    if ($LevelName -notmatch '^[A-Za-z0-9_\- ]+$' -or $LevelName.Trim() -ne $LevelName) {
        return "That map name looks wrong: $LevelName"
    }
    if ($ZipToHost) {
        $client = $script:RootDir + 'Resources\Client'
        if (-not (Test-Path -LiteralPath $client)) { New-Item -ItemType Directory -Path $client -Force | Out-Null }
        $dest = Join-Path $client (Split-Path -Leaf $ZipToHost)
        $srcFull = [System.IO.Path]::GetFullPath($ZipToHost)
        $destFull = [System.IO.Path]::GetFullPath($dest)
        if ($srcFull -ne $destFull) {
            if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
            Copy-Item -LiteralPath $ZipToHost -Destination $dest -Force
            Write-Log "Map mod hosted for players: $(Split-Path -Leaf $ZipToHost)"
        }
    }
    $cfgPath = $script:RootDir + 'ServerConfig.toml'
    $newMap = "/levels/$LevelName/info.json"
    if ((Get-ServerMap) -ne $newMap) {
        $backupDir = $script:ServerDir + 'Backups'
        if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        Copy-Item -LiteralPath $cfgPath -Destination (Join-Path $backupDir ("ServerConfig-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-map.toml")) -Force
        $lines = @(Get-Content -LiteralPath $cfgPath)
        $changed = $false
        $lines = $lines | ForEach-Object {
            if ($_ -match '^\s*Map\s*=') { $changed = $true; "Map = ""$newMap""" } else { $_ }
        }
        if (-not $changed) { $lines += "Map = ""$newMap""" }
        Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
        Write-Log "Map changed to $newMap"
        return "Map set to $newMap. It applies on the next server start."
    }
    return "Already on map $newMap."
}

# ---------------------------------------------------------------------------------------
# GAME / TOOLS
# ---------------------------------------------------------------------------------------
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

# The port the K BNG M Hoster firewall rules were opened for.
# Returns '' when no rules exist, 'program' when only program-wide rules exist.
function Get-FirewallRulePort {
    try {
        $out = @(netsh advfirewall firewall show rule name=all 2>$null)
        $ports = @($out | Select-String -Pattern 'K BNG M Hoster.*(TCP|UDP)\s*(\d+)' | ForEach-Object { $_.Matches[0].Groups[2].Value })
        if ($ports.Count) { return [string]$ports[0] }
        $any = @($out | Select-String -Pattern 'K BNG M Hoster')
        if ($any.Count) { return 'program' }
    } catch { }
    return ''
}

# Adds firewall rules via an elevated helper window (one UAC prompt).
function Add-FirewallRule {
    $serverExe = $script:ServerDir + 'BeamMP-Server.exe'
    $port = Get-ServerPort
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
    $ok = $false
    try {
        Say "A Windows security window will appear. Click 'Yes' to allow the server."
        Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $tmp + '"') -Verb RunAs -Wait | Out-Null
        if (Test-Path -LiteralPath $resultFile) {
            Get-Content -LiteralPath $resultFile | ForEach-Object { Say $_ }
            if (Select-String -LiteralPath $resultFile -Pattern '\[FAIL\]' -Quiet) {
                Say "Some rules could not be created - see the messages above."
            } else {
                Say "Firewall is open for the server (port $port TCP+UDP)."
                $ok = $true
            }
        } else {
            Say "Firewall rule added (port $port TCP+UDP)."
            $ok = $true
        }
    } catch {
        Say "Could not add the firewall rule (was the Windows window cancelled?)."
    }
    Remove-Item -LiteralPath $tmp, $resultFile -Force -ErrorAction SilentlyContinue
    return $ok
}

# $true when BeamNG.drive has its own ALLOW firewall rule.
function Test-BeamNGFirewallRule {
    try {
        $found = @(netsh advfirewall firewall show rule name=all 2>$null | Select-String -Pattern 'K BNG M Hoster BeamNG')
        return [bool]$found
    } catch { }
    return $false
}

# Adds an ALLOW rule for BeamNG.drive.exe (one UAC prompt, like the server rule).
function Add-BeamNGFirewallRule {
    $exe = Get-BeamNGPath
    if (-not $exe) { return "BeamNG.drive.exe was not found - install the game first, then re-run this fix." }
    $resultFile = Join-Path $env:TEMP ('kbfwb-' + [guid]::NewGuid().ToString('N') + '.txt')
    $script = @"
`$resultFile = '$resultFile'
`$lines = @()
try { New-NetFirewallRule -DisplayName 'K BNG M Hoster BeamNG' -Direction Inbound -Action Allow -Program '$exe' -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null; `$lines += "[OK] BeamNG.drive allowed (inbound)" } catch { `$lines += "[FAIL] " + `$_.Exception.Message }
try { New-NetFirewallRule -DisplayName 'K BNG M Hoster BeamNG Out' -Direction Outbound -Action Allow -Program '$exe' -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null; `$lines += "[OK] BeamNG.drive allowed (outbound)" } catch { `$lines += "[FAIL] " + `$_.Exception.Message }
Set-Content -LiteralPath `$resultFile -Value (`$lines -join [Environment]::NewLine)
Write-Host ""
Write-Host "Firewall setup for BeamNG.drive finished."
Read-Host "Press Enter to close this window"
"@
    $tmp = Join-Path $env:TEMP ('kbfwb-' + [guid]::NewGuid().ToString('N') + '.ps1')
    Set-Content -LiteralPath $tmp -Value $script
    $ok = $false
    try {
        Say "A Windows security window will appear. Click 'Yes' to allow BeamNG.drive."
        Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $tmp + '"') -Verb RunAs -Wait | Out-Null
        if (Test-Path -LiteralPath $resultFile) {
            Get-Content -LiteralPath $resultFile | ForEach-Object { Say $_ }
            if (Select-String -LiteralPath $resultFile -Pattern '\[FAIL\]' -Quiet) {
                Say "Some BeamNG rules could not be created - see the messages above."
            } else {
                Say "BeamNG.drive is now allowed through Windows Firewall."
                $ok = $true
            }
        } else {
            Say "BeamNG.drive firewall rule added."
            $ok = $true
        }
    } catch {
        Say "Could not add the BeamNG rule (was the Windows window cancelled?)."
    }
    Remove-Item -LiteralPath $tmp, $resultFile -Force -ErrorAction SilentlyContinue
    return $ok
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
    return (Test-Path -LiteralPath ($script:ServerDir + 'staticip.cfg'))
}

# Switches the main adapter from DHCP to a static IP (one UAC prompt).
function Set-StaticLanIp {
    $a = Get-PrimaryLanAdapter
    if (-not $a) {
        Say "Could not detect your main network adapter. Skipping."
        Write-Log "Static IP lock: adapter detection failed"
        return $false
    }
    $cur = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $a.InterfaceIndex -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq $a.IP } | Select-Object -First 1
    if ($cur -and $cur.PrefixOrigin -ne 'Dhcp') {
        Set-Content -LiteralPath ($script:ServerDir + 'staticip.cfg') -Value $a.Alias -ErrorAction SilentlyContinue
        Say "Your IP is already static ($($a.IP)) - I will leave it untouched."
        Write-Log "Static IP lock: already static, left untouched ($($a.Alias): $($a.IP))"
        return $true
    }
    $mask = Get-IPv4Mask $a.PrefixLength
    $backup = $script:ServerDir + 'Logs\staticip.undo.json'
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
        Say "A Windows security window will appear. Click 'Yes' to lock your IP."
        Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $tmp + '"') -Verb RunAs -Wait | Out-Null
        $res = (Get-Content -LiteralPath $result -Raw -ErrorAction SilentlyContinue).Trim()
        if ($res -eq 'OK') {
            Set-Content -LiteralPath ($script:ServerDir + 'staticip.cfg') -Value $a.Alias
            Say "IP locked: $($a.IP) (stays fixed while hosting)."
            Write-Log "Static IP lock applied ($($a.Alias): $($a.IP))"
            return $true
        }
        Say "Could not lock the IP ($res). Was the Windows window cancelled?"
        Write-Log "Static IP lock failed: $res"
        return $false
    } catch {
        Say "Could not lock the IP (was the Windows window cancelled?)."
        Write-Log "Static IP lock failed (exception: $_)"
        return $false
    } finally {
        Remove-Item -LiteralPath $tmp, $result -Force -ErrorAction SilentlyContinue
    }
}

# Restores DHCP only if the tool itself made the DHCP->static switch.
function Restore-DhcpLanIp {
    $backup = $script:ServerDir + 'Logs\staticip.undo.json'
    if (-not (Test-Path -LiteralPath $backup)) {
        Say "IP was not changed by the tool - nothing to restore."
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
        Say "A Windows security window will appear. Click 'Yes' to restore your IP."
        Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $tmp + '"') -Verb RunAs -Wait | Out-Null
        $res = (Get-Content -LiteralPath $result -Raw -ErrorAction SilentlyContinue).Trim()
        if ($res -eq 'OK') {
            Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
            Say "IP restored to DHCP."
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

# ---------------------------------------------------------------------------------------
# IP DETECTION
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

# Reads the router's own WAN IP via UPnP (GetExternalIPAddress). Empty string if unavailable.
function Get-RouterWanIp {
    $igd = Get-UpnpControlUrl
    if (-not $igd) { return '' }
    try {
        $body = "<?xml version=`"1.0`"?><s:Envelope xmlns:s=`"http://schemas.xmlsoap.org/soap/envelope/`" s:encodingStyle=`"http://schemas.xmlsoap.org/soap/encoding/`"><s:Body><u:GetExternalIPAddress xmlns:u=`"$($igd.ServiceType)`"></u:GetExternalIPAddress></s:Body></s:Envelope>"
        $r = Invoke-WebRequest -Uri $igd.ControlUrl -Method Post -Body $body -ContentType 'text/xml; charset="utf-8"' -Headers @{ SOAPACTION = ('"{0}#GetExternalIPAddress"' -f $igd.ServiceType) } -UseBasicParsing -TimeoutSec 6
        $m = [regex]::Match($r.Content, '<NewExternalIPAddress>([\d.]+)</NewExternalIPAddress>')
        if ($m.Success) { return $m.Groups[1].Value }
    } catch { }
    return ''
}

# CGNAT check: carrier-grade NAT public IPs live in the ISP CGNAT range (RFC 6598).
# Checks BOTH the public IP (from the internet) and the router's own WAN IP,
# because some ISPs hand out a 100.x WAN address while the public IP looks normal.
function Test-Cgnat([string]$PublicIp, [switch]$SkipRouterWan) {
    $candidates = @($PublicIp)
    if (-not $SkipRouterWan) {
        $routerWan = Get-RouterWanIp
        if ($routerWan) { $candidates += $routerWan }
    }
    foreach ($ip in $candidates) {
        if (-not $ip) { continue }
        $o = $ip.Split('.')
        if ($o.Count -ne 4) { continue }
        if ([int]$o[0] -eq 100 -and [int]$o[1] -ge 64 -and [int]$o[1] -le 127) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------------------
# VPN SUPPORT (Radmin VPN / Hamachi / ZeroTier / Tailscale)
# ---------------------------------------------------------------------------------------
function Get-VpnApps {
    @(
        @{ Key = 'radmin';    Name = 'Radmin VPN'; Match = 'Radmin';  Exes = @('C:\Program Files (x86)\Radmin VPN\RvRvpnGui.exe', 'C:\Program Files\Radmin VPN\RvRvpnGui.exe', 'C:\Program Files (x86)\Radmin VPN\Radmin_VPN.exe', 'C:\Program Files\Radmin VPN\Radmin_VPN.exe'); Url = 'https://www.radmin-vpn.com/' },
        @{ Key = 'hamachi';   Name = 'Hamachi';    Match = 'Hamachi'; Exes = @('C:\Program Files (x86)\LogMeIn Hamachi\hamachi-2.exe', 'C:\Program Files\LogMeIn Hamachi\hamachi-ui.exe'); Url = 'https://www.vpn.net/' },
        @{ Key = 'zerotier';  Name = 'ZeroTier';   Match = 'ZeroTier';Exes = @('C:\Program Files (x86)\ZeroTier\One\zerotier_desktop_ui.exe', 'C:\Program Files (x86)\ZeroTier\One\ZeroTier_GUI.exe', 'C:\Program Files (x86)\ZeroTier\One\zerotier-one_x64.exe', 'C:\Program Files\ZeroTier\One\zerotier_desktop_ui.exe'); Url = 'https://www.zerotier.com/download/' },
        @{ Key = 'tailscale'; Name = 'Tailscale';  Match = 'Tailscale';Exes = @('C:\Program Files\Tailscale\tailscale-ipn.exe'); Url = 'https://tailscale.com/download' }
    )
}

# Which VPNs are installed on this PC? (install paths, Start-menu shortcuts, registry).
function Get-InstalledVpns {
    $menuDirs = @()
    foreach ($d in @([Environment]::GetFolderPath('CommonStartMenu'), [Environment]::GetFolderPath('StartMenu'))) { if ($d) { $menuDirs += $d } }
    $lnks = @(Get-ChildItem -Path $menuDirs -Recurse -Filter '*.lnk' -File -ErrorAction SilentlyContinue)
    $regItems = @(Get-ItemProperty -Path @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*') -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName })
    $out = @()
    foreach ($app in Get-VpnApps) {
        $exe = $app.Exes | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        $installed = [bool]$exe -or [bool]($lnks | Where-Object { $_.Name -match $app.Match }) -or [bool]($regItems | Where-Object { $_.DisplayName -match $app.Match })
        $out += [pscustomobject]@{ Key = $app.Key; Name = $app.Name; Url = $app.Url; Exe = $(if ($exe) { $exe } else { '' }); Installed = $installed }
    }
    return $out
}

# Which VPNs are RUNNING right now (adapter up), with their IPs.
function Get-VpnIps {
    $out = @()
    try {
        $names = @{ radmin = 'Radmin VPN'; hamachi = 'Hamachi'; zerotier = 'ZeroTier'; tailscale = 'Tailscale' }
        $adaps = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' -and $_.InterfaceAlias -match 'Radmin|Hamachi|LogMeIn|ZeroTier|Tailscale' })
        foreach ($a in $adaps) {
            $key = if ($a.InterfaceAlias -match 'Radmin') { 'radmin' }
                   elseif ($a.InterfaceAlias -match 'Hamachi|LogMeIn') { 'hamachi' }
                   elseif ($a.InterfaceAlias -match 'ZeroTier') { 'zerotier' }
                   elseif ($a.InterfaceAlias -match 'Tailscale') { 'tailscale' } else { 'vpn' }
            $ip = ''
            try { $ip = ((Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress) } catch { }
            $out += [pscustomobject]@{ Key = $key; Name = $names[$key]; Ip = $ip; Alias = $a.InterfaceAlias }
        }
        $dedicated = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '26.*' -or $_.IPAddress -like '25.*' })
        foreach ($d in $dedicated) {
            if ($out | Where-Object { $_.Ip -eq $d.IPAddress }) { continue }
            $key = if ($d.IPAddress -like '26.*') { 'radmin' } else { 'hamachi' }
            $out += [pscustomobject]@{ Key = $key; Name = $names[$key]; Ip = $d.IPAddress; Alias = 'VPN adapter' }
        }
    } catch { }
    return $out
}

# Starts an installed VPN (or opens its official download page when missing).
function Start-OrDownload-Vpn($App, [int]$WaitSeconds = 20) {
    if (-not $App.Installed) {
        try { Start-Process $App.Url } catch { }
        return "Opened the official page: $($App.Url). Install it, then come back here."
    }
    if (-not $App.Exe) {
        return "$($App.Name) is installed but I can't find its program file. Start it from the Start menu, then refresh."
    }
    try {
        Start-Process -FilePath $App.Exe -ErrorAction Stop
    } catch {
        return "Could not start $($App.Name) automatically. Launch it yourself from the Start menu, or reinstall it."
    }
    for ($i = 0; $i -lt $WaitSeconds; $i += 4) {
        Start-Sleep -Seconds 4
        $hit = @(Get-VpnIps | Where-Object { $_.Key -eq $App.Key -and $_.Ip })
        if ($hit.Count) { return "$($App.Name) connected - friends join via $($hit[0].Ip)" }
    }
    return "$($App.Name) is opening. If it shows no VPN IP, click/join your network inside the app window, then refresh."
}

# Turns a VPN completely off with one press: kills its processes, disconnects
# Tailscale and stops the background service (one UAC prompt if a service is used).
function Stop-VpnApp([string]$Key) {
    $defs = @{
        radmin    = @{ Name = 'Radmin VPN'; Exes = @('RvRvpnGui.exe', 'Radmin_VPN.exe', 'Radmin.exe'); Srv = 'Radmin*' }
        hamachi   = @{ Name = 'Hamachi';    Exes = @('hamachi-2.exe', 'hamachi-ui.exe', 'hamachi.exe'); Srv = 'Hamachi2Svc' }
        zerotier  = @{ Name = 'ZeroTier';   Exes = @('zerotier_desktop_ui.exe', 'ZeroTier_GUI.exe', 'zerotier-one_x64.exe'); Srv = 'ZeroTierOne' }
        tailscale = @{ Name = 'Tailscale';  Exes = @('tailscale-ipn.exe'); Srv = 'Tailscale'; Cli = 'C:\Program Files\Tailscale\tailscale.exe' }
    }
    if (-not $defs.ContainsKey($Key)) { return "Unknown VPN: $Key" }
    $d = $defs[$Key]
    $what = @()
    foreach ($n in $d.Exes) {
        Get-Process -Name ($n -replace '\.exe$', '') -ErrorAction SilentlyContinue | ForEach-Object {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            $what += $n
        }
    }
    if ($Key -eq 'tailscale' -and (Test-Path -LiteralPath $d.Cli)) {
        try { & $d.Cli down 2>$null | Out-Null; $what += 'tailscale down' } catch { }
    }
    $svc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $d.Srv -or $_.DisplayName -like $d.Srv } | Select-Object -First 1
    if ($svc -and $svc.Status -ne 'Stopped') {
        $tmp = Join-Path $env:TEMP ('kbvpn-' + [guid]::NewGuid().ToString('N') + '.ps1')
        Set-Content -LiteralPath $tmp -Value ("Stop-Service -Name '" + $svc.Name + "' -Force -ErrorAction SilentlyContinue; Set-Service -Name '" + $svc.Name + "' -StartupType Manual -ErrorAction SilentlyContinue")
        try {
            Say "A Windows security window will appear. Click 'Yes' to stop the $($d.Name) background service."
            Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $tmp + '"') -Verb RunAs -Wait | Out-Null
            Start-Sleep -Seconds 2
            $what += 'service'
        } catch { }
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    $still = @(Get-VpnIps | Where-Object { $_.Key -eq $Key })
    if ($still.Count) {
        return "$($d.Name) is still showing a network adapter - close it from its tray icon too. Friends should no longer see it as connected."
    }
    if ($what.Count) { Write-Log "VPN stopped: $Key ($($what -join ', '))" }
    return "$($d.Name) is now fully stopped."
}

# ---------------------------------------------------------------------------------------
# UPnP
# ---------------------------------------------------------------------------------------
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
    for ($i = 0; $i -lt 3; $i++) {
        try {
            $r = Invoke-RestMethod -Uri "https://ifconfig.co/port/$Port" -Headers @{ 'User-Agent' = 'K-BNG-M-Hoster' } -TimeoutSec 10
            if ($null -ne $r.reachable) { return [bool]$r.reachable }
        } catch { }
        if ($i -lt 2) { Start-Sleep -Seconds 3 }
    }
    try {
        $t = (Invoke-WebRequest -Uri "https://api.hackertarget.com/nmap/?q=$PublicIp`:$Port" -UseBasicParsing -TimeoutSec 20).Content
        if ($t -match 'Host is up' -and $t -match "$Port/tcp\s+open") { return $true }
        if ($t -match "$Port/tcp\s+(filtered|closed)") { return $false }
    } catch { }
    return $null
}

# Public IP with a 24h disk cache (Logs\publicip.json) - never blocks startup.
function Get-PublicIpCached {
    $cache = $script:ServerDir + 'Logs\publicip.json'
    if (Test-Path -LiteralPath $cache) {
        try {
            $j = Get-Content -LiteralPath $cache -Raw | ConvertFrom-Json
            if ($j.ip -and ((Get-Date) - [datetime]$j.checked).TotalHours -lt 24) { return [string]$j.ip }
        } catch { }
    }
    $public = ''
    try {
        $public = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 8).ToString().Trim()
        if ($public) { @{ ip = $public; checked = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $cache }
    } catch { }
    return $public
}

function Get-ConnectionInfo {
    param([switch]$SkipRouterWan)
    $port = Get-ServerPort
    $lan = Get-LanIp
    $tail = ''
    try {
        $tailExe = 'C:\Program Files\Tailscale\tailscale.exe'
        if (Test-Path -LiteralPath $tailExe) { $tail = (& $tailExe ip -4 2>$null | Select-Object -First 1).Trim() }
        elseif (Get-Command tailscale -ErrorAction SilentlyContinue) { $tail = (& tailscale ip -4 2>$null | Select-Object -First 1).Trim() }
    } catch { }
    $public = Get-PublicIpCached
    return [pscustomobject]@{ Port = $port; LAN = $lan; Tailscale = $tail; Public = $public; Vpn = @(Get-VpnIps | Where-Object { $_.Key -ne 'tailscale' }); Cgnat = (Test-Cgnat $public -SkipRouterWan:$SkipRouterWan) }
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

# Teredo state: 'disabled' / 'client' / 'unknown' (used by the Fix scan; re-enable is one click).
function Test-TeredoState {
    try {
        $out = (& netsh interface teredo show state 2>$null | Out-String)
        if ($out -match '(?i)Type\s*:\s*disabled') { return 'disabled' }
        if ($out -match '(?i)Type\s*:\s*(\S+)') { return $Matches[1] }
    } catch { }
    return 'unknown'
}

# Re-enables Teredo via an elevated helper window (one UAC prompt). Reversible.
function Enable-Teredo {
    $resultFile = Join-Path $env:TEMP ('kbter-' + [guid]::NewGuid().ToString('N') + '.txt')
    $script = @"
`$resultFile = '$resultFile'
try { netsh interface teredo set state type=enterpriseclient | Out-Null; Set-Content -LiteralPath `$resultFile -Value '[OK] Teredo enabled' } catch { Set-Content -LiteralPath `$resultFile -Value '[FAIL] ' + `$_.Exception.Message }
Write-Host ""
Write-Host "Teredo enabled. You can disable it again anytime from Fix Problems."
Read-Host "Press Enter to close this window"
"@
    $tmp = Join-Path $env:TEMP ('kbter-' + [guid]::NewGuid().ToString('N') + '.ps1')
    Set-Content -LiteralPath $tmp -Value $script
    try {
        Say "A Windows security window will appear. Click 'Yes' to enable Teredo."
        Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $tmp + '"') -Verb RunAs -Wait | Out-Null
        if (Test-Path -LiteralPath $resultFile) {
            $msg = Get-Content -LiteralPath $resultFile -Raw
            if ($msg -match '\[FAIL\]') { Say "Could not enable Teredo - see the message above." } else { Say "Teredo is enabled again (only needed by old games / rare setups)." }
        } else {
            Say "Teredo enable was cancelled (no Windows window appeared)."
        }
    } catch {
        Say "Could not enable Teredo (was the Windows window cancelled?)."
    }
    Remove-Item -LiteralPath $tmp, $resultFile -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------------------
# DIAGNOSTICS / UPDATE CHECK
# ---------------------------------------------------------------------------------------
function Get-ServerDiag {
    $log = $script:RootDir + 'Server.log'
    $c = @()
    if (Test-Path -LiteralPath $log) { $c = Get-Content -LiteralPath $log -Tail 20 }
    $txt = $c -join ' '
    if ($c.Count -eq 0) {
        return "The server exited without writing a log. This usually means the Visual C++ runtime is missing - run 'Fix Problems' to fix it."
    }
    if ($txt -match '(?i)(invalid auth|authentication failed|auth.*(invalid|wrong|rejected|missing))') {
        return "Your server key is wrong or missing. Set it up in Settings."
    }
    if ($txt -match '(?i)(bind|already in use|address already|access denied|permission denied)') {
        return "Port $script:ServerPort is already in use. Use 'Use a free port' in Settings or Fix Problems."
    }
    if ($txt -match '(?i)(0xc000007b|vcruntime140|msvcp|vc_redist)') {
        return "Visual C++ runtime is missing. Use 'Install Visual C++' in Fix Problems."
    }
    if ($txt -match '(?i)(keymaster|backend|timeout|unreachable)') {
        return "I could not reach BeamMP's servers. Check your internet connection."
    }
    if ($txt -match '(?i)(map|level).*(missing|invalid|not found)') {
        return "The chosen map is missing. Change the Map setting in ServerConfig.toml."
    }
    return "Unknown error. Last server log lines:" + [Environment]::NewLine + ($c | Select-Object -Last 5 | ForEach-Object { "    $_" })
}

# Cached 24h, never blocks startup. Returns a message string ('' when nothing new).
function Check-ForUpdates {
    $cache = $script:ServerDir + 'Logs\update_check.json'
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
            $local = (Get-Item -LiteralPath ($script:ServerDir + 'BeamMP-Server.exe')).LastWriteTime
            $remote = [datetime]$r.published_at
            if ($remote -gt $local) {
                $msg = "New BeamMP-Server $($r.tag_name) is available (published $($r.published_at)). Download: $($r.html_url)"
            }
            @{ checked = (Get-Date).ToString('o'); msg = $msg } | ConvertTo-Json | Set-Content -LiteralPath $cache
        } catch { $msg = '' }
    }
    return $msg
}

# ---------------------------------------------------------------------------------------
# TOOL SELF-UPDATE (checks THIS app on GitHub - not the BeamMP server)
# ---------------------------------------------------------------------------------------
# Returns $null when up to date, or @{ Tag; Version; Url; ZipUrl; ZipName; Notes }.
function Get-ToolUpdateInfo {
    param([string]$CurrentVersion)
    try {
        $r = Invoke-RestMethod -Uri 'https://api.github.com/repos/Kinan0713/K-BNG-M-Hoster/releases/latest' -Headers @{ 'User-Agent' = 'K-BNG-M-Hoster' } -TimeoutSec 6
        $tag = [string]$r.tag_name
        $ver = $tag -replace '^[vV]', ''
        if ($ver -notmatch '^\d+\.\d+\.\d+$') { return $null }
        if ([version]$ver -le [version]$CurrentVersion) { return $null }
        $zip = @($r.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1)
        if (-not $zip) { return $null }
        return [pscustomobject]@{ Tag = $tag; Version = $ver; Url = $r.html_url; ZipUrl = $zip[0].browser_download_url; ZipName = $zip[0].name; Notes = [string]$r.body }
    } catch { return $null }
}

# Downloads + extracts the new release into Server\Backups\updates\<tag>. Returns the staging folder.
function Invoke-ToolDownload {
    param([string]$Tag, [string]$ZipUrl, [string]$ZipName)
    $updates = $script:ServerDir + 'Backups\updates'
    if (-not (Test-Path -LiteralPath $updates)) { New-Item -ItemType Directory -Path $updates -Force | Out-Null }
    $zipPath = Join-Path $updates $ZipName
    Invoke-WebRequest -Uri $ZipUrl -OutFile $zipPath -Headers @{ 'User-Agent' = 'K-BNG-M-Hoster' } -TimeoutSec 120
    if (-not (Test-Path -LiteralPath $zipPath) -or (Get-Item -LiteralPath $zipPath).Length -eq 0) { throw 'The download failed (empty file). Try again, or download it from the browser instead.' }
    $staging = Join-Path $updates $Tag
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath $staging -Force
    if (-not (Test-Path -LiteralPath (Join-Path $staging 'Server\Play_BeamMP.ps1')) -or -not (Test-Path -LiteralPath (Join-Path $staging 'Start_Here.bat'))) { throw 'The downloaded file is not a K BNG M Hoster update - aborted.' }
    return $staging
}

# Full fix-menu report: one object per check with Key / Label / Ok / Detail / Action / NeedsAction.
# Streams progress through Say() so the GUI log shows the scan live.
function Get-FixReport {
    $rows = @()
    Say "Fix scan: checking the server key..."
    $keyOk = Test-AuthKeyConfigured
    $rows += [pscustomobject]@{ Key = 'AUTHKEY'; Label = 'Server key'; Ok = $keyOk; Detail = $(if ($keyOk) { 'present' } else { 'missing' }); Action = 'Set up my server key'; NeedsAction = -not $keyOk }
    Say "Fix scan: checking the launcher..."
    $launcherOk = Test-Path -LiteralPath $script:LauncherPath
    $rows += [pscustomobject]@{ Key = 'LAUNCHER'; Label = 'BeamMP Launcher'; Ok = $launcherOk; Detail = $(if ($launcherOk) { 'installed' } else { 'not installed' }); Action = 'Open the BeamMP Launcher download'; NeedsAction = -not $launcherOk }
    Say "Fix scan: checking BeamNG.drive..."
    $game = Get-BeamNGPath
    $rows += [pscustomobject]@{ Key = 'BEAMNG'; Label = 'BeamNG.drive'; Ok = [bool]$game; Detail = $(if ($game) { 'found' } else { 'not found' }); Action = 'Open BeamNG.drive download'; NeedsAction = -not $game }
    Say "Fix scan: checking the port..."
    $port = Get-ServerPort
    $busy = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    $rows += [pscustomobject]@{ Key = 'PORT'; Label = "Port $port"; Ok = -not $busy; Detail = $(if ($busy) { "in use by another program" } else { 'free' }); Action = 'Use a free port automatically'; NeedsAction = [bool]$busy }
    Say "Fix scan: checking the Visual C++ runtime..."
    $vcOk = Test-Path -LiteralPath "$env:WINDIR\System32\vcruntime140.dll"
    $rows += [pscustomobject]@{ Key = 'VC'; Label = 'Visual C++ runtime'; Ok = $vcOk; Detail = $(if ($vcOk) { 'present' } else { 'missing' }); Action = 'Open the Visual C++ installer'; NeedsAction = -not $vcOk }
    Say "Fix scan: checking the map..."
    $curMap = Get-ServerMap
    $curMapName = Get-MapNameFromPath $curMap
    $mapOk = [bool]$curMapName
    $mapFound = $false
    if ($mapOk) { $mapFound = [bool](@(Get-AvailableMaps | Where-Object { $_.Name -ieq $curMapName } | Select-Object -First 1).Count) }
    $rows += [pscustomobject]@{ Key = 'MAP'; Label = 'Map'; Ok = ($mapOk -and $mapFound); Detail = $(if (-not $mapOk) { "$curMap is not a valid map path (must end in /info.json)" } elseif ($mapFound) { "$curMap" } else { "$curMap is not among the maps found on this PC - the server will not start with it" }); Action = 'Choose a map in Settings'; NeedsAction = (-not $mapOk -or -not $mapFound) }
    Say "Fix scan: checking the firewall..."
    $fwRulePort = Get-FirewallRulePort
    $fwPortMismatch = ($fwRulePort -and $fwRulePort -ne 'program' -and $fwRulePort -ne "$port")
    $fwOk = [bool]$fwRulePort -and -not $fwPortMismatch
    $rows += [pscustomobject]@{ Key = 'FW'; Label = 'Firewall (server)'; Ok = $fwOk; Detail = $(if (-not $fwRulePort) { 'BeamMP-Server may be blocked' } elseif ($fwPortMismatch) { "rules exist for port $fwRulePort but the server now uses $port" } else { 'BeamMP-Server is allowed' }); Action = 'Add a firewall rule (asks for admin)'; NeedsAction = -not $fwOk }
    Say "Fix scan: checking BeamNG.drive through the firewall..."
    $fwBeamngOk = Test-BeamNGFirewallRule
    $rows += [pscustomobject]@{ Key = 'FWBEAMNG'; Label = 'Firewall (BeamNG.drive)'; Ok = $fwBeamngOk; Detail = $(if ($fwBeamngOk) { 'BeamNG.drive is allowed' } else { 'no rule yet - if BeamNG.drive ever shows a firewall warning or friends cannot connect, add it' }); Action = 'Add a firewall rule for BeamNG.drive (asks for admin)'; NeedsAction = -not $fwBeamngOk }
    Say "Fix scan: checking Tailscale..."
    $tailOk = Test-Path -LiteralPath 'C:\Program Files\Tailscale\tailscale.exe'
    $rows += [pscustomobject]@{ Key = 'TAIL'; Label = 'Tailscale'; Ok = $tailOk; Detail = $(if ($tailOk) { 'installed' } else { 'not installed (friends can still join via public IP)' }); Action = ''; NeedsAction = $false }
    Say "Fix scan: checking Teredo..."
    $teredo = Test-TeredoState
    $rows += [pscustomobject]@{ Key = 'TEREDO'; Label = 'Teredo (advanced)'; Ok = $true; Detail = $(if ($teredo -eq 'disabled') { 'disabled (recommended for hosting - friends connect over IPv4 directly)' } elseif ($teredo -eq 'unknown') { 'state unknown (nothing to do)' } else { 'enabled (rarely needed for hosting - fine to leave)' }); Action = $(if ($teredo -eq 'disabled') { 'Re-enable Teredo (only if you need it)' } else { '' }); NeedsAction = $false }
    Say "Fix scan: checking VPNs..."
    $vpnRunning = @(Get-VpnIps)
    if ($vpnRunning.Count) {
        foreach ($v in $vpnRunning) {
            $ok = [bool]$v.Ip
            $rows += [pscustomobject]@{ Key = 'VPN'; Label = $v.Name; Ok = $ok; Detail = $(if ($v.Ip) { "running - friends can join via $($v.Ip)" } else { 'running but has no VPN IP yet - wait for it to connect' }); Action = ''; NeedsAction = $false }
        }
    } else {
        $rows += [pscustomobject]@{ Key = 'VPN'; Label = 'VPN'; Ok = $true; Detail = 'none running (VPNs are only needed when port forwarding is impossible - see VPN Manager)'; Action = ''; NeedsAction = $false }
    }
    Say "Fix scan: checking mods..."
    $mi = Get-ModsInfo
    $rows += [pscustomobject]@{ Key = 'MODS'; Label = 'Mods'; Ok = $true; Detail = "$(@($mi.Enabled).Count) enabled, $(@($mi.Disabled).Count) disabled - manage them from the Mods page"; Action = 'Open the Mods page'; NeedsAction = $false }
    Say "Fix scan: checking disk space..."
    try {
        $drive = (Get-Item -LiteralPath $script:RootDir).PSDrive
        $freeGb = [double]$drive.Free / 1GB
        $rows += [pscustomobject]@{ Key = 'DISK'; Label = 'Disk space'; Ok = $freeGb -ge 0.5; Detail = ("{0:N1} GB free on drive {1}" -f $freeGb, $drive.Name); Action = ''; NeedsAction = $freeGb -lt 0.5 }
    } catch {
        $rows += [pscustomobject]@{ Key = 'DISK'; Label = 'Disk space'; Ok = $true; Detail = 'could not check'; Action = ''; NeedsAction = $false }
    }
    Say "Fix scan: checking the server version..."
    $verMsg = Check-ForUpdates
    $rows += [pscustomobject]@{ Key = 'VER'; Label = 'Server version'; Ok = -not $verMsg; Detail = $(if ($verMsg) { $verMsg } else { 'up to date' }); Action = 'Open the BeamMP-Server download page'; NeedsAction = -not $verMsg }
    Say "Fix scan: checking the public IP..."
    $pubIp = Get-PublicIpCached
    $cgnat = Test-Cgnat $pubIp
    if ($cgnat) {
        $routerWan = Get-RouterWanIp
        $rows += [pscustomobject]@{ Key = 'CGNAT'; Label = 'CGNAT'; Ok = $false; Detail = "detected - your ISP is behind carrier-grade NAT. Internet sees $pubIp. Port forwarding CANNOT work. Use Tailscale (free) or ask your ISP for a public IP."; Action = 'Explain CGNAT (why forwarding can never work here)'; NeedsAction = $true }
    } elseif ($pubIp) {
        $rows += [pscustomobject]@{ Key = 'CGNAT'; Label = 'Public IP'; Ok = $true; Detail = "Public IP: $pubIp"; Action = ''; NeedsAction = $false }
    }
    $serverListening = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -ne $PID -and $_.LocalAddress -notmatch '^(127\.|::1$)' } | Select-Object -First 1
    if ($serverListening) {
        Say "Fix scan: testing the external reachability (server is live)..."
        $reachable = Test-ExternalReachability -PublicIp $pubIp -Port $port
        if ($reachable -eq $true) {
            $rows += [pscustomobject]@{ Key = 'EXT'; Label = 'External reachability'; Ok = $true; Detail = "$($pubIp):$port IS reachable from the internet"; Action = ''; NeedsAction = $false }
        } elseif ($reachable -eq $false) {
            $rows += [pscustomobject]@{ Key = 'EXT'; Label = 'External reachability'; Ok = $false; Detail = "$($pubIp):$port NOT reachable - check forwarding/firewall"; Action = 'Show step-by-step fixes for the NOT-reachable result'; NeedsAction = $true }
        } else {
            $rows += [pscustomobject]@{ Key = 'EXT'; Label = 'External reachability'; Ok = $true; Detail = 'could not verify (test services unreachable) - check https://checkbeammp.beammp.com manually'; Action = ''; NeedsAction = $false }
        }
    } else {
        $rows += [pscustomobject]@{ Key = 'EXT'; Label = 'External reachability'; Ok = $true; Detail = 'not tested - the server is not running right now (start the server first, then re-scan while it is live)'; Action = ''; NeedsAction = $false }
    }
    Say "Fix scan: done."
    return $rows
}

# One-click auto-fix: safe fixes that need no human decision. Manual-only steps
# (server key, CGNAT/VPN) are reported. Returns a summary message.
function Fix-AllPossible {
    $fixed = @()
    $manual = @()

    $keyOk = Test-AuthKeyConfigured
    if (-not $keyOk) { $manual += 'server key (Settings tab)' }

    $port = Get-ServerPort
    $busy = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($busy) {
        Say "Fix all: port $port is busy - picking a free port..."
        $newPort = Set-FreePort -Port (Get-FreePort)
        $fixed += "port $port was busy - now using $newPort"
    }

    $fwOk = [bool](Get-FirewallRulePort)
    if (-not $fwOk) {
        Say "Fix all: adding the firewall rule (a Windows security window may appear - click Yes)..."
        $null = Add-FirewallRule
        if (Test-FirewallRule) { $fixed += 'firewall rule added' }
        else { $manual += 'firewall rule (the admin window was cancelled?)' }
    }

    if (-not (Test-BeamNGFirewallRule)) {
        Say "Fix all: adding a firewall rule for BeamNG.drive (a Windows security window may appear - click Yes)..."
        $r = Add-BeamNGFirewallRule
        Say $r
        if (Test-BeamNGFirewallRule) { $fixed += 'BeamNG.drive firewall rule added' }
    }

    $curMap = Get-ServerMap
    $curMapName = Get-MapNameFromPath $curMap
    $mapOk = [bool]$curMapName
    if ($mapOk) {
        $mapFound = [bool](@(Get-AvailableMaps | Where-Object { $_.Name -ieq $curMapName } | Select-Object -First 1).Count)
        if (-not $mapFound) {
            Say "Fix all: the current map is missing - switching to the default map..."
            $msg = Set-ServerMap -LevelName 'gridmap_v2'
            Say $msg
            $fixed += 'map was invalid - switched to gridmap_v2'
        }
    }

    Say "Fix all: opening the port on the router via UPnP..."
    if (Add-UpnpPortForward $port) { $fixed += "port $port forwarded on the router (UPnP)" }
    else { $manual += 'port forwarding on the router (UPnP failed - forward port manually or use a VPN)' }

    if ($manual.Count) {
        Say "Fix all: still needs you: $($manual -join ', ')."
    }
    if ($fixed.Count) {
        Say "Fix all: done - $($fixed -join '; ')."
        return "Fixed: $($fixed -join '; ')."
    }
    Say "Fix all: nothing to fix - everything looks fine."
    return "Nothing to fix - everything looks fine."
}

# ---------------------------------------------------------------------------------------
# MOD MANAGER
# ---------------------------------------------------------------------------------------
function Get-ModsInfo {
    $client = $script:RootDir + 'Resources\Client'
    $backup = $script:ServerDir + 'Backups\mods'
    $enabled = @(Get-ChildItem -LiteralPath $client -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'mods.json' })
    $disabled = @()
    if (Test-Path -LiteralPath $backup) { $disabled = @(Get-ChildItem -LiteralPath $backup -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'mods.json' }) }
    return [pscustomobject]@{ Enabled = $enabled; Disabled = $disabled }
}

function Disable-Mod([string]$Name) {
    $client = $script:RootDir + 'Resources\Client'
    $backup = $script:ServerDir + 'Backups\mods'
    $src = Join-Path $client $Name
    if (-not (Test-Path -LiteralPath $src)) { return "Could not find $Name." }
    try {
        if (-not (Test-Path -LiteralPath $backup)) { New-Item -ItemType Directory -Path $backup -Force | Out-Null }
        Move-Item -LiteralPath $src -Destination (Join-Path $backup $Name) -Force
        Write-Log "Mod disabled: $Name"
        return "Disabled: $Name"
    } catch { return "Could not move file (is it in use?)." }
}

function Enable-Mod([string]$Name) {
    $client = $script:RootDir + 'Resources\Client'
    $backup = $script:ServerDir + 'Backups\mods'
    $src = Join-Path $backup $Name
    if (-not (Test-Path -LiteralPath $src)) { return "Could not find $Name." }
    try {
        Move-Item -LiteralPath $src -Destination $client -Force
        Write-Log "Mod enabled: $Name"
        return "Enabled: $Name"
    } catch { return "Could not move file." }
}

# Scans mods for executable content and quarantines anything suspicious.
function Scan-Mods {
    $client = $script:RootDir + 'Resources\Client'
    $qroot = $script:ServerDir + 'Quarantine'
    if (-not (Test-Path -LiteralPath $client)) { return "Resources\Client folder not found." }
    $mj = $client + '\mods.json'
    if (Test-Path -LiteralPath $mj) {
        $raw = Get-Content -LiteralPath $mj -Raw
        if ($raw -match '^\s*(null|\[\])\s*$') { Set-Content -LiteralPath $mj -Value '{}' }
    }
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
        Write-Log "Mod scan: $($s.Count) suspect file(s) quarantined"
        return "[SECURITY] $($s.Count) suspect file(s) quarantined."
    }
    return "Scan clean - no suspicious files found."
}

# ---------------------------------------------------------------------------------------
# PRESETS (named snapshots of server settings + the enabled mod list)
# ---------------------------------------------------------------------------------------
function Get-PresetPath([string]$Name) {
    $dir = $script:ServerDir + 'Presets'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $safe = ($Name -replace '[^\w\- ]', '').Trim()
    return (Join-Path $dir ($safe + '.json'))
}

function Get-Presets {
    $dir = $script:ServerDir + 'Presets'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object { $_.BaseName } | Sort-Object)
}

function Save-Preset([string]$Name) {
    if (-not $Name -or -not $Name.Trim()) { return "Type a preset name first." }
    $settings = @{
        Name               = Get-ConfigValue 'Name'
        MaxPlayers         = Get-ConfigValue 'MaxPlayers'
        MaxCars            = Get-ConfigValue 'MaxCars'
        Description        = Get-ConfigValue 'Description'
        Tags               = Get-ConfigValue 'Tags'
        AllowGuests        = Get-ConfigValue 'AllowGuests'
        LogChat            = Get-ConfigValue 'LogChat'
        Debug              = Get-ConfigValue 'Debug'
        InformationPacket  = Get-ConfigValue 'InformationPacket'
        Private            = Get-ConfigValue 'Private'
        Map                = Get-ServerMap
    }
    $mods = @(Get-ChildItem -LiteralPath ($script:RootDir + 'Resources\Client') -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'mods.json' } | ForEach-Object { $_.Name })
    $preset = @{ Name = $Name.Trim(); Saved = (Get-Date).ToString('o'); Settings = $settings; Mods = $mods } | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath (Get-PresetPath $Name) -Value $preset -Encoding UTF8
    Write-Log "Preset saved: $Name ($(@($mods).Count) mods)"
    return "Preset '$Name' saved - it includes your server settings and the $(@($mods).Count) enabled mod(s)."
}

function Load-Preset([string]$Name) {
    $p = Get-PresetPath $Name
    if (-not (Test-Path -LiteralPath $p)) { return "Preset '$Name' not found." }
    $data = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
    $vals = @{}
    foreach ($k in @('Name', 'MaxPlayers', 'MaxCars', 'Description', 'Tags', 'AllowGuests', 'LogChat', 'Debug', 'InformationPacket', 'Private', 'Map')) {
        $v = $data.Settings.$k
        if ($null -eq $v -or "$v" -eq '') { continue }
        if ($v -is [int] -or $v -is [long] -or $v -match '^\d+$') { $vals[$k] = "$v"; continue }
        if ($v -is [bool] -or $v -match '^(true|false)$') { $vals[$k] = "$v".ToLower(); continue }
        $vals[$k] = '"' + ("$v".Replace('"', "'")) + '"'
    }
    $msg = Set-ServerConfig -Values $vals
    $want = @($data.Mods)
    $info = Get-ModsInfo
    $changed = 0
    foreach ($f in @($info.Enabled)) {
        if ($f.Name -eq 'mods.json') { continue }
        if ($want -notcontains $f.Name) { $r = Disable-Mod $f.Name; if ($r -match '^Disabled') { $changed++ } }
    }
    foreach ($f in @($info.Disabled)) {
        if ($want -contains $f.Name) { $r = Enable-Mod $f.Name; if ($r -match '^Enabled') { $changed++ } }
    }
    Write-Log "Preset loaded: $Name (mods changed: $changed)"
    return "Preset '$Name' applied. ($msg, $changed mod(s) switched to match it.)"
}

function Delete-Preset([string]$Name) {
    $p = Get-PresetPath $Name
    if (-not (Test-Path -LiteralPath $p)) { return "Preset '$Name' not found." }
    Remove-Item -LiteralPath $p -Force
    Write-Log "Preset deleted: $Name"
    return "Preset '$Name' deleted."
}

# ---------------------------------------------------------------------------------------
# CLEAN FOR SHARING (removes every personal/runtime file before zipping the folder)
# ---------------------------------------------------------------------------------------
function Invoke-CleanForSharing {
    $removed = @()
    if (Test-StaticIpLocked) {
        Say "IP lock is on - restoring DHCP first..."
        $null = Restore-DhcpLanIp
    }
    foreach ($p in @('Logs', 'Backups', 'Quarantine', 'CONNECTING.txt', 'Server.log', '.env', 'webhook.txt', 'staticip.cfg')) {
        $full = $script:ServerDir + $p
        if (Test-Path -LiteralPath $full) {
            try {
                Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
                $removed += $p
            } catch {
                Say "Could not remove $p (is it in use?)."
            }
        }
    }
    $rootLog = $script:RootDir + 'Server.log'
    if (Test-Path -LiteralPath $rootLog) {
        try { Remove-Item -LiteralPath $rootLog -Force -ErrorAction Stop; $removed += '(top) Server.log' } catch { }
    }
    $cfgPath = $script:RootDir + 'ServerConfig.toml'
    $lines = @(Get-Content -LiteralPath $cfgPath) | ForEach-Object {
        if ($_ -match '^\s*AuthKey\s*=') { 'AuthKey = ""' } else { $_ }
    }
    Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
    Write-Log "Clean-for-sharing: removed $($removed -join ', ')"
    if ($removed.Count) {
        return "Removed: $($removed -join ', ')" + [Environment]::NewLine + "ServerConfig.toml: AuthKey cleared. The folder is now safe to zip and share."
    }
    return "Nothing to clean - the folder was already clean. ServerConfig.toml: AuthKey cleared."
}

# ---------------------------------------------------------------------------------------
# SERVER SESSION (runs in a background runspace; reports via Say into the GUI queue)
# ---------------------------------------------------------------------------------------
function Start-HosterSession {
    param($Queue, $State)
    $script:Q = $Queue
    $script:St = $State
    $logDir = $script:ServerDir + 'Logs'
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    Write-Log "===== Session starting ====="

    if (-not (Test-Path -LiteralPath $script:LauncherPath)) {
        Say "The free BeamMP Launcher is required to detect your game session."
        Say "Download and install it from https://beammp.com, then press Start again."
        $script:St.SessionEnded = (Get-Date).ToString('o')
        return
    }

    $serverPort = Get-ServerPort
    $busy = Get-NetTCPConnection -LocalPort $serverPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($busy) {
        $np = Get-FreePort
        Say "Port $serverPort was in use, switching to port $np automatically."
        $null = Set-FreePort -Port $np
        $serverPort = $np
        Say "IMPORTANT: your router/UPnP must forward the NEW port $np (TCP+UDP). Trying to open it now..."
        if (Add-UpnpPortForward $np) {
            Say "UPnP: port $np (TCP+UDP) forwarded on the router."
            Write-Log "UPnP forwarded new port $np after busy-port switch"
        } else {
            Say "UPnP unavailable - forward port $np (TCP+UDP) manually in your router."
            Write-Log "UPnP failed for new port $np after busy-port switch"
        }
    }

    if (Get-Process -Name 'BeamMP-Server' -ErrorAction SilentlyContinue) {
        Say "A BeamMP server is already running. Stop it first, then try again."
        $script:St.SessionEnded = (Get-Date).ToString('o')
        return
    }

    $leftover = @(Get-Process -Name 'BeamMP-Launcher' -ErrorAction SilentlyContinue)
    if ($leftover.Count) {
        Write-Log "Stopped $($leftover.Count) leftover BeamMP-Launcher process(es) from an earlier session"
        $leftover | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    $serverName = 'K BNG M Server'
    $m = Select-String -LiteralPath ($script:RootDir + 'ServerConfig.toml') -Pattern '^\s*Name\s*=\s*"(.*)"' | Select-Object -First 1
    if ($m) { $serverName = $m.Matches[0].Groups[1].Value }

    $clientDir = $script:RootDir + 'Resources\Client'
    $quarantineDir = $script:ServerDir + 'Quarantine'
    if (-not (Test-Path -LiteralPath $quarantineDir)) { New-Item -ItemType Directory -Path $quarantineDir -Force | Out-Null }
    if (Test-Path -LiteralPath $clientDir) {
        Say "Quick safety check of your mods..."
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
            Say "[SECURITY] Moved $($suspects.Count) suspicious file(s) out of the mods folder."
        }
    }

    $authKey = $env:BEAMMP_AUTHKEY
    $authSource = 'BEAMMP_AUTHKEY env var'
    $envFile = $script:ServerDir + '.env'
    if (-not $authKey) {
        if (Test-Path -LiteralPath $envFile) {
            $authKey = Get-Content -LiteralPath $envFile | Where-Object { $_ -match '^\s*BEAMMP_AUTHKEY\s*=' } | Select-Object -First 1 |
                ForEach-Object { ($_ -replace '^\s*BEAMMP_AUTHKEY\s*=', '').Trim().Trim('"', "'") }
            if ($authKey) { $authSource = '.env file' }
        }
    }
    $cfgPath = $script:RootDir + 'ServerConfig.toml'
    if ($authKey) {
        $lines = Get-Content -LiteralPath $cfgPath
        $lines = $lines | ForEach-Object {
            if ($_ -match '^\s*AuthKey\s*=') { 'AuthKey = "' + $authKey + '"' } else { $_ }
        }
        Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
        Write-Log "AuthKey injected from $authSource"
    } else {
        Say "No server key found. Set it up in Settings (or Fix Problems), then press Start again."
        $script:St.SessionEnded = (Get-Date).ToString('o')
        return
    }

    $fwDeclined = $script:ServerDir + 'Logs\fw.declined'
    if (-not (Test-FirewallRule) -and -not (Test-Path -LiteralPath $fwDeclined)) {
        Say "Opening Windows Firewall for the server (needed so friends can join)..."
        $null = Add-FirewallRule
        if (Test-FirewallRule) {
            Say "Firewall is open for the server."
            Write-Log "Firewall rule added automatically"
        } else {
            Set-Content -LiteralPath $fwDeclined -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            Write-Log "Firewall rule declined - marker written (fix via Fix Problems later)"
        }
    }

    if ($script:St.StopRequested) { $script:St.SessionEnded = (Get-Date).ToString('o'); return }

    $ipLockedBefore = $false
    if (Test-StaticIpLocked) {
        Say "Locking your IP for the session (Settings: 'Lock my IP while hosting' is ON)..."
        $ipLockedBefore = Set-StaticLanIp
    }

    Say "Starting your server..."
    $startTime = Get-Date
    $server = Start-Process -FilePath ($script:ServerDir + 'BeamMP-Server.exe') -WorkingDirectory $script:RootDir -WindowStyle Minimized -PassThru
    Write-Log "Server process started (PID $($server.Id), working dir $script:RootDir)"

    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        if ($server.HasExited) { break }
        if ($script:St.StopRequested) { break }
        if (Get-NetTCPConnection -LocalPort $serverPort -State Listen -ErrorAction SilentlyContinue) { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        Say "Your server did not start. Let me check why..."
        Write-Log "Server failed to listen (PID $($server.Id))"
        Say (Get-ServerDiag)
        if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
        $script:St.SessionEnded = (Get-Date).ToString('o')
        return
    }
    Write-Log "Server is live (PID $($server.Id))"

    $upnpOk = $false
    Say "Opening port $serverPort (TCP+UDP) on your router via UPnP..."
    $upnpOk = Add-UpnpPortForward $serverPort
    if ($upnpOk) {
        Say "UPnP: port $serverPort forwarded automatically."
        Write-Log "UPnP port-forward OK (port $serverPort)"
    } else {
        Say "UPnP: not available (router setting off, or unsupported)."
        Say "You must forward port $serverPort (TCP+UDP) manually, or use a VPN."
        Write-Log "UPnP port-forward unavailable (port $serverPort)"
    }

    if (-not (Test-Loopback $serverPort)) {
        Say "Warning: I could not reach 127.0.0.1:$serverPort. If friends can't connect, use Fix Problems (firewall) or check your antivirus."
        Write-Log "Loopback check failed (diagnostic only - config left untouched)"
    }

    $watchdogCmd = '$seen=$false; $t0=[datetime]::Now; while($true){ $running=[bool](Get-Process -Name BeamMP-Launcher -ErrorAction SilentlyContinue); if($running){$seen=$true}; if($seen -and -not $running){Stop-Process -Id ' + $server.Id + ' -Force -ErrorAction SilentlyContinue; break}; if(-not (Get-Process -Id ' + $server.Id + ' -ErrorAction SilentlyContinue)){break}; if(-not $seen -and ([datetime]::Now-$t0).TotalMinutes -gt 60){break}; Start-Sleep -Seconds 2 }'
    Start-Process powershell -WindowStyle Hidden -ArgumentList ('-NoProfile -Command "' + $watchdogCmd + '"') | Out-Null

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
    } -ArgumentList $script:ServerDir, $script:RootDir, $server.Id

    Send-Webhook 'K BNG M Hoster [ONLINE]' 'Server is now live.' 3066993

    $conn = Get-ConnectionInfo
    $vpnDoc = ''
    $vpnWithIp = @($conn.Vpn | Where-Object { $_.Ip })
    if ($vpnWithIp.Count) {
        foreach ($v in $vpnWithIp) { $vpnDoc += "   Direct Connect, IP: $($v.Ip)   Port: $($conn.Port)  (friends must be on the SAME $($v.Name) network)" + [Environment]::NewLine }
    } else {
        $vpnDoc = '   Install the same VPN as you (Radmin VPN / Hamachi / ZeroTier / Tailscale), join your network, then Direct Connect with the host VPN IP shown on the Stats page.'
    }
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

2.5) FRIENDS VIA VPN:
   $vpnDoc

3) FRIENDS ANYWHERE (internet):
   IP: $(if ($conn.Public) { "$($conn.Public)   Port: $($conn.Port)" } else { '(public IP not detected)' })

   Router port forwarding status: $(if ($upnpOk) { 'OPENED AUTOMATICALLY via UPnP - friends can join' } elseif ($conn.Cgnat) { 'CANNOT WORK - your ISP uses CGNAT. Use a VPN (Radmin/Hamachi/ZeroTier/Tailscale) or ask the ISP for a public IP.' } else { 'NOT OPENED - forward port ' + $conn.Port + ' (TCP+UDP) in your router, or use a VPN' })
   $(if ($conn.Cgnat) { "WARNING: your ISP uses CGNAT ($($conn.Public)) - public port forwarding can never work. Use a VPN or a VPS." })

IMPORTANT: Do NOT click your own server in the BeamMP server list.
It uses your public IP, which fails from inside your own network.
Always use Direct Connect with the correct address above.
"@
    Set-Content -LiteralPath ($script:ServerDir + 'CONNECTING.txt') -Value $connectDoc

    Speak 'K BNG M Hoster is online.'
    $script:St.Running = $true
    $script:St.Port = $serverPort
    $script:St.UpnpOk = $upnpOk
    $script:St.ServerName = $serverName
    $script:St.Conn = $conn
    Say "================================================================="
    Say "YOUR SERVER IS LIVE - $serverName (port $serverPort)"
    Say "Start BeamNG through the BeamMP Launcher that just opened."
    Say "In BeamNG: More... -> BeamMP -> Direct Connect, IP: 127.0.0.1 Port: $serverPort"
    if ($conn.LAN) { Say "Friends on the same WiFi join via: $($conn.LAN):$($conn.Port)" }
    foreach ($v in $vpnWithIp) { Say "Friends via $($v.Name): $($v.Ip):$($conn.Port) (same VPN as you)" }
    if ($conn.Tailscale) { Say "Friends via Tailscale: $($conn.Tailscale):$($conn.Port)" }
    if ($conn.Public) { Say "Anyone on the internet: $($conn.Public):$($conn.Port) $(if ($upnpOk) { '(UPnP open)' } elseif ($conn.Cgnat) { '(CGNAT - forwarding impossible, use a VPN)' } else { '(forward manually)' })" }
    Say "Copy the line for your friends with the Copy IP button. Do NOT click your own server in the list - always Direct Connect."
    Say "Press Stop (or close the launcher) to shut the server down. Closing this app also stops it."
    Start-Process -FilePath $script:LauncherPath -WorkingDirectory (Split-Path $script:LauncherPath) | Out-Null

    while (Get-Process -Name 'BeamMP-Launcher' -ErrorAction SilentlyContinue) {
        if ($script:St.StopRequested) { break }
        Start-Sleep -Seconds 2
    }

    Say "Game session ended. Stopping your server..."
    Write-Log "Session ended"
    Stop-Job $trackerJob -ErrorAction SilentlyContinue
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
    Write-Log "Server stopped"
    $lines = @(Get-Content -LiteralPath $cfgPath) | ForEach-Object {
        if ($_ -match '^\s*AuthKey\s*=') { 'AuthKey = ""' } else { $_ }
    }
    Set-Content -LiteralPath $cfgPath -Value $lines -Encoding UTF8
    Write-Log "AuthKey removed from ServerConfig.toml (re-injected on next start)"
    if (Test-StaticIpLocked) {
        Say "Releasing the IP lock for this session..."
        if (Restore-DhcpLanIp) {
            Say "IP lock released - your network is back to normal."
        } else {
            Say "WARNING: could not restore DHCP. Run the tool again later - it retries automatically."
        }
    }
    $rootLog = $script:RootDir + 'Server.log'
    if (Test-Path -LiteralPath $rootLog) {
        Move-Item -LiteralPath $rootLog -Destination ($script:ServerDir + 'Server.log') -Force -ErrorAction SilentlyContinue
    }
    $uptimeMin = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
    Say "Your server ran for $uptimeMin minute(s). Thanks for using K BNG M Hoster!"
    Send-Webhook 'K BNG M Hoster [OFFLINE]' 'Server is now offline.' 15158332
    Speak 'Session closed.'
    $script:St.Running = $false
    $script:St.LastUptime = $uptimeMin
    $script:St.SessionEnded = (Get-Date).ToString('o')
}

# Self-initialize so every context (dot-sourced, runspace, direct run) gets correct paths.
Initialize-HosterPaths
