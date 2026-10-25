# Compiles K-BNG-M-Hoster.exe with embedded application icon and version metadata
$ErrorActionPreference = 'Stop'

$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) {
    throw "C# compiler not found at $csc"
}

$source = Join-Path $PSScriptRoot 'Launcher.cs'
$output = Join-Path $PSScriptRoot 'K-BNG-M-Hoster.exe'
$icon   = Join-Path $PSScriptRoot 'app.ico'

Write-Host "Compiling K-BNG-M-Hoster.exe..." -ForegroundColor Cyan

$args = @(
    '/target:winexe',
    "/out:$output",
    "/win32icon:$icon",
    '/optimize+',
    '/platform:anycpu',
    '/r:System.dll',
    '/r:System.Windows.Forms.dll',
    $source
)

$proc = Start-Process -FilePath $csc -ArgumentList $args -NoNewWindow -Wait -PassThru

if ($proc.ExitCode -eq 0) {
    Write-Host "BUILD SUCCESSFUL: $output is ready!" -ForegroundColor Green
} else {
    throw "Build failed with exit code $($proc.ExitCode)"
}
