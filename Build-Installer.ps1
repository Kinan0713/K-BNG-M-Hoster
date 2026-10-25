# =======================================================================================
# Build-Installer.ps1
# Automates the creation of K-BNG-M-Hoster-Setup.exe (Standalone Windows Installer)
# =======================================================================================
$ErrorActionPreference = 'Stop'

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "BUILDING K-BNG-M-HOSTER STANDALONE INSTALLER" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) {
    throw "C# compiler not found at $csc"
}

$root = $PSScriptRoot
$pkgDir = Join-Path $root 'Packaging'
$stagingDir = Join-Path $pkgDir 'staging'
$payloadZip = Join-Path $pkgDir 'payload.zip'
$installerExe = Join-Path $root 'K-BNG-M-Hoster-Setup.exe'
$iconPath = Join-Path $root 'app.ico'

# 1. Compile Launcher executable if needed
Write-Host "`n[1/5] Compiling Launcher (K-BNG-M-Hoster.exe)..." -ForegroundColor Yellow
& (Join-Path $root 'Build-Launcher.ps1')

# 2. Compile Uninstaller (Uninstall.exe)
Write-Host "`n[2/5] Compiling Uninstaller (Uninstall.exe)..." -ForegroundColor Yellow
$uninstallerSource = Join-Path $pkgDir 'Uninstaller.cs'
$uninstallerOut = Join-Path $pkgDir 'Uninstall.exe'

$uninstArgs = @(
    '/target:winexe',
    "/out:$uninstallerOut",
    "/win32icon:$iconPath",
    '/optimize+',
    '/platform:anycpu',
    '/r:System.dll',
    '/r:System.Drawing.dll',
    '/r:System.Windows.Forms.dll',
    $uninstallerSource
)

$proc = Start-Process -FilePath $csc -ArgumentList $uninstArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    throw "Uninstaller compilation failed with exit code $($proc.ExitCode)"
}
Write-Host "  -> Uninstall.exe compiled successfully." -ForegroundColor Green

# 3. Stage clean production files
Write-Host "`n[3/5] Staging application files for installation payload..." -ForegroundColor Yellow
if (Test-Path -LiteralPath $stagingDir) {
    Remove-Item -Path $stagingDir -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

# Copy root binaries and assets
Copy-Item -Path (Join-Path $root 'K-BNG-M-Hoster.exe') -Destination $stagingDir -Force
Copy-Item -Path $iconPath -Destination $stagingDir -Force
Copy-Item -Path $uninstallerOut -Destination $stagingDir -Force
if (Test-Path -LiteralPath (Join-Path $root 'LICENSE')) { Copy-Item -Path (Join-Path $root 'LICENSE') -Destination $stagingDir -Force }
if (Test-Path -LiteralPath (Join-Path $root 'README.md')) { Copy-Item -Path (Join-Path $root 'README.md') -Destination $stagingDir -Force }

# Copy Server directory (excluding private .env and runtime logs/backups)
$stagingServer = Join-Path $stagingDir 'Server'
New-Item -ItemType Directory -Path $stagingServer -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingServer 'bin') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingServer 'Logs') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingServer 'Backups') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stagingServer 'Resources\Client') -Force | Out-Null

$serverFiles = @(
    'BeamMP-Server.exe',
    'HosterCore.ps1',
    'Play_BeamMP.ps1',
    'Play_BeamMP.bat',
    'ServerConfig.toml',
    'app.ico',
    '.env.example',
    'webhook.example.txt',
    'README.txt'
)

foreach ($sf in $serverFiles) {
    $srcFile = Join-Path $root "Server\$sf"
    if (Test-Path -LiteralPath $srcFile) {
        Copy-Item -Path $srcFile -Destination (Join-Path $stagingServer $sf) -Force
    }
}

$modsJson = Join-Path $root 'Server\Resources\Client\mods.json'
if (Test-Path -LiteralPath $modsJson) {
    Copy-Item -Path $modsJson -Destination (Join-Path $stagingServer 'Resources\Client\mods.json') -Force
}

# 4. Create compressed payload
Write-Host "`n[4/5] Compressing payload archive (payload.zip)..." -ForegroundColor Yellow
if (Test-Path -LiteralPath $payloadZip) {
    Remove-Item -Path $payloadZip -Force
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $payloadZip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
$zipSizeMb = [math]::Round(((Get-Item $payloadZip).Length / 1MB), 2)
Write-Host "  -> Payload compressed: $zipSizeMb MB" -ForegroundColor Green

# 5. Compile Installer with embedded payload
Write-Host "`n[5/5] Compiling K-BNG-M-Hoster-Setup.exe..." -ForegroundColor Yellow
$installerSource = Join-Path $pkgDir 'Installer.cs'

$installerArgs = @(
    '/target:winexe',
    "/out:$installerExe",
    "/win32icon:$iconPath",
    "/resource:$payloadZip,payload.zip",
    "/resource:$iconPath,app.ico",
    '/optimize+',
    '/platform:anycpu',
    '/r:System.dll',
    '/r:System.Drawing.dll',
    '/r:System.Windows.Forms.dll',
    '/r:System.IO.Compression.dll',
    '/r:System.IO.Compression.FileSystem.dll',
    $installerSource
)

$proc = Start-Process -FilePath $csc -ArgumentList $installerArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    throw "Installer compilation failed with exit code $($proc.ExitCode)"
}

# Cleanup staging files
Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $payloadZip -Force -ErrorAction SilentlyContinue
Remove-Item -Path $uninstallerOut -Force -ErrorAction SilentlyContinue

$finalSizeMb = [math]::Round(((Get-Item $installerExe).Length / 1MB), 2)
Write-Host "`n=================================================" -ForegroundColor Green
Write-Host "INSTALLER BUILD SUCCESSFUL!" -ForegroundColor Green
Write-Host "Output: $installerExe" -ForegroundColor Green
Write-Host "Size:   $finalSizeMb MB" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green
