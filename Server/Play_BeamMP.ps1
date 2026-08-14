# ========================================================================================
# K BNG M Hoster v0.6.2 - Simplest Edition (GUI)
# All logic lives in HosterCore.ps1 (single source of truth). This file is the window.
# Start_Here.bat / Play_BeamMP.bat only launch this file.
#
# Mouse: click anything. Keyboard: Tab between controls, Enter activates, Esc closes,
# Alt+underlined letter on every button, and Ctrl+letter shortcuts (see the status bar).
# ========================================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Mode = '',
    [switch]$Mods,
    [switch]$Help,
    [switch]$Setup,
    [switch]$Fix
)

if ($Mode -eq 'mods') { $Mods = $true }
elseif ($Mode -eq 'fix') { $Fix = $true }
elseif ($Mode -eq 'help') { $Help = $true }
elseif ($Mode -eq 'setup') { $Setup = $true }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32R {
    [DllImport("user32.dll")] public static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
}
"@
} catch { }
[System.Windows.Forms.Application]::EnableVisualStyles()

$ErrorActionPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'HosterCore.ps1')
Initialize-HosterPaths

# Top-level app folder (the one holding Start_Here.bat) - used by "Open Folder".
$script:AppDir = $script:RootDir
if ((Split-Path -Leaf $script:RootDir.TrimEnd('\')) -eq 'Server') {
    $script:AppDir = (Split-Path -Parent $script:RootDir.TrimEnd('\')).TrimEnd('\') + '\'
}

if (-not (Test-Path -LiteralPath ($script:ServerDir + 'BeamMP-Server.exe')) -or -not (Test-Path -LiteralPath ($script:RootDir + 'ServerConfig.toml'))) {
    [System.Windows.Forms.MessageBox]::Show(
        "I could not find the server files (BeamMP-Server.exe / ServerConfig.toml).`nMake sure you run this from inside the K BNG M Hoster folder.",
        'K BNG M Hoster', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}

# ---------------------------------------------------------------------------------------
# SHARED STATE (queue + state are passed into every background runspace)
# ---------------------------------------------------------------------------------------
$script:Queue = New-Object System.Collections.Concurrent.ConcurrentQueue[string]
$script:State = @{
    Running      = $false
    Port         = 0
    UpnpOk       = $false
    ServerName   = ''
    Cgnat        = $false
    Conn         = $null
    StopRequested  = $false
    SessionEnded   = $null
    LastUptime     = ''
    Pre           = $null
    Diag          = ''
    FixReport     = $null
    UpdateMsg     = ''
}
$script:CorePath = Join-Path $PSScriptRoot 'HosterCore.ps1'
$script:CoreText = "`$script:CorePath = '" + ($script:CorePath -replace "'", "''") + "'`r`n" + (Get-Content -LiteralPath $script:CorePath -Raw)
$script:PendingAction = $null
$script:Busy = $false
$script:SessionPs = $null
$script:SessionHandle = $null
$script:LastSessionEnded = $null
$script:LastRunning = $false
$script:AllowClose = $false
$script:ClosingAfterStop = $false
$script:Starting = $false

# ---------------------------------------------------------------------------------------
# COLORS / HELPERS
# ---------------------------------------------------------------------------------------
$C = @{
    bg      = [System.Drawing.Color]::FromArgb(30, 30, 30)
    panel   = [System.Drawing.Color]::FromArgb(37, 37, 40)
    border  = [System.Drawing.Color]::FromArgb(63, 63, 70)
    text    = [System.Drawing.Color]::FromArgb(240, 240, 240)
    dim     = [System.Drawing.Color]::FromArgb(157, 165, 180)
    green   = [System.Drawing.Color]::FromArgb(63, 185, 80)
    red     = [System.Drawing.Color]::FromArgb(248, 81, 73)
    yellow  = [System.Drawing.Color]::FromArgb(210, 153, 34)
    blue    = [System.Drawing.Color]::FromArgb(88, 166, 255)
    btn     = [System.Drawing.Color]::FromArgb(45, 45, 48)
    btnHov  = [System.Drawing.Color]::FromArgb(62, 62, 66)
    log     = [System.Drawing.Color]::FromArgb(20, 20, 20)
}

function New-Btn([string]$Text, [string]$Tip, [scriptblock]$OnClick) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderColor = $C.border
    $b.FlatAppearance.MouseOverBackColor = $C.btnHov
    $b.BackColor = $C.btn
    $b.ForeColor = $C.text
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $b.AutoSize = $false
    $b.Height = 34
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Add_SizeChanged({ Set-Round $this 7 })
    $b.Add_HandleCreated({ Set-Round $this 7 })
    if ($Tip) { $script:Tip.SetToolTip($b, $Tip) }
    if ($OnClick) { $b.Add_Click($OnClick) }
    return $b
}

function New-Lbl([string]$Text, [System.Drawing.Color]$Color, [float]$Size = 9.5, [int]$Height = 20, [bool]$Bold = $false, [int]$Width = 0) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.ForeColor = $Color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.Font = New-Object System.Drawing.Font('Segoe UI', $Size, $(if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }))
    if ($Width) { $l.AutoSize = $false; $l.Width = $Width } else { $l.AutoSize = $true }
    $l.Height = $Height
    return $l
}

# ---------------------------------------------------------------------------------------
# RESPONSIVE LAYOUT HELPERS (design size 1000x720, everything scales with the window)
# ---------------------------------------------------------------------------------------
$script:DW = 1000
$script:DH = 720

function SX([double]$V) {
    return [int][math]::Round($V * $script:Form.ClientSize.Width / $script:DW)
}
function SY([double]$V) {
    return [int][math]::Round($V * $script:Form.ClientSize.Height / $script:DH)
}

# Rounded corners (works with the dark theme; re-apply after any size change).
function Set-Round($Ctrl, [int]$Radius) {
    if (-not $Ctrl -or $Ctrl.Width -le 0 -or $Ctrl.Height -le 0) { return }
    $max = [int]([math]::Min($Ctrl.Width, $Ctrl.Height) / 2)
    if ($Radius -gt $max) { $Radius = $max }
    if ($Radius -lt 1) { $Radius = 1 }
    try {
        $d = $Radius * 2
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        $p.AddArc(0, 0, $d, $d, 180, 90)
        $p.AddArc($Ctrl.Width - $d, 0, $d, $d, 270, 90)
        $p.AddArc($Ctrl.Width - $d, $Ctrl.Height - $d, $d, $d, 0, 90)
        $p.AddArc(0, $Ctrl.Height - $d, $d, $d, 90, 90)
        $p.CloseFigure()
        $Ctrl.Region = New-Object System.Drawing.Region($p)
        $p.Dispose()
        if ($Ctrl.IsHandleCreated) {
            $g = $Ctrl.CreateGraphics()
            try {
                $hr = $Ctrl.Region.GetHrgn($g)
                [Win32R]::SetWindowRgn($Ctrl.Handle, $hr, $true)
            } finally { $g.Dispose() }
        }
    } catch { Write-Log "SR-ERR Set-Round $($_.Exception.Message)" }
}

# How many lines does $Text need inside $MaxWidth with $Font?
function Measure-Text([string]$Text, [System.Drawing.Font]$Font, [int]$MaxWidth) {
    $g = $script:Form.CreateGraphics()
    try {
        $s = $g.MeasureString($Text, $Font, $MaxWidth)
        return [pscustomobject]@{
            Lines  = [int][math]::Max(1, [math]::Ceiling($s.Height / [math]::Max(1, $Font.Height)))
            Height = [int][math]::Ceiling($s.Height)
        }
    } finally { $g.Dispose() }
}

function Add-Log([string]$Line) {
    if (-not $Line -or -not $script:LogBox) { return }
    $script:LogBox.SuspendLayout()
    try {
        $script:LogBox.AppendText($Line + [Environment]::NewLine)
        while ($script:LogBox.Lines.Count -gt 500) {
            $idx = $script:LogBox.Text.IndexOf([Environment]::NewLine) + 2
            if ($idx -gt 0) { $script:LogBox.Text = $script:LogBox.Text.Substring($idx) }
            else { break }
        }
        $script:LogBox.SelectionStart = $script:LogBox.TextLength
        $script:LogBox.ScrollToCaret()
    } finally {
        $script:LogBox.ResumeLayout()
    }
}

# Runs a short core action in a fresh background runspace (UI never freezes).
function Start-CoreAction {
    param([string]$Script, [string]$Tag = 'action')
    if ($script:Busy) { Add-Log "[INFO] Another task is running - wait a moment."; return }
    $ps = [powershell]::Create()
    $null = $ps.AddScript($script:CoreText)
    $null = $ps.AddScript($Script).AddArgument($script:Queue).AddArgument($script:State)
    $handle = $ps.BeginInvoke()
    $script:Busy = $true
    $script:PendingAction = @{ Ps = $ps; Handle = $handle; Tag = $Tag }
    Update-BusyUi
}

function QStr([string]$Value) {
    return "'" + ($Value -replace "'", "''") + "'"
}

function Update-BusyUi {
    $busy = $script:Busy -or $script:Starting
    foreach ($b in @($script:BtnFix, $script:BtnVpn, $script:BtnMods, $script:BtnSettings, $script:BtnClean)) {
        if ($b) { $b.Enabled = -not $busy }
    }
}

# ---------------------------------------------------------------------------------------
# MAIN FORM
# ---------------------------------------------------------------------------------------
$script:Form = New-Object System.Windows.Forms.Form
$script:Form.Text = 'K BNG M Hoster v0.6.2 - by Kinan (@raed713)'
$script:Form.Size = New-Object System.Drawing.Size(1000, 720)
$script:Form.MinimumSize = New-Object System.Drawing.Size(960, 660)
$script:Form.StartPosition = 'CenterScreen'
$script:Form.BackColor = $C.bg
$script:Form.ForeColor = $C.text
$script:Form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
$script:Form.KeyPreview = $true
$script:Tip = New-Object System.Windows.Forms.ToolTip
$script:Tip.InitialDelay = 350
$script:Tip.ReshowDelay = 80
$script:Tip.AutoPopDelay = 12000

# ---------------- Header ----------------
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 62
$header.BackColor = $C.panel
$title = New-Lbl 'K BNG M Hoster' ([System.Drawing.Color]::White) 19 30 $true
$title.Location = New-Object System.Drawing.Point(14, 6)
$subtitle = New-Lbl 'v0.6.2  |  Update 6 - Fix 2  |  Sole Creator: Kinan  |  Discord: @raed713' $C.dim 9 18
$subtitle.Location = New-Object System.Drawing.Point(15, 38)
$header.Controls.Add($title)
$header.Controls.Add($subtitle)

# ---------------- Toolbar ----------------
$toolbar = New-Object System.Windows.Forms.Panel
$toolbar.Dock = 'Top'
$toolbar.Height = 52
$toolbar.BackColor = $C.bg
$toolbar.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 4)

$script:BtnStart = New-Btn '&Start Server' 'Start the BeamMP server and open the launcher. Friends join via the addresses shown on the dashboard. (Ctrl+S)' { Start-ServerFlow }
$script:BtnStart.BackColor = [System.Drawing.Color]::FromArgb(35, 100, 60)
$script:BtnStart.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(63, 185, 80)
$script:BtnStart.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Bold)

$script:BtnStop = New-Btn 'Sto&p' 'Stop the running server. Closing the launcher window also stops it. (Ctrl+X)' { Stop-ServerFlow }
$script:BtnStop.Enabled = $false

$script:BtnFix = New-Btn '&Fix Problems' 'Scan your setup and repair common issues (key, port, firewall, CGNAT, VPN). (Ctrl+F)' { Show-FixPage }

$script:BtnVpn = New-Btn '&VPN Manager' 'Radmin VPN / Hamachi / ZeroTier / Tailscale: start or download them, see their IPs. Needed when port forwarding can''t work (CGNAT). (Ctrl+V)' { Show-VpnPage }

$script:BtnMods = New-Btn '&Mods' 'Manage your mods (Resources\Client): enable, disable, scan for suspicious files. (Ctrl+M)' { Show-ModsPage }

$script:BtnSettings = New-Btn 'Se&ttings' 'Server name, max players, port, IP lock, server key. (Ctrl+T)' { Show-SettingsPage }

$script:BtnClean = New-Btn 'C&lean Info' 'Remove personal/runtime files (key, logs, webhook, IP files) so the folder is safe to zip and share.' { Run-CleanFlow }
$script:BtnClean.BackColor = [System.Drawing.Color]::FromArgb(122, 26, 26)
$script:BtnClean.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(158, 34, 34)
$script:BtnClean.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(220, 60, 60)
$script:BtnClean.ForeColor = [System.Drawing.Color]::White

$btnOpen = New-Btn '&Open Folder' 'Open the K BNG M Hoster folder in Explorer.' { Start-Process explorer.exe -ArgumentList ('"' + $script:AppDir + '"') }

$script:BtnGuide = New-Btn '&Guide' 'How everything works, step by step - the whole README inside the app. (Ctrl+G)' { Show-GuidePage }

# Design-time geometry for every chrome control (scaled on every resize).
$script:ChromeSpecs = @(
    @{ Btn = $script:BtnStart;    X = 10;  Y = 6; W = 120; H = 38 },
    @{ Btn = $script:BtnStop;     X = 136; Y = 6; W = 74;  H = 38 },
    @{ Btn = $script:BtnFix;      X = 216; Y = 6; W = 104; H = 38 },
    @{ Btn = $script:BtnVpn;      X = 326; Y = 6; W = 108; H = 38 },
    @{ Btn = $script:BtnMods;     X = 440; Y = 6; W = 66;  H = 38 },
    @{ Btn = $script:BtnSettings; X = 512; Y = 6; W = 88;  H = 38 },
    @{ Btn = $script:BtnClean;    X = 606; Y = 6; W = 94;  H = 38 },
    @{ Btn = $btnOpen;            X = 706; Y = 6; W = 98;  H = 38 },
    @{ Btn = $script:BtnGuide;    X = 810; Y = 6; W = 82;  H = 38 }
)
$script:ChromeReady = $false

foreach ($b in @($script:BtnStart, $script:BtnStop, $script:BtnFix, $script:BtnVpn, $script:BtnMods, $script:BtnSettings, $script:BtnClean, $btnOpen, $script:BtnGuide)) { $toolbar.Controls.Add($b) }

# Re-layout the fixed chrome (header / toolbar / status bar / log panel) to the window size.
function Layout-Chrome {
    if (-not $script:ChromeReady -or -not $script:Form) { return }
    try {
        $w = $script:Form.ClientSize.Width
        $c = $script:Chrome
        $c.Header.Height = SY(62)
        Set-Round $c.Header 10
        $c.Toolbar.Height = SY(52)
        $c.StatusBar.Height = SY(26)
        Set-Round $c.StatusBar 10
        $c.LogPanel.Height = SY(190)
        Set-Round $c.LogPanel 10
        foreach ($s in $script:ChromeSpecs) {
            $bx = SX $s.X; $by = SY $s.Y; $bw = SX $s.W; $bh = SY $s.H
            $s.Btn.Location = New-Object System.Drawing.Point($bx, $by)
            $s.Btn.Size = New-Object System.Drawing.Size($bw, $bh)
            Set-Round $s.Btn 7
        }
        $c.LblShortcuts.Width = $w - (SX 430)
        $c.LblPlayers.Width = SX 390
        $px = $w - (SX 400)
        $c.LblPlayers.Location = New-Object System.Drawing.Point($px, 3)
        $cx = $w - (SX 66)
        $c.BtnClearLog.Location = New-Object System.Drawing.Point($cx, 0)
    } catch { Write-Log "[LAYOUT-ERROR] CHROME $($_.Exception.Message)" }
}

# ---------------- Status bar ----------------
$statusBar = New-Object System.Windows.Forms.Panel
$statusBar.Dock = 'Bottom'
$statusBar.Height = 26
$statusBar.BackColor = $C.panel
$script:LblShortcuts = New-Lbl 'Ctrl+S Start  |  Ctrl+X Stop  |  Ctrl+F Fix  |  Ctrl+V VPN  |  Ctrl+M Mods  |  Ctrl+T Settings  |  Ctrl+G Guide  |  Ctrl+D Diagnose  |  Ctrl+C Copy IP  |  Tab next  |  Enter activate  |  Esc close' $C.dim 8 20
$script:LblShortcuts.AutoSize = $false
$script:LblShortcuts.Width = 940
$script:LblShortcuts.Location = New-Object System.Drawing.Point(10, 3)
$script:LblPlayers = New-Lbl '' $C.blue 8.5 20 $true 380
$script:LblPlayers.Location = New-Object System.Drawing.Point(580, 3)
$script:LblPlayers.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$statusBar.Controls.Add($script:LblShortcuts)
$statusBar.Controls.Add($script:LblPlayers)

# ---------------- Log panel ----------------
$logPanel = New-Object System.Windows.Forms.Panel
$logPanel.Dock = 'Bottom'
$logPanel.Height = 190
$logPanel.BackColor = $C.bg
$logTitle = New-Lbl 'Activity log  (everything the tool does, and why)' $C.dim 8.5 18
$logTitle.Location = New-Object System.Drawing.Point(12, 2)
$btnClearLog = New-Btn 'Clear' 'Clear the activity log (does not affect the server).' { $script:LogBox.Clear() }
$btnClearLog.Size = New-Object System.Drawing.Size(56, 24)
$btnClearLog.Location = New-Object System.Drawing.Point(920, 0)
$btnClearLog.Height = 24
$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.ReadOnly = $true
$script:LogBox.BackColor = $C.log
$script:LogBox.ForeColor = [System.Drawing.Color]::FromArgb(212, 212, 212)
$script:LogBox.BorderStyle = 'None'
$script:LogBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:LogBox.WordWrap = $false
$script:LogBox.ScrollBars = 'Vertical'
$logPanel.Add_Resize({
    $script:LogBox.Size = New-Object System.Drawing.Size(($logPanel.ClientSize.Width - 24), ($logPanel.ClientSize.Height - 30))
    $script:LogBox.Location = New-Object System.Drawing.Point(12, 26)
})
$logPanel.Controls.Add($btnClearLog)
$logPanel.Controls.Add($logTitle)
$logPanel.Controls.Add($script:LogBox)

$script:Chrome = @{ Header = $header; Toolbar = $toolbar; StatusBar = $statusBar; LogPanel = $logPanel; LblShortcuts = $script:LblShortcuts; LblPlayers = $script:LblPlayers; BtnClearLog = $btnClearLog }

# ---------------- Content area (added FIRST so the docked bars lay out around it) --------
$script:Content = New-Object System.Windows.Forms.Panel
$script:Content.Dock = 'Fill'
$script:Content.BackColor = $C.bg

$script:Form.Controls.Add($script:Content)
$script:Form.Controls.Add($statusBar)
$script:Form.Controls.Add($logPanel)
$script:Form.Controls.Add($toolbar)
$script:Form.Controls.Add($header)

$script:ChromeReady = $true
Layout-Chrome

# One resize handler drives the whole UI: chrome + the active page's layout.
$script:Form.Add_Resize({
    try {
        Set-Round $script:Form 12
        Layout-Chrome
        if ($script:PageLayout) { & $script:PageLayout }
    } catch { Write-Log "[LAYOUT-ERROR] $($_.Exception.Message)" }
})

# ---------------- Content pages ----------------
function Show-DashboardPage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $C.bg

    $script:ConnCard = New-Object System.Windows.Forms.Panel
    $script:ConnCard.Dock = 'Fill'
    $script:ConnCard.BackColor = $C.bg

    $connTitle = New-Lbl 'How your friends connect  (BeamNG -> More... -> BeamMP -> Direct Connect)' $C.blue 12 26 $true
    $connTitle.Location = New-Object System.Drawing.Point(16, 4)
    $script:ConnCard.Controls.Add($connTitle)

    $script:LblConnThis = New-Lbl '' ([System.Drawing.Color]::White) 10.5 22
    $script:LblConnThis.Location = New-Object System.Drawing.Point(16, 34)
    $script:LblConnLan = New-Lbl '' $C.dim 10 22
    $script:LblConnLan.Location = New-Object System.Drawing.Point(16, 58)
    $script:LblConnVpn = New-Lbl '' $C.green 10 22  $false 900
    $script:LblConnVpn.Location = New-Object System.Drawing.Point(16, 82)
    $script:LblConnTail = New-Lbl '' $C.blue 10 22
    $script:LblConnTail.Location = New-Object System.Drawing.Point(16, 106)
    $script:LblConnPub = New-Lbl '' $C.dim 10 22
    $script:LblConnPub.Location = New-Object System.Drawing.Point(16, 130)
    $script:LblConnRouter = New-Lbl '' $C.dim 10 22  $false 900
    $script:LblConnRouter.Location = New-Object System.Drawing.Point(16, 154)
    $script:LblConnNote = New-Lbl '' $C.yellow 9 42  $false 900
    $script:LblConnNote.Location = New-Object System.Drawing.Point(16, 178)

    $script:BtnDiag = New-Btn '&Diagnose' 'Run a full live diagnosis and show a plain-language report of any problem. (Ctrl+D)' { Run-Diagnose }
    $script:BtnDiag.Size = New-Object System.Drawing.Size(110, 36)

    $script:BtnCopy = New-Btn '&Copy IP' 'Copy the best address for your friends to the clipboard (LAN > VPN > Tailscale > internet). (Ctrl+C)' { Copy-ConnectionLine }
    $script:BtnCopy.Size = New-Object System.Drawing.Size(110, 36)

    foreach ($l in @($script:LblConnThis, $script:LblConnLan, $script:LblConnVpn, $script:LblConnTail, $script:LblConnPub, $script:LblConnRouter, $script:LblConnNote, $script:BtnDiag, $script:BtnCopy)) { $script:ConnCard.Controls.Add($l) }

    $script:StatusCard = New-Object System.Windows.Forms.Panel
    $script:StatusCard.Dock = 'Top'
    $script:StatusCard.Height = 104
    $script:StatusCard.BackColor = $C.panel

    $script:LblStatusBig = New-Lbl 'SERVER STOPPED' $C.red 20 34 $true
    $script:LblStatusBig.Location = New-Object System.Drawing.Point(16, 10)
    $script:LblStatusBig.Font = New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)

    $script:LblServerMeta = New-Lbl '' $C.dim 9.5 20  $false 500
    $script:LblServerMeta.Location = New-Object System.Drawing.Point(16, 54)

    $script:LblCgnatBadge = New-Lbl '' $C.yellow 10 20 $true
    $script:LblCgnatBadge.Location = New-Object System.Drawing.Point(16, 78)
    $script:LblCgnatBadge.Height = 0

    $script:LblStatusHint = New-Lbl 'Press Start Server (or Ctrl+S). Everything is automatic: key check, safety scan, firewall, port, then it opens the BeamMP Launcher.' $C.dim 9.5 40  $false 620
    $script:LblStatusHint.Location = New-Object System.Drawing.Point(320, 14)

    $script:StatusCard.Controls.Add($script:LblStatusHint)
    $script:StatusCard.Controls.Add($script:LblCgnatBadge)
    $script:StatusCard.Controls.Add($script:LblServerMeta)
    $script:StatusCard.Controls.Add($script:LblStatusBig)

    $p.Controls.Add($script:ConnCard)
    $p.Controls.Add($script:StatusCard)
    $script:Content.Controls.Add($p)
    $script:PageLayout = { Layout-Dashboard }
    Refresh-Dashboard
}

function Layout-Dashboard {
    if (-not $script:ConnCard) { return }
    try {
        $cw = $script:ConnCard.ClientSize.Width - 32
        $labels = @($script:LblConnThis, $script:LblConnLan, $script:LblConnVpn, $script:LblConnTail, $script:LblConnPub, $script:LblConnRouter)
        $y = SY(34)
        for ($i = 0; $i -lt $labels.Count; $i++) {
            $labels[$i].AutoSize = $false
            $labels[$i].Width = $cw
            $m = Measure-Text $labels[$i].Text $labels[$i].Font $cw
            $lh = [int][math]::Max(22, $m.Lines * 24 + 4)
            $labels[$i].Height = $lh
            $labels[$i].Location = New-Object System.Drawing.Point(16, $y)
            $y += $lh
        }
        $script:LblConnNote.AutoSize = $false
        $script:LblConnNote.Width = $cw
        $m = Measure-Text $script:LblConnNote.Text $script:LblConnNote.Font $cw
        $noteH = [int]($m.Lines * 24 + 6)
        $script:LblConnNote.Height = $noteH
        $script:LblConnNote.Location = New-Object System.Drawing.Point(16, $y)
        $btnY = ($y + $noteH + 12)
        $bx2 = SX 136
        $script:BtnDiag.Location = New-Object System.Drawing.Point(16, $btnY)
        $script:BtnCopy.Location = New-Object System.Drawing.Point($bx2, $btnY)
        $script:StatusCard.Height = SY(104)
        Set-Round $script:StatusCard 10
        $sw = $script:StatusCard.ClientSize.Width - 336
        $script:LblStatusHint.Width = $sw
        $hx = SX 320
        $hy = SY 14
        $hh = $script:StatusCard.ClientSize.Height - 28
        $script:LblStatusHint.Location = New-Object System.Drawing.Point($hx, $hy)
        $script:LblStatusHint.Height = $hh
    } catch { Write-Log "[LAYOUT-ERROR] DASHBOARD $($_.Exception.Message)" }
}

function Refresh-Dashboard {
    if (-not $script:LblStatusBig) { return }
    $conn = $script:State.Conn
    $running = $script:State.Running
    $port = if ($conn) { $conn.Port } else { (Get-ServerPort) }
    $name = if ($script:State.ServerName) { $script:State.ServerName } else { 'K BNG M Server' }

    $script:LblStatusBig.Text = if ($running) { 'SERVER IS LIVE' } else { 'SERVER STOPPED' }
    $script:LblStatusBig.ForeColor = if ($running) { $C.green } else { $C.red }
    $script:LblServerMeta.Text = "Server: $name   |   Port: $port   |   $(if ($running) { 'Running - press Stop or close the launcher to shut it down' } else { 'Not running' })"
    if ($running) {
        $script:LblStatusHint.Text = 'The server is live. Start BeamNG via the BeamMP Launcher, then Direct Connect with one of the addresses below. Closing this app stops the server.'
        $script:LblStatusHint.ForeColor = $C.green
    } else {
        $script:LblStatusHint.Text = 'Press Start Server (or Ctrl+S). Everything is automatic: key check, safety scan, firewall, port, then it opens the BeamMP Launcher.'
        $script:LblStatusHint.ForeColor = $C.dim
    }

    $cgnat = if ($conn) { $conn.Cgnat } else { $false }
    if ($cgnat) {
        $script:LblCgnatBadge.Height = 20
        $script:LblCgnatBadge.Text = '[CGNAT detected] Your ISP shares one public IP - port forwarding can never work. Friends must use a VPN (VPN Manager) or your ISP must give you a real public IP.'
    } else {
        $script:LblCgnatBadge.Height = 0
        $script:LblCgnatBadge.Text = ''
    }

    $script:LblConnThis.Text = "THIS PC (test it now):   127.0.0.1  :  $port"
    $script:LblConnLan.Text = if ($conn -and $conn.LAN) { "Friends (same WiFi):      $($conn.LAN)  :  $port" } else { 'Friends (same WiFi):     (LAN IP not detected)' }
    $vpnLines = @()
    if ($conn) { $vpnLines = @($conn.Vpn | Where-Object { $_.Ip }) }
    if ($vpnLines.Count) {
        $vpnText = (($vpnLines | ForEach-Object { "$($_.Name) -> $($_.Ip):$port" }) -join '   ')
        if ($vpnLines.Count -ge 2) { $vpnText += '   (friends must use the SAME VPN as the line you send)' }
        $script:LblConnVpn.Text = "Friends (VPN):             $vpnText"
    } else {
        $script:LblConnVpn.Text = 'Friends (VPN):             (none running - see VPN Manager)'
    }
    $script:LblConnTail.Text = if ($conn -and $conn.Tailscale) { "Friends (Tailscale):      $($conn.Tailscale)  :  $port" } else { 'Friends (Tailscale):      (not running)' }
    $script:LblConnPub.Text = if ($conn -and $conn.Public) { "Anyone (internet):        $($conn.Public)  :  $port" } else { 'Anyone (internet):        (public IP not detected)' }
    if ($running) {
        if ($script:State.UpnpOk) {
            $script:LblConnRouter.Text = "Router (UPnP):            port $port forwarded - internet players CAN connect."
            $script:LblConnRouter.ForeColor = $C.green
        } elseif ($cgnat) {
            $script:LblConnRouter.Text = "Router (UPnP):            CGNAT - forwarding impossible. Use a VPN (VPN Manager) or ask your ISP for a public IP."
            $script:LblConnRouter.ForeColor = $C.red
        } else {
            $script:LblConnRouter.Text = "Router (UPnP):            NOT forwarded - use Fix Problems or forward port $port (TCP+UDP) manually."
            $script:LblConnRouter.ForeColor = $C.yellow
        }
    } else {
        $script:LblConnRouter.Text = "Router (UPnP):            opens automatically when the server starts (start it to see the result)"
        $script:LblConnRouter.ForeColor = $C.dim
    }
    $badVpn = @()
    if ($conn) { $badVpn = @($conn.Vpn | Where-Object { -not $_.Ip }) }
    if ($badVpn.Count) {
        $script:LblConnNote.Text = "[NOTE] $($badVpn[0].Name) is running but has no VPN IP yet - click/join your network inside the VPN app, or start it from the VPN Manager.`nIMPORTANT: do NOT click your own server in the BeamMP server list - it uses your public IP and fails from inside your own network. Always use Direct Connect."
    } else {
        $script:LblConnNote.Text = "IMPORTANT: do NOT click your own server in the BeamMP server list - it uses your public IP and fails from inside your own network. Always use Direct Connect."
    }
    Layout-Dashboard
}

function Show-FixPage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $C.bg

    $script:FixRowsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $script:FixRowsPanel.Dock = 'Fill'
    $script:FixRowsPanel.FlowDirection = 'TopDown'
    $script:FixRowsPanel.WrapContents = $false
    $script:FixRowsPanel.AutoScroll = $true
    $script:FixRowsPanel.BackColor = $C.bg

    $script:FixTop = New-Object System.Windows.Forms.Panel
    $script:FixTop.Dock = 'Top'
    $script:FixTop.Height = 96
    $script:FixTop.BackColor = $C.bg

    $head = New-Lbl 'Help / Fix Problems' $C.blue 14 26 $true
    $head.Location = New-Object System.Drawing.Point(4, 2)
    $script:FixTop.Controls.Add($head)
    $sub = New-Lbl 'Every check is run for you. [OK] = fine, [X] = fix it (use the button on that row), [?] = needs your attention. Start the server first if you want the internet test to run.' $C.dim 9 20  $false 900
    $sub.Location = New-Object System.Drawing.Point(4, 30)
    $script:FixTop.Controls.Add($sub)

    $btnScan = New-Btn 'Re-&scan everything' 'Run every check again (key, launcher, port, firewall, CGNAT, internet reachability...).' { Run-FixScan }
    $btnScan.Size = New-Object System.Drawing.Size(160, 34)
    $btnScan.Location = New-Object System.Drawing.Point(4, 54)
    $script:FixTop.Controls.Add($btnScan)

    $btnUpnp = New-Btn 'Open port on router via UPnP' 'Ask the router to forward the server port (TCP+UDP) automatically - no admin needed.' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$port = Get-ServerPort`nif (Add-UpnpPortForward `$port) { Say ""UPnP: port `$port (TCP+UDP) forwarded on the router. Friends can now connect!"" } else { Say ""UPnP failed. Enable UPnP in your router settings, or forward port `$port (TCP+UDP) manually."" }" 'upnp' }
    $btnUpnp.Size = New-Object System.Drawing.Size(210, 34)
    $btnUpnp.Location = New-Object System.Drawing.Point(172, 54)
    $script:FixTop.Controls.Add($btnUpnp)

    $p.Controls.Add($script:FixRowsPanel)
    $p.Controls.Add($script:FixTop)
    $script:Content.Controls.Add($p)
    $script:FixRowRefs = @()
    $script:PageLayout = { Layout-FixRows }
    Run-FixScan
}

function Run-FixScan {
    $script:FixRowsPanel.Controls.Clear()
    $script:FixRowRefs = @()
    $wait = New-Lbl 'Scanning... (this takes a few seconds)' $C.dim 10 22
    $wait.Location = New-Object System.Drawing.Point(4, 4)
    $script:FixRowsPanel.Controls.Add($wait)
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.FixReport = @(Get-FixReport)" 'fixscan'
}

function Add-FixRow($row) {
    $rowPanel = New-Object System.Windows.Forms.Panel
    $rowPanel.Width = $script:FixRowsPanel.ClientSize.Width - 22
    $rowPanel.Height = 44
    $rowPanel.BackColor = $C.panel
    $rowPanel.Padding = New-Object System.Windows.Forms.Padding(8, 5, 8, 5)

    $status = if ($row.Ok) { '[OK]' } elseif ($row.NeedsAction) { '[X]' } else { '[?]' }
    $color = if ($row.Ok) { $C.green } elseif ($row.NeedsAction) { $C.red } else { $C.yellow }
    $lbl = New-Lbl $status $color 10 30 $true
    $lbl.Location = New-Object System.Drawing.Point(8, 7)
    $lbl.Width = 42
    $rowPanel.Controls.Add($lbl)

    $lbl2 = New-Lbl ("$($row.Label):  $($row.Detail)") ([System.Drawing.Color]::White) 9.5 30  $false 630
    $lbl2.Location = New-Object System.Drawing.Point(54, 7)
    $rowPanel.Controls.Add($lbl2)

    $btn = $null
    if ($row.Action) {
        $prefix = if ($row.NeedsAction) { 'Fix: ' } else { 'Info: ' }
        $btn = New-Btn ("&$prefix$($row.Action)") $row.Action { FixRowAction $row.Key }
        $btn.Size = New-Object System.Drawing.Size(250, 30)
        $btn.Location = New-Object System.Drawing.Point(690, 7)
        $btn.Height = 30
        $btn.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $rowPanel.Controls.Add($btn)
    }
    $script:FixRowRefs += @{ Row = $rowPanel; Lbl = $lbl2; Btn = $btn }
    $script:FixRowsPanel.Controls.Add($rowPanel)
}

function Layout-FixRows {
    if (-not $script:FixRowsPanel -or -not $script:FixRowRefs) { return }
    try {
        $w = $script:FixRowsPanel.ClientSize.Width - 22
        if ($script:FixTop) {
            $script:FixTop.Height = SY(96)
            foreach ($c in $script:FixTop.Controls) { if ($c -is [System.Windows.Forms.Label] -and $c.Width -gt 400) { $c.Width = $script:FixTop.ClientSize.Width - 8 } }
        }
        foreach ($r in $script:FixRowRefs) {
            $r.Row.Width = $w
            $lblW = [int][math]::Max(200, $w - 320)
            $r.Lbl.Width = $lblW
            $m = Measure-Text $r.Lbl.Text $r.Lbl.Font $lblW
            $lh = [int]($m.Lines * 20 + 12)
            $rh = [int][math]::Max(44, $lh + 10)
            $r.Row.Height = $rh
            $r.Lbl.Height = $lh
            $ly = [int](($rh - $lh) / 2)
            $r.Lbl.Location = New-Object System.Drawing.Point(54, $ly)
            if ($r.Btn) {
                $bxp = $w - 262
                $byp = [int](($rh - 30) / 2)
                $r.Btn.Location = New-Object System.Drawing.Point($bxp, $byp)
            }
            Set-Round $r.Row 10
        }
    } catch { Write-Log "[LAYOUT-ERROR] FIXROWS $($_.Exception.Message)" }
}

function FixRowAction([string]$Key) {
    switch ($Key) {
        'AUTHKEY' { Show-KeySetupDialog $script:Form }
        'LAUNCHER' { Start-Process 'https://beammp.com' }
        'PORT' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Set-FreePort -Port (Get-FreePort))" 'fixport' }
        'FW' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$null = Add-FirewallRule`nif (Test-FirewallRule) { Say ""Firewall rules verified."" } else { Say ""Firewall rules still missing - try again or check your antivirus."" }" 'fixfw' }
        'VC' { Start-Process 'https://aka.ms/vs/17/release/vc_redist.x64.exe' }
        'BEAMNG' { Start-Process 'https://www.beamng.com/game/' }
        'CGNAT' { Show-CgnatExplain }
        'EXT' { Show-ExtSteps }
        default { Add-Log "[INFO] Nothing to do for $Key." }
    }
}

function Show-CgnatExplain {
    $text = @"
What is CGNAT and why can't I port-forward?

Your ISP does not give your router its own public internet address.
Instead you share ONE public IP with many customers.

Since the public IP is shared, your router's port-forward rules are
ignored by the ISP's big NAT device - it does NOT forward your port.
Nothing in the router or this tool can change that.

Your options:
 A) Tailscale (FREE, recommended) - creates a direct encrypted tunnel
    that works through CGNAT. Friends install Tailscale too and join
    via your 100.x.x.x Tailscale IP. No router changes needed.
 B) Contact your ISP and ask for a real public IP (often free or a
    small monthly fee) - then port forwarding will work.
 C) Rent a cheap VPS and run the BeamMP server there instead.

Download Tailscale: https://tailscale.com
"@
    [System.Windows.Forms.MessageBox]::Show($text, 'What is CGNAT?', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Show-ExtSteps {
    $text = @"
Fixing a 'NOT reachable' external test result

The internet test can only pass while your server is LIVE.
Work through these in order:

1. Server running?  Start it and wait for 'SERVER IS LIVE',
   then Re-scan while it is live.

2. Router forward?  Log into your router admin page (address on the
   router's sticker) and check that BOTH TCP and UDP forward to your
   PC's LAN IP. Enable it if disabled.
   Or use the 'Open port on router via UPnP' button (no admin needed).

3. Windows Firewall?  Use the Fix button on the Firewall row to create
   the BeamMP ALLOW rules.

4. VPN running?  Radmin VPN / Hamachi / ZeroTier / Tailscale are
   supported - friends join via the VPN IP shown on the dashboard.

5. IP changed?  If your PC's LAN IP changed, the forward breaks.
   Enable 'Lock my IP while hosting' in Settings to prevent this.

Still stuck? Check your port manually on your phone:
https://checkbeammp.beammp.com
"@
    [System.Windows.Forms.MessageBox]::Show($text, 'NOT reachable - what to do', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Show-VpnPage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $C.bg

    $script:VpnRowsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $script:VpnRowsPanel.Dock = 'Fill'
    $script:VpnRowsPanel.FlowDirection = 'TopDown'
    $script:VpnRowsPanel.WrapContents = $false
    $script:VpnRowsPanel.AutoScroll = $true
    $script:VpnRowsPanel.BackColor = $C.bg

    $script:VpnTop = New-Object System.Windows.Forms.Panel
    $script:VpnTop.Dock = 'Top'
    $script:VpnTop.Height = 110
    $script:VpnTop.BackColor = $C.bg

    $head = New-Lbl 'VPN Manager  -  Radmin VPN / Hamachi / ZeroTier / Tailscale' $C.blue 14 26 $true
    $head.Location = New-Object System.Drawing.Point(4, 2)
    $script:VpnTop.Controls.Add($head)
    $safety = New-Lbl 'SAFETY: a VPN puts friends on a virtual LAN with your PC - they can reach file sharing / Remote Desktop etc. Only invite people you TRUST. Never invite random players into your VPN network.' $C.yellow 9 20  $false 940
    $safety.Location = New-Object System.Drawing.Point(4, 30)
    $script:VpnTop.Controls.Add($safety)
    $sub = New-Lbl 'Port forwarding (Fix Problems) is the #1 way to host for STRANGERS. These VPNs are the fallback for when forwarding can''t work (e.g. CGNAT ISPs).' $C.dim 9 20  $false 940
    $sub.Location = New-Object System.Drawing.Point(4, 52)
    $script:VpnTop.Controls.Add($sub)

    $btnRefresh = New-Btn '&Refresh' 'Re-check which VPNs are installed / running and their IPs.' { Show-VpnPage }
    $btnRefresh.Size = New-Object System.Drawing.Size(90, 32)
    $btnRefresh.Location = New-Object System.Drawing.Point(4, 76)
    $script:VpnTop.Controls.Add($btnRefresh)

    $btnAll = New-Btn '&Start all installed VPNs' 'Start every VPN that is installed on this PC.' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$started = 0`nforeach (`$app in Get-InstalledVpns | Where-Object { `$_.Installed -and `$_.Exe }) { `$r = Start-OrDownload-Vpn `$app 6; Say `$r; if (`$r -match 'connected') { `$started++ } }`nif (`$started -eq 0) { Say ""No VPN could be started. Install one first (see the rows below) and try again."" }`n`$State.VpnRefresh = (Get-Date).ToString('o')" 'vpns' }
    $btnAll.Size = New-Object System.Drawing.Size(150, 32)
    $btnAll.Location = New-Object System.Drawing.Point(100, 76)
    $script:VpnTop.Controls.Add($btnAll)

    $p.Controls.Add($script:VpnRowsPanel)
    $p.Controls.Add($script:VpnTop)
    $script:Content.Controls.Add($p)
    $script:PageLayout = { Layout-VpnRows }
    Refresh-VpnRows
    Layout-VpnRows
}

function Refresh-VpnRows {
    if (-not $script:VpnRowsPanel) { return }
    $script:VpnRowsPanel.Controls.Clear()
    $script:VpnRowRefs = @()
    $apps = @(Get-InstalledVpns)
    $running = @(Get-VpnIps)
    foreach ($app in $apps) {
        $run = @($running | Where-Object { $_.Key -eq $app.Key })
        $rowPanel = New-Object System.Windows.Forms.Panel
        $rowPanel.Width = $script:VpnRowsPanel.ClientSize.Width - 22
        $rowPanel.Height = 46
        $rowPanel.BackColor = $C.panel
        $rowPanel.Padding = New-Object System.Windows.Forms.Padding(8, 5, 8, 5)

        $state = ''
        $color = $C.dim
        if (-not $app.Installed) {
            $state = 'NOT installed'
            $color = $C.yellow
        } elseif ($run.Count -and $run[0].Ip) {
            $state = "RUNNING - IP $($run[0].Ip)"
            $color = $C.green
        } elseif ($run.Count) {
            $state = 'RUNNING - connecting (no VPN IP yet)'
            $color = $C.yellow
        } else {
            $state = 'installed, not running'
            $color = $C.dim
        }

        $lbl = New-Lbl "$($app.Name)   -   $state" $color 10.5 32 $true
        $lbl.Location = New-Object System.Drawing.Point(10, 7)
        $lbl.Width = 380
        $rowPanel.Controls.Add($lbl)

        $btn = $null
        if (-not $app.Installed) {
            $btn = New-Btn '&Download (official page)' "Open the official download page for $($app.Name)." { Start-Process $app.Url }
            $btn.Size = New-Object System.Drawing.Size(170, 30)
            $btn.Height = 30
            $btn.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $rowPanel.Controls.Add($btn)
        } elseif (-not ($run.Count -and $run[0].Ip)) {
            $btn = New-Btn '&Start' "Start $($app.Name) and wait for it to connect. Friends must be on the same VPN network as you." { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$app = (Get-InstalledVpns | Where-Object { `$_.Key -eq '$($app.Key)' } | Select-Object -First 1)`nSay (Start-OrDownload-Vpn `$app)`n`$State.VpnRefresh = (Get-Date).ToString('o')" 'vpn' }
            $btn.Size = New-Object System.Drawing.Size(170, 30)
            $btn.Height = 30
            $btn.Font = New-Object System.Drawing.Font('Segoe UI', 9)
            $rowPanel.Controls.Add($btn)
        }
        $script:VpnRowRefs += @{ Row = $rowPanel; Lbl = $lbl; Btn = $btn }
        $script:VpnRowsPanel.Controls.Add($rowPanel)
    }
    $script:VpnNote = New-Lbl 'Tip: only ONE VPN should be used at a time - friends must be on the SAME one as the IP line you send them. Close the unused VPNs.' $C.dim 9 30  $false 940
    $script:VpnNote.Location = New-Object System.Drawing.Point(0, 4)
    $script:VpnRowsPanel.Controls.Add($script:VpnNote)
}

function Layout-VpnRows {
    if (-not $script:VpnRowsPanel) { return }
    try {
        $w = $script:VpnRowsPanel.ClientSize.Width - 22
        if ($script:VpnTop) {
            $script:VpnTop.Height = SY(110)
            foreach ($c in $script:VpnTop.Controls) { if ($c -is [System.Windows.Forms.Label] -and $c.Width -gt 400) { $c.Width = $script:VpnTop.ClientSize.Width - 8 } }
        }
        foreach ($r in $script:VpnRowRefs) {
            $r.Row.Width = $w
            $r.Lbl.Width = $w - 210
            if ($r.Btn) {
                $bxv = $w - 190
                $r.Btn.Location = New-Object System.Drawing.Point($bxv, 8)
            }
            Set-Round $r.Row 10
        }
        if ($script:VpnNote) { $script:VpnNote.Width = $w }
    } catch { Write-Log "[LAYOUT-ERROR] VPNROWS $($_.Exception.Message)" }
}

function Show-ModsPage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $C.bg

    $script:ModsListPanel = New-Object System.Windows.Forms.Panel
    $script:ModsListPanel.Dock = 'Fill'
    $script:ModsListPanel.BackColor = $C.bg
    $script:ModsListPanel.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)

    $lblOn = New-Lbl 'Enabled mods (click to select)' $C.green 9.5 18 $true
    $lblOn.Location = New-Object System.Drawing.Point(0, 2)
    $script:ModsListPanel.Controls.Add($lblOn)
    $script:ListEnabled = New-Object System.Windows.Forms.ListBox
    $script:ListEnabled.Location = New-Object System.Drawing.Point(0, 24)
    $script:ListEnabled.Size = New-Object System.Drawing.Size(470, 280)
    $script:ListEnabled.BackColor = $C.panel
    $script:ListEnabled.ForeColor = [System.Drawing.Color]::White
    $script:ListEnabled.BorderStyle = 'FixedSingle'
    $script:ListEnabled.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $lblOff = New-Lbl 'Disabled mods (click to select)' $C.yellow 9.5 18 $true
    $lblOff.Location = New-Object System.Drawing.Point(480, 2)
    $script:ModsListPanel.Controls.Add($lblOff)
    $script:ListDisabled = New-Object System.Windows.Forms.ListBox
    $script:ListDisabled.Location = New-Object System.Drawing.Point(480, 24)
    $script:ListDisabled.Size = New-Object System.Drawing.Size(470, 280)
    $script:ListDisabled.BackColor = $C.panel
    $script:ListDisabled.ForeColor = [System.Drawing.Color]::White
    $script:ListDisabled.BorderStyle = 'FixedSingle'
    $script:ListDisabled.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $script:ModsListPanel.Controls.Add($script:ListEnabled)
    $script:ModsListPanel.Controls.Add($script:ListDisabled)

    $script:ModsTop = New-Object System.Windows.Forms.Panel
    $script:ModsTop.Dock = 'Top'
    $script:ModsTop.Height = 96
    $script:ModsTop.BackColor = $C.bg

    $head = New-Lbl 'Mod Manager  -  Resources\Client' $C.blue 14 26 $true
    $head.Location = New-Object System.Drawing.Point(4, 2)
    $script:ModsTop.Controls.Add($head)
    $sub = New-Lbl 'Disabled mods are moved to Server\Backups\mods and are NOT loaded by the server. Mods in .zip are synced to everyone who joins automatically.' $C.dim 9 20  $false 940
    $sub.Location = New-Object System.Drawing.Point(4, 30)
    $script:ModsTop.Controls.Add($sub)

    $btnDisable = New-Btn '&Disable selected' 'Move the selected enabled mod to Backups\mods (not loaded).' { ModAction 'disable' }
    $btnDisable.Size = New-Object System.Drawing.Size(130, 32)
    $btnDisable.Location = New-Object System.Drawing.Point(4, 54)
    $script:ModsTop.Controls.Add($btnDisable)

    $btnEnable = New-Btn '&Enable selected' 'Move the selected disabled mod back to Resources\Client (loaded).' { ModAction 'enable' }
    $btnEnable.Size = New-Object System.Drawing.Size(130, 32)
    $btnEnable.Location = New-Object System.Drawing.Point(140, 54)
    $script:ModsTop.Controls.Add($btnEnable)

    $btnScan = New-Btn '&Scan for suspicious files' 'Check all mods and zips for executables (.exe/.vbs/.cmd/...) and quarantine anything found.' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Scan-Mods)`n`$State.ModsRefresh = (Get-Date).ToString('o')" 'modscan' }
    $btnScan.Size = New-Object System.Drawing.Size(190, 32)
    $btnScan.Location = New-Object System.Drawing.Point(276, 54)
    $script:ModsTop.Controls.Add($btnScan)

    $btnOpen = New-Btn '&Open folder' 'Open Resources\Client in Explorer.' { Start-Process explorer.exe -ArgumentList ('"' + ($script:RootDir + 'Resources\Client') + '"') }
    $btnOpen.Size = New-Object System.Drawing.Size(110, 32)
    $btnOpen.Location = New-Object System.Drawing.Point(472, 54)
    $script:ModsTop.Controls.Add($btnOpen)

    $btnRefresh = New-Btn '&Refresh list' 'Reload the mod list.' { Show-ModsPage }
    $btnRefresh.Size = New-Object System.Drawing.Size(110, 32)
    $btnRefresh.Location = New-Object System.Drawing.Point(588, 54)
    $script:ModsTop.Controls.Add($btnRefresh)

    $p.Controls.Add($script:ModsListPanel)
    $p.Controls.Add($script:ModsTop)
    $script:Content.Controls.Add($p)
    $script:PageLayout = { Layout-Mods }

    $info = Get-ModsInfo
    $script:ListEnabled.Items.Clear()
    foreach ($f in $info.Enabled) { [void]$script:ListEnabled.Items.Add(("{0}  ({1:N1} MB)" -f $f.Name, ($f.Length / 1MB))) }
    $script:ListDisabled.Items.Clear()
    foreach ($f in $info.Disabled) { [void]$script:ListDisabled.Items.Add($f.Name) }
}

function Layout-Mods {
    if (-not $script:ModsListPanel) { return }
    try {
        $script:ModsTop.Height = SY(96)
        foreach ($c in $script:ModsTop.Controls) { if ($c -is [System.Windows.Forms.Label] -and $c.Width -gt 400) { $c.Width = $script:ModsTop.ClientSize.Width - 8 } }
        $w = $script:ModsListPanel.ClientSize.Width
        $h = $script:ModsListPanel.ClientSize.Height
        $colW = [int](($w - 10) / 2)
        $listH = [int][math]::Max(60, $h - 32)
        $x2 = $colW + 10
        $script:ListEnabled.Size = New-Object System.Drawing.Size($colW, $listH)
        $script:ListDisabled.Size = New-Object System.Drawing.Size($colW, $listH)
        $script:ListDisabled.Location = New-Object System.Drawing.Point($x2, 24)
    } catch { Write-Log "[LAYOUT-ERROR] MODS $($_.Exception.Message)" }
}

function ModAction([string]$Which) {
    $name = ''
    if ($Which -eq 'disable') {
        if ($script:ListEnabled.SelectedIndex -lt 0) { Add-Log "[INFO] Select a mod in the 'Enabled mods' list first."; return }
        $name = ($script:ListEnabled.SelectedItem -split '  ')[0]
    } else {
        if ($script:ListDisabled.SelectedIndex -lt 0) { Add-Log "[INFO] Select a mod in the 'Disabled mods' list first."; return }
        $name = $script:ListDisabled.SelectedItem
    }
    if (-not $name) { Add-Log "[INFO] No mod selected."; return }
    $fn = QStr $name
    $cmd = if ($Which -eq 'disable') { 'Disable-Mod' } else { 'Enable-Mod' }
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay ($cmd -Name $fn)`n`$State.ModsRefresh = (Get-Date).ToString('o')" 'mods'
}

function Show-SettingsPage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $C.bg

    $head = New-Lbl 'Settings' $C.blue 14 26 $true
    $head.Location = New-Object System.Drawing.Point(4, 2)
    $p.Controls.Add($head)

    $script:ChkLock = New-Object System.Windows.Forms.CheckBox
    $script:ChkLock.Text = 'Lock my IP while hosting (keeps the LAN IP fixed so router forwards never break when the DHCP lease renews)'
    $script:ChkLock.ForeColor = [System.Drawing.Color]::White
    $script:ChkLock.BackColor = [System.Drawing.Color]::Transparent
    $script:ChkLock.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $script:ChkLock.Location = New-Object System.Drawing.Point(8, 36)
    $script:ChkLock.Size = New-Object System.Drawing.Size(720, 26)
    $script:ChkLock.Checked = (Test-StaticIpLocked)
    $p.Controls.Add($script:ChkLock)

    $script:LblSettings1 = New-Lbl 'Server name (shown in the BeamMP list):' $C.dim 9.5 20
    $script:LblSettings1.Location = New-Object System.Drawing.Point(8, 74)
    $p.Controls.Add($script:LblSettings1)
    $script:TxtName = New-Object System.Windows.Forms.TextBox
    $script:TxtName.Location = New-Object System.Drawing.Point(8, 96)
    $script:TxtName.Size = New-Object System.Drawing.Size(300, 26)
    $script:TxtName.BackColor = $C.panel
    $script:TxtName.ForeColor = [System.Drawing.Color]::White
    $script:TxtName.BorderStyle = 'FixedSingle'
    $m = Select-String -LiteralPath ($script:RootDir + 'ServerConfig.toml') -Pattern '^\s*Name\s*=\s*"(.*)"' | Select-Object -First 1
    if ($m) { $script:TxtName.Text = $m.Matches[0].Groups[1].Value }
    $p.Controls.Add($script:TxtName)

    $script:LblSettings2 = New-Lbl 'Max players:' $C.dim 9.5 20
    $script:LblSettings2.Location = New-Object System.Drawing.Point(8, 130)
    $p.Controls.Add($script:LblSettings2)
    $script:TxtPlayers = New-Object System.Windows.Forms.TextBox
    $script:TxtPlayers.Location = New-Object System.Drawing.Point(8, 152)
    $script:TxtPlayers.Size = New-Object System.Drawing.Size(120, 26)
    $script:TxtPlayers.BackColor = $C.panel
    $script:TxtPlayers.ForeColor = [System.Drawing.Color]::White
    $script:TxtPlayers.BorderStyle = 'FixedSingle'
    $m2 = Select-String -LiteralPath ($script:RootDir + 'ServerConfig.toml') -Pattern '^\s*MaxPlayers\s*=\s*(\d+)' | Select-Object -First 1
    if ($m2) { $script:TxtPlayers.Text = $m2.Matches[0].Groups[1].Value }
    $p.Controls.Add($script:TxtPlayers)

    $script:BtnSave = New-Btn '&Save settings' 'Save the server name and max players.' { Save-Settings }
    $script:BtnSave.Size = New-Object System.Drawing.Size(120, 34)
    $script:BtnSave.Location = New-Object System.Drawing.Point(8, 188)
    $p.Controls.Add($script:BtnSave)

    $script:LblSettings3 = New-Lbl ("Port: $((Get-ServerPort))  (change it automatically if it is ever busy)") $C.dim 9.5 20  $false 600
    $script:LblSettings3.Location = New-Object System.Drawing.Point(8, 240)
    $p.Controls.Add($script:LblSettings3)
    $script:BtnPort = New-Btn '&Use a free port' 'Pick a free port and write it to ServerConfig.toml. Remember: the router must forward the NEW port (TCP+UDP).' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Set-FreePort -Port (Get-FreePort))" 'setport' }
    $script:BtnPort.Size = New-Object System.Drawing.Size(130, 34)
    $script:BtnPort.Location = New-Object System.Drawing.Point(8, 264)
    $p.Controls.Add($script:BtnPort)

    $script:LblSettings4 = New-Lbl 'Server key (BEAMMP_AUTHKEY) - stored in Server\.env, never shown again:' $C.dim 9.5 20  $false 600
    $script:LblSettings4.Location = New-Object System.Drawing.Point(8, 316)
    $p.Controls.Add($script:LblSettings4)
    $script:BtnKey = New-Btn '&Set up / change my server key' 'Open the key setup dialog. Get your free key at https://keymaster.beammp.com' { Show-KeySetupDialog $script:Form }
    $script:BtnKey.Size = New-Object System.Drawing.Size(200, 34)
    $script:BtnKey.Location = New-Object System.Drawing.Point(8, 340)
    $p.Controls.Add($script:BtnKey)

    $script:BtnUpdate = New-Btn '&Check for BeamMP-Server updates' 'Ask GitHub if a newer BeamMP-Server build exists (cached 24h).' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$msg = Check-ForUpdates`n`$State.UpdateMsg = `$msg`nif (`$msg) { Say `$msg } else { Say ""BeamMP-Server is up to date."" }" 'update' }
    $script:BtnUpdate.Size = New-Object System.Drawing.Size(220, 34)
    $script:BtnUpdate.Location = New-Object System.Drawing.Point(8, 390)
    $p.Controls.Add($script:BtnUpdate)

    $script:LblSettingsResult = New-Lbl '' $C.green 9.5 40  $false 800
    $script:LblSettingsResult.Location = New-Object System.Drawing.Point(8, 434)
    $p.Controls.Add($script:LblSettingsResult)

    $script:Content.Controls.Add($p)
    $script:PageLayout = { Layout-Settings }
}

function Layout-Settings {
    if (-not $script:TxtName) { return }
    try {
        $w = $script:Content.ClientSize.Width - 16
        $y36 = SY 36; $y74 = SY 74; $y96 = SY 96; $y130 = SY 130; $y152 = SY 152
        $y188 = SY 188; $y240 = SY 240; $y264 = SY 264; $y316 = SY 316; $y340 = SY 340
        $y390 = SY 390; $y434 = SY 434
        $tw = SX 300; $pw2 = SX 120
        $script:ChkLock.Width = $w
        $script:ChkLock.Location = New-Object System.Drawing.Point(8, $y36)
        $script:LblSettings1.Location = New-Object System.Drawing.Point(8, $y74)
        $script:TxtName.Location = New-Object System.Drawing.Point(8, $y96)
        $script:TxtName.Size = New-Object System.Drawing.Size($tw, 26)
        $script:LblSettings2.Location = New-Object System.Drawing.Point(8, $y130)
        $script:TxtPlayers.Location = New-Object System.Drawing.Point(8, $y152)
        $script:TxtPlayers.Size = New-Object System.Drawing.Size($pw2, 26)
        $script:BtnSave.Location = New-Object System.Drawing.Point(8, $y188)
        $script:LblSettings3.Location = New-Object System.Drawing.Point(8, $y240)
        $script:LblSettings3.Width = $w
        $script:BtnPort.Location = New-Object System.Drawing.Point(8, $y264)
        $script:LblSettings4.Location = New-Object System.Drawing.Point(8, $y316)
        $script:LblSettings4.Width = $w
        $script:BtnKey.Location = New-Object System.Drawing.Point(8, $y340)
        $script:BtnUpdate.Location = New-Object System.Drawing.Point(8, $y390)
        $script:LblSettingsResult.Location = New-Object System.Drawing.Point(8, $y434)
        $script:LblSettingsResult.Width = $w
    } catch { Write-Log "[LAYOUT-ERROR] SETTINGS $($_.Exception.Message)" }
}

function Save-Settings {
    $name = $script:TxtName.Text.Trim()
    $players = $script:TxtPlayers.Text.Trim()
    if ($name -and $name -notmatch '^[^"]{1,60}$') {
        Add-Log "[ERROR] Server name must be 60 characters or fewer and cannot contain double quotes."
        return
    }
    if ($players -and $players -notmatch '^\d+$') {
        Add-Log "[ERROR] Max players must be a number."
        return
    }
    $nameArg = $(if ($name) { QStr $name } else { "''" })
    $playersArg = $(if ($players -match '^\d+$') { $players } else { '0' })
    if ($name -or $players) {
        Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Update-Config -Name $nameArg -Players $playersArg)`n`$State.SettingsSaved = (Get-Date).ToString('o')" 'settings'
    }
    $lockNow = Test-StaticIpLocked
    if ($script:ChkLock.Checked -and -not $lockNow) {
        Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay ""Enabling the IP lock...""`nif (Set-StaticLanIp) { Say ""IP lock enabled - it will be applied on the next server start."" } else { Say ""Could not enable the lock (was the Windows window cancelled?)."" }" 'lockon'
    } elseif (-not $script:ChkLock.Checked -and $lockNow) {
        Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay ""Disabling the IP lock...""`nif (Restore-DhcpLanIp) { Remove-Item -LiteralPath ($script:ServerDir + 'staticip.cfg') -Force -ErrorAction SilentlyContinue; Say ""Lock disabled - your IP returns to DHCP now."" } else { Say ""Could not disable it (was the Windows window cancelled?)."" }" 'lockoff'
    }
    Add-Log "[OK] Settings saved."
    Refresh-Dashboard
}

# ---------------------------------------------------------------------------------------
# DIALOGS
# ---------------------------------------------------------------------------------------
$EulaText = @'
K BNG M Hoster - END USER LICENSE AGREEMENT

Licensor / Copyright Holder: Kinan (@raed713) - Copyright (c) 2026. All Rights Reserved.

IMPORTANT: BY DOWNLOADING, INSTALLING, ACCESSING, OR USING THE SOFTWARE, YOU
ACCEPT AND AGREE TO THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT USE THE SOFTWARE.

1. LICENSE GRANT - LIMITED USE
   You may: (a) run the unmodified Software on your devices for personal,
   non-commercial use; (b) edit Configuration Files where the documentation
   permits (e.g. AuthKey in ServerConfig.toml); (c) add user mod archives
   into Resources/Client/ for server-side mod syncing. All other rights are reserved.

2. PROHIBITED CONDUCT
   You shall NOT: (a) modify, patch, adapt, translate, or create derivative works
   of the Software; (b) decompile, disassemble, or reverse-engineer it;
   (c) redistribute, reupload, mirror, fork, publish, share, sell, sublicense,
   lease, rent, or transfer the Software, except by directing others to the
   official GitHub Releases page; (d) use it for paid hosting or commercial
   services without prior written permission; (e) remove, alter, or obscure
   any attribution identifying the Licensor (Kinan / @raed713).

3. TERMINATION
   This license may be terminated immediately upon notice for any breach.
   Upon termination you must cease use and delete all copies of the Software.

4. DISCLAIMER OF WARRANTY
   THE SOFTWARE IS PROVIDED 'AS IS' AND 'AS AVAILABLE', WITHOUT WARRANTY OF ANY
   KIND, EXPRESS OR IMPLIED. THE ENTIRE RISK ARISING OUT OF ITS USE REMAINS WITH YOU.

5. LIMITATION OF LIABILITY
   TO THE MAXIMUM EXTENT PERMITTED BY LAW, THE LICENSOR SHALL NOT BE LIABLE FOR
   ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY
   LOSS OF PROFITS, DATA, OR GOODWILL, ARISING OUT OF OR RELATED TO THE USE OF
   OR INABILITY TO USE THE SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.

6. GOVERNING LAW
   This Agreement is governed by the laws of Sweden, without regard to its
   conflict-of-law provisions. The Licensor may also seek to enforce this
   Agreement in any jurisdiction where the Software is used or a breach has occurred.

7. CONTACT
   Legal inquiries, permissions requests, and DMCA notices: open an issue at
   https://github.com/Kinan0713/K-BNG-M-Hoster/issues

8. GENERAL
   Sections 2-8 survive termination. This is the entire agreement regarding the
   Software and supersedes any prior agreements or understandings.

The full agreement is available in the LICENSE file shipped with this tool.
'@

function Show-EulaDialog {
    $marker = $script:ServerDir + 'Logs\eula.accepted'
    if (Test-Path -LiteralPath $marker) { return $true }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'K BNG M Hoster - End User License Agreement'
    $dlg.Size = New-Object System.Drawing.Size(780, 640)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $C.bg
    $dlg.ForeColor = $C.text

    $title = New-Lbl 'K BNG M Hoster - End User License Agreement' ([System.Drawing.Color]::Yellow) 13 28 $true
    $title.Location = New-Object System.Drawing.Point(14, 10)
    $dlg.Controls.Add($title)

    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Location = New-Object System.Drawing.Point(14, 44)
    $box.Size = New-Object System.Drawing.Size(736, 500)
    $box.ReadOnly = $true
    $box.BackColor = $C.log
    $box.ForeColor = [System.Drawing.Color]::FromArgb(212, 212, 212)
    $box.BorderStyle = 'FixedSingle'
    $box.Font = New-Object System.Drawing.Font('Consolas', 9.5)
    $box.Text = $EulaText
    $dlg.Controls.Add($box)

    $accept = New-Btn '&I Accept' 'Accept the license and use K BNG M Hoster.' { $dlg.DialogResult = 'OK' }
    $accept.Size = New-Object System.Drawing.Size(110, 36)
    $accept.Location = New-Object System.Drawing.Point(330, 556)
    $accept.BackColor = [System.Drawing.Color]::FromArgb(35, 100, 60)
    $accept.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(63, 185, 80)
    $dlg.Controls.Add($accept)
    $decline = New-Btn '&I Do Not Accept' 'Leave the tool. It will not run without accepting the license.' { $dlg.DialogResult = 'Cancel' }
    $decline.Size = New-Object System.Drawing.Size(130, 36)
    $decline.Location = New-Object System.Drawing.Point(446, 556)
    $dlg.Controls.Add($decline)
    $dlg.AcceptButton = $accept
    $dlg.CancelButton = $decline
    $null = $dlg.Handle
    Set-Round $dlg 10

    $r = $dlg.ShowDialog()
    if ($r -eq 'OK') {
        $logDir = $script:ServerDir + 'Logs'
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        Set-Content -LiteralPath $marker -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Write-Log "EULA accepted"
        return $true
    }
    Write-Log "EULA rejected"
    return $false
}

function Show-KeySetupDialog($owner) {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Server key - first-time setup'
    $dlg.Size = New-Object System.Drawing.Size(620, 430)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $C.bg
    $dlg.ForeColor = $C.text

    $intro = New-Lbl 'This key is how BeamMP knows you own your server. It is free and takes 1 minute. It will be saved to Server\.env and never shown again.' $C.dim 9.5 40  $false 570
    $intro.Location = New-Object System.Drawing.Point(14, 12)
    $dlg.Controls.Add($intro)

    $link = New-Object System.Windows.Forms.LinkLabel
    $link.Text = 'Get your free key here: https://keymaster.beammp.com  (opens in your browser)'
    $link.LinkColor = $C.blue
    $link.ActiveLinkColor = [System.Drawing.Color]::White
    $link.Location = New-Object System.Drawing.Point(14, 60)
    $link.Size = New-Object System.Drawing.Size(570, 22)
    $link.Add_LinkClicked({ Start-Process 'https://keymaster.beammp.com' })
    $dlg.Controls.Add($link)

    $lbl = New-Lbl 'Paste your key here (right-click to paste):' $C.text 9.5 20
    $lbl.Location = New-Object System.Drawing.Point(14, 96)
    $dlg.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(14, 118)
    $txt.Size = New-Object System.Drawing.Size(570, 26)
    $txt.BackColor = $C.panel
    $txt.ForeColor = [System.Drawing.Color]::White
    $txt.BorderStyle = 'FixedSingle'
    $dlg.Controls.Add($txt)

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = 'Also apply recommended server settings (backup first: port, name, max players)'
    $chk.Checked = $true
    $chk.ForeColor = [System.Drawing.Color]::White
    $chk.BackColor = [System.Drawing.Color]::Transparent
    $chk.Location = New-Object System.Drawing.Point(14, 160)
    $chk.Size = New-Object System.Drawing.Size(570, 24)
    $dlg.Controls.Add($chk)

    $lblResult = New-Lbl '' $C.yellow 9.5 40  $false 570
    $lblResult.Location = New-Object System.Drawing.Point(14, 194)
    $dlg.Controls.Add($lblResult)

    $save = New-Btn '&Save Key' 'Validate and save the key.' {
        $r = Save-AuthKey -Key $txt.Text
        if ($r.Ok) {
            if ($chk.Checked) {
                $port = New-SetupConfig
                $lblResult.Text = "$($r.Message)  Server settings applied (port $port)."
            } else {
                $lblResult.Text = $r.Message
            }
            $lblResult.ForeColor = $C.green
            $dlg.DialogResult = 'OK'
        } else {
            $lblResult.Text = $r.Message
            $lblResult.ForeColor = $C.red
        }
    }
    $save.Size = New-Object System.Drawing.Size(110, 36)
    $save.Location = New-Object System.Drawing.Point(14, 250)
    $save.BackColor = [System.Drawing.Color]::FromArgb(35, 100, 60)
    $save.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(63, 185, 80)
    $dlg.Controls.Add($save)

    $skip = New-Btn '&Skip for now' 'Continue without a key. You can set it up later in Settings.' { $dlg.DialogResult = 'Cancel' }
    $skip.Size = New-Object System.Drawing.Size(110, 36)
    $skip.Location = New-Object System.Drawing.Point(130, 250)
    $dlg.Controls.Add($skip)

    $note = New-Lbl 'A valid key contains only letters, numbers and dashes (8-64 characters).' $C.dim 8.5 20  $false 570
    $note.Location = New-Object System.Drawing.Point(14, 300)
    $dlg.Controls.Add($note)

    $dlg.AcceptButton = $save
    $dlg.CancelButton = $skip
    $null = $dlg.Handle
    Set-Round $dlg 10
    $r = $dlg.ShowDialog($owner)
    $dlg.Dispose()
    return ($r -eq 'OK')
}

function Show-CgnatPrompt($owner) {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'One more thing before you start...'
    $dlg.Size = New-Object System.Drawing.Size(680, 320)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $C.bg
    $dlg.ForeColor = $C.text

    $msg = New-Lbl "Your ISP uses CGNAT - port forwarding can never work on this connection.`nA VPN is how friends can reach you.`n`nSAFETY: a VPN puts friends on a virtual LAN with your PC (they can reach`nfile sharing / Remote Desktop etc.) - only invite people you TRUST.`nNever invite random players into your VPN network." $C.yellow 10 100  $false 620
    $msg.Location = New-Object System.Drawing.Point(18, 16)
    $dlg.Controls.Add($msg)

    $btnVpn = New-Btn '&Open VPN Manager' 'Go to the VPN Manager to start or install a VPN.' { $dlg.DialogResult = 'Yes' }
    $btnVpn.Size = New-Object System.Drawing.Size(160, 38)
    $btnVpn.Location = New-Object System.Drawing.Point(18, 150)
    $dlg.Controls.Add($btnVpn)

    $btnAnyway = New-Btn '&Start anyway' 'Skip the VPN for now and start the server (friends will only reach you via the same WiFi, or after you set up a VPN).' { $dlg.DialogResult = 'No' }
    $btnAnyway.Size = New-Object System.Drawing.Size(140, 38)
    $btnAnyway.Location = New-Object System.Drawing.Point(186, 150)
    $dlg.Controls.Add($btnAnyway)

    $btnCancel = New-Btn '&Cancel' 'Do not start the server.' { $dlg.DialogResult = 'Cancel' }
    $btnCancel.Size = New-Object System.Drawing.Size(100, 38)
    $btnCancel.Location = New-Object System.Drawing.Point(334, 150)
    $dlg.Controls.Add($btnCancel)

    $null = $dlg.Handle
    Set-Round $dlg 10

    $r = $dlg.ShowDialog($owner)
    $dlg.Dispose()
    return $r
}

# ---------------------------------------------------------------------------------------
# ACTIONS (start / stop / diagnose / copy / clean)
# ---------------------------------------------------------------------------------------
function Start-ServerFlow {
    if ($script:State.Running) { Add-Log "[INFO] The server is already running."; return }
    if ($script:Starting) { Add-Log "[INFO] Already starting..."; return }
    if ($script:State.StopRequested) { $script:State.StopRequested = $false }

    if (-not (Test-AuthKeyConfigured)) {
        Add-Log "[INFO] No server key yet - setting it up first (you can skip)."
        $null = Show-KeySetupDialog $script:Form
        if (-not (Test-AuthKeyConfigured)) {
            Add-Log "[INFO] No server key - the server cannot start without it. Use Settings or Fix Problems to set it up."
            return
        }
    }

    if (-not (Test-Path -LiteralPath $script:LauncherPath)) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "The free BeamMP Launcher is required to detect your game session.`nOpen its download page now?`n(Install it, then press Start again.)",
            'BeamMP Launcher needed', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
        if ($r -eq 'Yes') { Start-Process 'https://beammp.com' }
        Add-Log "[INFO] BeamMP Launcher not installed - install it from https://beammp.com, then press Start again."
        return
    }

    $script:Starting = $true
    Update-BusyUi
    $script:BtnStart.Enabled = $false
    $script:BtnStart.Text = 'Starting...'
    Add-Log "===== Starting the server ====="
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.Pre = Get-ConnectionInfo" 'precheck'
}

function Continue-StartFlow {
    $script:Starting = $false
    $script:BtnStart.Text = '&Start Server'
    $script:BtnStart.Enabled = -not $script:State.Running
    Update-BusyUi
    $conn = $script:State.Pre
    $marker = $script:ServerDir + 'Logs\vpn.asked'
    if ($conn -and $conn.Cgnat -and -not (Test-Path -LiteralPath $marker)) {
        $logDir = $script:ServerDir + 'Logs'
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $r = Show-CgnatPrompt $script:Form
        Set-Content -LiteralPath $marker -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Write-Log "Pre-start VPN help shown (CGNAT network)"
        if ($r -eq 'Cancel') {
            Add-Log "[INFO] Start cancelled."
            return
        }
        if ($r -eq 'Yes') {
            Show-VpnPage
            Add-Log "[INFO] Server not started - set up a VPN first, then press Start again."
            return
        }
    }
    Launch-Session
}

function Launch-Session {
    $script:State.Conn = $script:State.Pre
    $script:State.SessionEnded = $null
    $script:LastSessionEnded = $null
    $script:State.StopRequested = $false
    $ps = [powershell]::Create()
    $null = $ps.AddScript($script:CoreText)
    $null = $ps.AddScript('param($Queue, $State) Start-HosterSession -Queue $Queue -State $State').AddArgument($script:Queue).AddArgument($script:State)
    $script:SessionPs = $ps
    $script:SessionHandle = $ps.BeginInvoke()
    $script:BtnStart.Enabled = $false
    $script:BtnStop.Enabled = $true
    Add-Log "[INFO] Server starting - watch the log below."
}

function Stop-ServerFlow {
    if (-not $script:State.Running -and -not (Get-Process -Name 'BeamMP-Server' -ErrorAction SilentlyContinue)) {
        Add-Log "[INFO] Nothing is running."
        return
    }
    Add-Log "===== Stop requested ====="
    $script:State.StopRequested = $true
    Stop-Process -Name 'BeamMP-Launcher' -ErrorAction SilentlyContinue
    Stop-Process -Name 'BeamMP-Server' -ErrorAction SilentlyContinue
    if (-not $script:State.Running) {
        Add-Log "[INFO] Server process stopped."
    }
}

function Copy-ConnectionLine {
    $conn = $script:State.Conn
    $port = if ($conn) { $conn.Port } else { Get-ServerPort }
    $line = "127.0.0.1:$port"
    if ($conn -and $conn.LAN) { $line = "$($conn.LAN):$port" }
    $vpnLines = @()
    if ($conn) { $vpnLines = @($conn.Vpn | Where-Object { $_.Ip }) }
    if ($conn -and $vpnLines.Count -and -not $conn.LAN) { $line = "$($vpnLines[0].Ip):$port" }
    if ($conn -and $conn.Tailscale -and -not $conn.LAN -and -not $vpnLines.Count) { $line = "$($conn.Tailscale):$port" }
    try {
        [System.Windows.Forms.Clipboard]::SetText($line)
        Add-Log "[OK] Copied to clipboard: $line  (send this to your friends)"
    } catch {
        Add-Log "[ERROR] Could not copy to clipboard: $_"
    }
}

function Run-Diagnose {
    if ($script:Busy) { Add-Log "[INFO] Another task is running - wait a moment."; return }
    Add-Log "[INFO] Running diagnosis..."
    $act = @'
param($Queue, $State)
$script:Q = $Queue
$c = Get-ConnectionInfo
$srvPort = Get-ServerPort
$vpnOk = @($c.Vpn | Where-Object { $_.Ip })
$lines = @()
if ($vpnOk.Count) { $lines += "VPN running: " + (($vpnOk | ForEach-Object { $_.Name + ' ' + $_.Ip }) -join ', ') } else { $lines += 'VPN running: none (start one from the VPN Manager if friends cannot join)' }
$lines += "LAN IP: " + $(if ($c.LAN) { $c.LAN } else { 'not detected' })
$lines += "Tailscale: " + $(if ($c.Tailscale) { $c.Tailscale } else { 'not running' })
$lines += "Public IP: " + $(if ($c.Public) { $c.Public } else { 'not detected' })
$lines += "CGNAT: " + $(if ($c.Cgnat) { 'YES - public hosting cannot work; use a VPN' } else { 'no' })
$lines += "Server listening: " + $(if (Test-Loopback $srvPort) { 'yes (127.0.0.1:' + $srvPort + ')' } else { 'NO - restart the server' })
$lines += "Firewall rules: " + $(if (Test-FirewallRule) { 'present' } else { 'MISSING - use Fix Problems, Firewall row' })
$State.Diag = $lines -join "`r`n"
Say "Diagnosis ready."
'@
    Start-CoreAction $act 'diag'
}

function Show-DiagResult {
    if ($script:State.Diag) {
        [System.Windows.Forms.MessageBox]::Show($script:State.Diag, 'Problem diagnosis', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        $script:State.Diag = ''
    }
}

function Run-CleanFlow {
    if ($script:State.Running) {
        [System.Windows.Forms.MessageBox]::Show('Stop the server first - it is still running.', 'Clean personal info', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Remove anything personal or temporary so the folder is safe to zip and share:`n  - .env (your secret server key)`n  - webhook.txt (Discord webhook)`n  - Logs\ and Server.log (IP caches, player names)`n  - CONNECTING.txt (contains your IP addresses)`n  - Backups\ , Quarantine\`n  - staticip.cfg (IP lock - restored to DHCP first)`n  - AuthKey inside ServerConfig.toml`n`nRun this BEFORE zipping the folder to give to someone else.",
        'Clean personal info', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($r -eq 'Yes') {
        Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Invoke-CleanForSharing)" 'clean'
    }
}

# ---------------------------------------------------------------------------------------
# TIMERS
# ---------------------------------------------------------------------------------------
$timerMain = New-Object System.Windows.Forms.Timer
$timerMain.Interval = 400
$timerMain.Add_Tick({
    $line = $null
    while ($script:Queue.TryDequeue([ref]$line)) { Add-Log $line }

    if ($script:PendingAction -and $script:PendingAction.Handle.IsCompleted) {
        $pa = $script:PendingAction
        try { $null = $pa.Ps.EndInvoke($pa.Handle) } catch { Add-Log "[ERROR] $($_.Exception.InnerException.Message)" }
        $pa.Ps.Dispose()
        $tag = $pa.Tag
        $script:PendingAction = $null
        $script:Busy = $false
        Update-BusyUi
        switch ($tag) {
            'precheck' { Continue-StartFlow }
            'fixscan' {
                if ($script:State.FixReport) {
                    $script:FixRowsPanel.Controls.Clear()
                    $script:FixRowRefs = @()
                    foreach ($row in $script:State.FixReport) { Add-FixRow $row }
                    Layout-FixRows
                }
            }
            'diag' { Show-DiagResult }
            'vpn' { Refresh-VpnRows }
            'vpns' { Refresh-VpnRows }
            'mods' { Show-ModsPage }
            'modscan' { Show-ModsPage }
            'settings' { $script:LblSettingsResult.Text = 'Settings saved.'; $script:LblSettingsResult.ForeColor = $C.green }
            'update' { $script:LblSettingsResult.Text = $(if ($script:State.UpdateMsg) { "Update available: $($script:State.UpdateMsg)" } else { 'Checked.' }); $script:LblSettingsResult.ForeColor = $C.green }
        }
    }

    if ($script:SessionHandle -and $script:State.SessionEnded -and $script:State.SessionEnded -ne $script:LastSessionEnded) {
        $script:LastSessionEnded = $script:State.SessionEnded
        try { $null = $script:SessionPs.EndInvoke($script:SessionHandle) } catch { Add-Log "[ERROR] $($_.Exception.InnerException.Message)" }
        $script:SessionPs.Dispose()
        $script:SessionPs = $null
        $script:SessionHandle = $null
        $script:State.Running = $false
        $script:BtnStart.Enabled = $true
        $script:BtnStop.Enabled = $false
        $script:BtnStart.Text = '&Start Server'
        $script:LblPlayers.Text = ''
        Add-Log "[INFO] Session finished. You can press Start again."
        Refresh-Dashboard
        if ($script:ClosingAfterStop) {
            $script:AllowClose = $true
            $script:Form.Close()
        }
    }

    if ($script:State.Running -ne $script:LastRunning) {
        $script:LastRunning = $script:State.Running
        $script:BtnStart.Enabled = -not $script:State.Running
        $script:BtnStop.Enabled = $script:State.Running
        Refresh-Dashboard
    }
})
$timerMain.Start()

$timerLive = New-Object System.Windows.Forms.Timer
$timerLive.Interval = 6000
$timerLive.Add_Tick({
    $playersFile = $script:ServerDir + 'Logs\players.tmp'
    if (Test-Path -LiteralPath $playersFile) {
        $state = (Get-Content -LiteralPath $playersFile -Raw).Trim()
        if ($state) { $script:LblPlayers.Text = $state }
    } elseif (-not $script:State.Running) {
        $script:LblPlayers.Text = ''
    }
    if ($script:State.Running -and -not $script:Busy) {
        Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.Conn = Get-ConnectionInfo" 'live'
    } elseif (-not $script:State.Running) {
        $script:State.Conn = $null
    }
    if ($script:State.Conn) { Refresh-Dashboard }
})
$timerLive.Start()

# ---------------------------------------------------------------------------------------
# GUIDE PAGE (the README lives inside the app)
# ---------------------------------------------------------------------------------------
function Add-GuideLine([string]$Text, [string]$Color = 'text', [bool]$Bold = $false, [float]$Size = 10.5) {
    if (-not $script:GuideBox) { return }
    $script:GuideBox.SelectionStart = $script:GuideBox.TextLength
    $script:GuideBox.SelectionLength = 0
    $script:GuideBox.SelectionColor = $C[$Color]
    $script:GuideBox.SelectionFont = New-Object System.Drawing.Font('Segoe UI', $Size, $(if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }))
    $script:GuideBox.AppendText($Text + [Environment]::NewLine)
}

function Show-GuidePage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $C.bg

    $script:GuideHead = New-Lbl 'Guide  -  everything you need, no files to open' $C.blue 14 26 $true
    $script:GuideHead.Location = New-Object System.Drawing.Point(14, 6)
    $p.Controls.Add($script:GuideHead)

    $script:GuideBtns = @(
        (New-Btn '&Start Server' 'Go to the dashboard and start the server. (Ctrl+S)' { Show-DashboardPage }),
        (New-Btn '&Fix Problems' 'Open the Fix Problems page. (Ctrl+F)' { Show-FixPage }),
        (New-Btn '&VPN Manager' 'Open the VPN Manager page. (Ctrl+V)' { Show-VpnPage }),
        (New-Btn '&Mods' 'Open the Mods page. (Ctrl+M)' { Show-ModsPage }),
        (New-Btn '&Settings' 'Open the Settings page. (Ctrl+T)' { Show-SettingsPage }),
        (New-Btn 'C&lean Info' 'Wipe personal files (key, webhook, logs, IP files) before sharing the folder.' { Run-CleanFlow })
    )
    foreach ($b in $script:GuideBtns) { $p.Controls.Add($b) }

    $script:GuideBox = New-Object System.Windows.Forms.RichTextBox
    $script:GuideBox.ReadOnly = $true
    $script:GuideBox.DetectUrls = $false
    $script:GuideBox.BackColor = $C.panel
    $script:GuideBox.ForeColor = $C.text
    $script:GuideBox.BorderStyle = 'None'
    $script:GuideBox.WordWrap = $true
    $script:GuideBox.ScrollBars = 'Vertical'
    $p.Controls.Add($script:GuideBox)

    Add-GuideLine 'STEP 1  -  START THE SERVER' 'yellow' $true 12
    Add-GuideLine '  Double-click Start_Here.bat - this window opens.'
    Add-GuideLine '  First time only: a small window asks for your server key.'
    Add-GuideLine '      1. Get your free key at https://keymaster.beammp.com'
    Add-GuideLine '      2. Paste it and click Save - it is stored privately in Server\.env'
    Add-GuideLine '  Click Start Server (or Ctrl+S). The BeamMP Launcher opens automatically.'
    Add-GuideLine '  In BeamNG: More... -> BeamMP -> Direct Connect, use the address'
    Add-GuideLine '  shown under "THIS PC (test it now)" to test on your own PC.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 2  -  HOW YOUR FRIENDS CONNECT' 'yellow' $true 12
    Add-GuideLine '  Send them ONE line from the dashboard. In BeamNG they open'
    Add-GuideLine '  More... -> BeamMP -> Direct Connect and type the address you send.'
    Add-GuideLine '      - "THIS PC (test it now)"       just testing on your own machine'
    Add-GuideLine '      - "Friends (same WiFi)"         LAN - same network only'
    Add-GuideLine '      - "Friends (VPN) / Tailscale"   works anywhere, even without'
    Add-GuideLine '        port forwarding (best behind CGNAT)'
    Add-GuideLine '      - "Anyone (internet)"           needs the port forwarded on the router'
    Add-GuideLine '  IMPORTANT: never click your own server in the BeamMP list - it uses'
    Add-GuideLine '  your public IP and fails from inside your network. Always use'
    Add-GuideLine '  Direct Connect with the address from this window.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 3  -  CANNOT CONNECT? RUN FIX PROBLEMS' 'yellow' $true 12
    Add-GuideLine '  Click Fix Problems (or Ctrl+F). It checks everything - key, port,'
    Add-GuideLine '  firewall, VPNs, CGNAT, reachability - and fixes most issues with'
    Add-GuideLine '  one click. Follow the instructions on each row.'
    Add-GuideLine '  If your ISP uses CGNAT, port forwarding can NEVER work:'
    Add-GuideLine '  use the VPN Manager (Ctrl+V) instead - VPNs bypass CGNAT.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 4  -  MODS' 'yellow' $true 12
    Add-GuideLine '  Click Mods (or Ctrl+M). Drop mod .zip files into'
    Add-GuideLine '  Server\Resources\Client\ and they sync to everyone who joins.'
    Add-GuideLine '  Suspicious files (exe, vbs, cmd, scr, pif) are auto-quarantined.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 5  -  SETTINGS' 'yellow' $true 12
    Add-GuideLine '  Click Settings (or Ctrl+T): server name, max players, free port,'
    Add-GuideLine '  IP lock and your server key. No config files needed - the GUI'
    Add-GuideLine '  saves everything for you.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 6  -  BEFORE SHARING THE FOLDER' 'yellow' $true 12
    Add-GuideLine '  Click Clean Info (the red button) - it wipes your key, webhook,'
    Add-GuideLine '  logs, backups and IP files so the folder is safe to zip and share.'
    Add-GuideLine '  NEVER share Server\.env or Server\webhook.txt.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 7  -  STUCK? CHECK THE ACTIVITY LOG' 'yellow' $true 12
    Add-GuideLine '  The log at the bottom of the window says exactly what the tool is'
    Add-GuideLine '  doing and why. Every button also explains itself in a tooltip -'
    Add-GuideLine '  hover any button to see what it does.'
    Add-GuideLine ''

    $script:Content.Controls.Add($p)
    $script:PageLayout = { Layout-Guide }
}

function Layout-Guide {
    if (-not $script:GuideBox) { return }
    try {
        $w = $script:Content.ClientSize.Width
        $h = $script:Content.ClientSize.Height
        $script:GuideHead.Location = New-Object System.Drawing.Point((SX 14), (SY 6))
        $by = SY 40
        for ($i = 0; $i -lt $script:GuideBtns.Count; $i++) {
            $bx = SX (14 + $i * 118)
            $script:GuideBtns[$i].Location = New-Object System.Drawing.Point($bx, $by)
            $script:GuideBtns[$i].Size = New-Object System.Drawing.Size((SX 112), (SY 32))
            Set-Round $script:GuideBtns[$i] 7
        }
        $script:GuideBox.Location = New-Object System.Drawing.Point((SX 14), (SY 82))
        $script:GuideBox.Size = New-Object System.Drawing.Size(($w - (SX 28)), ($h - (SY 96)))
    } catch { Write-Log "[LAYOUT-ERROR] GUIDE $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------------------
# KEYBOARD SHORTCUTS
# ---------------------------------------------------------------------------------------
$script:Form.Add_KeyDown({
    param($s, $e)
    if ($script:Form.ActiveControl -is [System.Windows.Forms.TextBox]) { return }
    if ($e.Control -and -not $e.Alt) {
        switch ($e.KeyCode) {
            'S' { Start-ServerFlow; $e.SuppressKeyPress = $true }
            'X' { Stop-ServerFlow; $e.SuppressKeyPress = $true }
            'F' { Show-FixPage; $e.SuppressKeyPress = $true }
            'V' { Show-VpnPage; $e.SuppressKeyPress = $true }
            'M' { Show-ModsPage; $e.SuppressKeyPress = $true }
            'T' { Show-SettingsPage; $e.SuppressKeyPress = $true }
            'G' { Show-GuidePage; $e.SuppressKeyPress = $true }
            'D' { Run-Diagnose; $e.SuppressKeyPress = $true }
            'C' { Copy-ConnectionLine; $e.SuppressKeyPress = $true }
        }
    }
})

# ---------------------------------------------------------------------------------------
# WINDOW CLOSING (stop the server cleanly, then close)
# ---------------------------------------------------------------------------------------
$script:Form.Add_FormClosing({
    param($s, $e)
    if ($script:AllowClose) { return }
    if ($script:State.Running) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            'The server is still running. Stopping it now and closing the app?',
            'K BNG M Hoster', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($r -ne 'Yes') { $e.Cancel = $true; return }
        $script:State.StopRequested = $true
        Stop-Process -Name 'BeamMP-Launcher' -ErrorAction SilentlyContinue
        Stop-Process -Name 'BeamMP-Server' -ErrorAction SilentlyContinue
        $script:ClosingAfterStop = $true
        $e.Cancel = $true
        Add-Log "[INFO] Stopping the server, then closing..."
        $script:Form.Text = 'K BNG M Hoster - stopping the server...'
        return
    }
    if (Get-Process -Name 'BeamMP-Server' -ErrorAction SilentlyContinue) {
        Stop-Process -Name 'BeamMP-Server' -ErrorAction SilentlyContinue
    }
})

$script:Form.Add_Shown({
    if ($Setup) {
        $null = Show-KeySetupDialog $script:Form
        Show-DashboardPage
    } elseif ($Help) {
        Show-GuidePage
    } elseif ($Fix) {
        Show-FixPage
    } elseif ($Mods) {
        Show-ModsPage
    } else {
        Show-DashboardPage
    }
    Layout-Chrome
    Set-Round $script:Form 12
    if ($script:PageLayout) { & $script:PageLayout }
})

# ---------------------------------------------------------------------------------------
# STARTUP
# ---------------------------------------------------------------------------------------
$logDir = $script:ServerDir + 'Logs'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
Write-Log "===== Launcher started (GUI) ====="

try {
    if (-not (Show-EulaDialog)) { exit 0 }

    [void][System.Windows.Forms.Application]::Run($script:Form)
} catch {
    try {
        [System.Windows.Forms.MessageBox]::Show(
            "K BNG M Hoster hit an unexpected error:`n`n$($_.Exception.Message)",
            'K BNG M Hoster', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } catch { }
}

if ($script:SessionPs) {
    try { $script:SessionPs.Dispose() } catch { }
}
exit 0


