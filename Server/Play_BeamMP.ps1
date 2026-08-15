# ========================================================================================
# K BNG M Hoster v0.6.5 - Simplest Edition (GUI)
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
    ToolUpdate    = $null
    ToolUpdateReady = $null
    ToolUpdateErr = ''
}
$script:AppVersion = '0.6.5'
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
$script:RestartAfterStop = $false
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
            Lines  = [int][math]::Max(1, [math]::Ceiling(($s.Height / [math]::Max(1, $Font.Height)) - 0.1))
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
    foreach ($b in @($script:BtnFix, $script:BtnVpn, $script:BtnMods, $script:BtnSettings, $script:BtnClean, $script:TileFix, $script:TileVpn, $script:TileMods, $script:TileSettings)) {
        if ($b) { $b.Enabled = -not $busy }
    }
}

# ---------------------------------------------------------------------------------------
# MAIN FORM
# ---------------------------------------------------------------------------------------
$script:Form = New-Object System.Windows.Forms.Form
$script:Form.Text = 'K BNG M Hoster v0.6.5 - by Kinan (@raed713)'
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
$header.Height = 66
$header.BackColor = $C.panel
$title = New-Lbl 'K BNG M Hoster' ([System.Drawing.Color]::White) 19 34 $true
$title.AutoSize = $false
$title.Size = New-Object System.Drawing.Size(240, 34)
$title.Location = New-Object System.Drawing.Point(16, 6)
$script:LblSubtitle = New-Lbl 'v0.6.5  ·  Update 6 - Fix 5  ·  by Kinan  ·  Discord: @raed713' $C.dim 9 18
$script:LblSubtitle.Location = New-Object System.Drawing.Point(17, 46)
$script:LblVersionChip = New-Object System.Windows.Forms.Panel
$script:LblVersionChip.BackColor = [System.Drawing.Color]::FromArgb(52, 52, 58)
$script:LblVersionChip.Size = New-Object System.Drawing.Size(112, 34)
$script:LblVersionChip.Location = New-Object System.Drawing.Point(($script:Form.ClientSize.Width - 128), 16)
$chipText = New-Lbl 'v0.6.5' $C.blue 10 20 $true
$chipText.AutoSize = $false
$chipText.Width = 112
$chipText.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$chipText.Location = New-Object System.Drawing.Point(0, 7)
$script:LblVersionChip.Controls.Add($chipText)
Set-Round $script:LblVersionChip 10
$header.Controls.Add($title)
$header.Controls.Add($script:LblSubtitle)
$header.Controls.Add($script:LblVersionChip)

# ---------------- Toolbar ----------------
$toolbar = New-Object System.Windows.Forms.Panel
$toolbar.Dock = 'Top'
$toolbar.Height = 52
$toolbar.BackColor = $C.bg
$toolbar.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 4)

$script:BtnHome = New-Btn '&Home' 'The main page: server status, quick actions and the addresses your friends use to join. (Ctrl+H)' { Show-HomePage }

$script:BtnStart = New-Btn '&Start Server' 'Start the BeamMP server and open the launcher. Friends join via the addresses shown on the home page. (Ctrl+S)' { Start-ServerFlow }
$script:BtnStart.BackColor = [System.Drawing.Color]::FromArgb(35, 100, 60)
$script:BtnStart.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(63, 185, 80)
$script:BtnStart.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Bold)

$script:BtnStop = New-Btn 'Sto&p' 'Stop the running server. Closing the launcher window also stops it. (Ctrl+X)' { Stop-ServerFlow }
$script:BtnStop.Enabled = $false

$script:BtnFix = New-Btn '&Fix Problems' 'Scan your setup and repair common issues (key, port, firewall, CGNAT, VPN). (Ctrl+F)' { Show-FixPage }

$script:BtnVpn = New-Btn '&VPN Manager' 'Radmin VPN / Hamachi / ZeroTier / Tailscale: start or download them, see their IPs. Needed when port forwarding can''t work (CGNAT). (Ctrl+V)' { Show-VpnPage }

$script:BtnMods = New-Btn '&Mods' 'Manage your mods (Resources\Client): enable, disable, scan for suspicious files. (Ctrl+M)' { Show-ModsPage }

$script:BtnSettings = New-Btn 'Se&ttings' 'Server name, max players, port, IP lock, server key, public/private. (Ctrl+T)' { Show-SettingsPage }

$script:BtnClean = New-Btn 'C&lean Info' 'Remove personal/runtime files (key, logs, webhook, IP files) so the folder is safe to zip and share.' { Run-CleanFlow }
$script:BtnClean.BackColor = [System.Drawing.Color]::FromArgb(122, 26, 26)
$script:BtnClean.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(158, 34, 34)
$script:BtnClean.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(220, 60, 60)
$script:BtnClean.ForeColor = [System.Drawing.Color]::White

$btnOpen = New-Btn '&Open Folder' 'Open the K BNG M Hoster folder in Explorer.' { Start-Process explorer.exe -ArgumentList ('"' + $script:AppDir + '"') }

$script:BtnGuide = New-Btn '&Guide' 'How everything works, step by step - the whole README inside the app. (Ctrl+G)' { Show-GuidePage }

# Design-time geometry for every chrome control (scaled on every resize).
$script:ChromeSpecs = @(
    @{ Btn = $script:BtnHome;     X = 10;  Y = 6; W = 66;  H = 38 },
    @{ Btn = $script:BtnStart;    X = 80;  Y = 6; W = 112; H = 38 },
    @{ Btn = $script:BtnStop;     X = 196; Y = 6; W = 60;  H = 38 },
    @{ Btn = $script:BtnFix;      X = 260; Y = 6; W = 102; H = 38 },
    @{ Btn = $script:BtnVpn;      X = 366; Y = 6; W = 108; H = 38 },
    @{ Btn = $script:BtnMods;     X = 478; Y = 6; W = 60;  H = 38 },
    @{ Btn = $script:BtnSettings; X = 542; Y = 6; W = 80;  H = 38 },
    @{ Btn = $script:BtnClean;    X = 626; Y = 6; W = 88;  H = 38 },
    @{ Btn = $btnOpen;            X = 718; Y = 6; W = 102; H = 38 },
    @{ Btn = $script:BtnGuide;    X = 824; Y = 6; W = 78;  H = 38 }
)
$script:ChromeReady = $false

foreach ($b in @($script:BtnHome, $script:BtnStart, $script:BtnStop, $script:BtnFix, $script:BtnVpn, $script:BtnMods, $script:BtnSettings, $script:BtnClean, $btnOpen, $script:BtnGuide)) { $toolbar.Controls.Add($b) }

# Re-layout the fixed chrome (header / toolbar / status bar / log panel) to the window size.
function Layout-Chrome {
    if (-not $script:ChromeReady -or -not $script:Form) { return }
    try {
        $w = $script:Form.ClientSize.Width
        $c = $script:Chrome
        $c.Header.Height = 66
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
        if ($script:LblVersionChip) {
            $script:LblVersionChip.Location = New-Object System.Drawing.Point(($w - (SX 128)), (SY 16))
        }
        $c.LblShortcuts.Width = $w - (SX 150)
        $c.LblPlayers.Width = SX 120
        $px = $w - (SX 130)
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
$script:LblShortcuts = New-Lbl 'Ctrl+H Home | Ctrl+S Start | Ctrl+X Stop | Ctrl+F Fix | Ctrl+V VPN | Ctrl+M Mods | Ctrl+T Settings | Ctrl+G Guide' $C.dim 8 20
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
# The layout runs via BeginInvoke (after the window finishes its new size - this
# fixes the stale layout when maximizing/fullscreen) and is coalesced so rapid
# drag-resizes only queue one pass. The rounded window region is skipped while
# maximized (a region on a maximized window fights the window manager and can
# leave the layout stale on the first fullscreen).
$script:LayoutPending = $false
$script:DoRelayout = {
    $script:LayoutPending = $false
    Layout-Chrome
    if ($script:PageLayout) { & $script:PageLayout }
}
$script:Form.Add_Resize({
    try {
        if ($script:Form.WindowState -ne 'Maximized') { Set-Round $script:Form 12 }
        if (-not $script:LayoutPending) {
            $script:LayoutPending = $true
            [void]$script:Form.BeginInvoke([System.Windows.Forms.MethodInvoker]$script:DoRelayout)
        }
    } catch { Write-Log "[LAYOUT-ERROR] $($_.Exception.Message)" }
})
$script:Form.Add_SizeChanged({
    try {
        if (-not $script:LayoutPending) {
            $script:LayoutPending = $true
            [void]$script:Form.BeginInvoke([System.Windows.Forms.MethodInvoker]$script:DoRelayout)
        }
    } catch { Write-Log "[LAYOUT-ERROR] SIZECHANGED $($_.Exception.Message)" }
})

# ---------------- Content pages ----------------
function Show-HomePage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $C.bg

    $script:ConnCard = New-Object System.Windows.Forms.Panel
    $script:ConnCard.Dock = 'Fill'
    $script:ConnCard.BackColor = $C.bg
    $script:ConnCard.AutoScroll = $true

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

    # Quick-action tiles (the homescreen hub).
    $script:HomeTiles = New-Object System.Windows.Forms.Panel
    $script:HomeTiles.Dock = 'Top'
    $script:HomeTiles.Height = 140
    $script:HomeTiles.BackColor = $C.bg
    $tileHead = New-Lbl 'Quick actions' $C.blue 11 22 $true
    $tileHead.Location = New-Object System.Drawing.Point(16, 4)
    $script:HomeTiles.Controls.Add($tileHead)
    $script:TileStart = New-Btn 'Start Server' 'Start the BeamMP server and open the launcher. (Ctrl+S)' { Start-ServerFlow }
    $script:TileStart.BackColor = [System.Drawing.Color]::FromArgb(35, 100, 60)
    $script:TileStart.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(63, 185, 80)
    $script:TileStart.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $script:TileFix = New-Btn 'Fix Problems' 'Scan your setup and repair common issues. (Ctrl+F)' { Show-FixPage }
    $script:TileVpn = New-Btn 'VPN Manager' 'Start or download a VPN when port forwarding cannot work. (Ctrl+V)' { Show-VpnPage }
    $script:TileMods = New-Btn 'Mods' 'Manage mods, enable/disable, security scan. (Ctrl+M)' { Show-ModsPage }
    $script:TileSettings = New-Btn 'Settings' 'Name, players, port, key, map, public/private. (Ctrl+T)' { Show-SettingsPage }
    $script:TileGuide = New-Btn 'Guide' 'Everything explained step by step. (Ctrl+G)' { Show-GuidePage }
    foreach ($t in @($script:TileStart, $script:TileFix, $script:TileVpn, $script:TileMods, $script:TileSettings, $script:TileGuide)) { $script:HomeTiles.Controls.Add($t) }

    $p.Controls.Add($script:ConnCard)
    $p.Controls.Add($script:HomeTiles)
    $p.Controls.Add($script:StatusCard)
    $script:Content.Controls.Add($p)
    $script:PageLayout = { Layout-Home }
    Refresh-Dashboard
}

function Layout-Home {
    if (-not $script:ConnCard) { return }
    if ($script:ConnCard.ClientSize.Width -le 0 -or $script:ConnCard.ClientSize.Height -le 0) { return }
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
        $scw = $script:StatusCard.ClientSize.Width - 32
        $script:LblServerMeta.AutoSize = $false
        $script:LblServerMeta.Width = $scw
        $mMeta = Measure-Text $script:LblServerMeta.Text $script:LblServerMeta.Font $scw
        $metaH = [int][math]::Max(20, $mMeta.Lines * 20 + 4)
        $script:LblServerMeta.Height = $metaH
        $script:LblServerMeta.Location = New-Object System.Drawing.Point(16, (SY 54))
        $badgeY = (SY 54) + $metaH
        $badgeH = 0
        if ($script:LblCgnatBadge.Text) {
            $script:LblCgnatBadge.AutoSize = $false
            $script:LblCgnatBadge.Width = $scw
            $mB = Measure-Text $script:LblCgnatBadge.Text $script:LblCgnatBadge.Font $scw
            $badgeH = [int]($mB.Lines * 20 + 4)
            $script:LblCgnatBadge.Height = $badgeH
            $script:LblCgnatBadge.Location = New-Object System.Drawing.Point(16, $badgeY)
        }
        $script:StatusCard.Height = [int][math]::Max((SY 104), ($badgeY + $badgeH + 8))
        Set-Round $script:StatusCard 10
        $sw = $script:StatusCard.ClientSize.Width - 336
        $script:LblStatusHint.Width = $sw
        $hx = SX 320
        $hy = SY 14
        $hh = $script:StatusCard.ClientSize.Height - 28
        $script:LblStatusHint.Location = New-Object System.Drawing.Point($hx, $hy)
        $script:LblStatusHint.Height = $hh

        # Quick-action tiles: 3 per row, two rows, grow with the window.
        if ($script:HomeTiles) {
            $tw = $script:HomeTiles.ClientSize.Width
            $tileW = if ($tw -gt 56) { [int][math]::Max(120, ((($tw - 32) - 24) / 3)) } else { (SX 300) }
            $tiles = @($script:TileStart, $script:TileFix, $script:TileVpn, $script:TileMods, $script:TileSettings, $script:TileGuide)
            for ($i = 0; $i -lt $tiles.Count; $i++) {
                $col = $i % 3
                $row = [int][math]::Floor($i / 3)
                $tiles[$i].Size = New-Object System.Drawing.Size($tileW, 44)
                $tiles[$i].Location = New-Object System.Drawing.Point((16 + $col * ($tileW + 12)), (28 + $row * 52))
                Set-Round $tiles[$i] 9
            }
            $script:HomeTiles.Height = 140
        }
    } catch { Write-Log "[LAYOUT-ERROR] HOME $($_.Exception.Message)" }
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
    $isPrivate = Get-ServerPrivate
    $privNote = if ($isPrivate) { '    (private - hidden from the server list - send the address to your friends)' } else { '' }
    $script:LblConnPub.Text = if ($conn -and $conn.Public) { "Anyone (internet):        $($conn.Public)  :  $port$privNote" } else { 'Anyone (internet):        (public IP not detected)' }
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
    Layout-Home
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
    $btnScan.Tag = @{ X = 4; Y = 54; W = 160; H = 34 }
    $script:FixTop.Controls.Add($btnScan)

    $btnUpnp = New-Btn 'Open port on router via UPnP' 'Ask the router to forward the server port (TCP+UDP) automatically - no admin needed.' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$port = Get-ServerPort`nif (Add-UpnpPortForward `$port) { Say ""UPnP: port `$port (TCP+UDP) forwarded on the router. Friends can now connect!"" } else { Say ""UPnP failed. Enable UPnP in your router settings, or forward port `$port (TCP+UDP) manually."" }" 'upnp' }
    $btnUpnp.Size = New-Object System.Drawing.Size(210, 34)
    $btnUpnp.Location = New-Object System.Drawing.Point(172, 54)
    $btnUpnp.Tag = @{ X = 172; Y = 54; W = 210; H = 34 }
    $script:FixTop.Controls.Add($btnUpnp)

    $script:BtnFixAll = New-Btn '&Fix all possible' 'One click: frees a busy port, adds the firewall rule, applies a valid map and forwards the port via UPnP. Anything that still needs you (like the server key) is listed in the log.' { Run-FixAll }
    $script:BtnFixAll.Size = New-Object System.Drawing.Size(150, 34)
    $script:BtnFixAll.Location = New-Object System.Drawing.Point(390, 54)
    $script:BtnFixAll.Tag = @{ X = 390; Y = 54; W = 150; H = 34 }
    $script:FixTop.Controls.Add($script:BtnFixAll)

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
    $script:LblFixSummary = New-Lbl 'Scanning... (the first scan takes a few seconds, then it is fast)' $C.dim 10 22
    $script:LblFixSummary.Location = New-Object System.Drawing.Point(4, 4)
    $script:FixRowsPanel.Controls.Add($script:LblFixSummary)
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.FixReport = @(Get-FixReport)" 'fixscan'
}

function Run-FixAll {
    Add-Log "[INFO] Fix all: running the safe automatic fixes..."
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Fix-AllPossible)`n`$State.FixReport = @(Get-FixReport)" 'fixall'
}

function Update-FixRows {
    if (-not $script:FixRowsPanel -or -not $script:State.FixReport) { return }
    foreach ($c in @($script:FixRowsPanel.Controls)) {
        if ($c -ne $script:LblFixSummary) { $script:FixRowsPanel.Controls.Remove($c); $c.Dispose() }
    }
    $script:FixRowRefs = @()
    foreach ($row in $script:State.FixReport) { Add-FixRow $row }
    if ($script:LblFixSummary) {
        $ok = @($script:State.FixReport | Where-Object { $_.Ok }).Count
        $need = @($script:State.FixReport | Where-Object { $_.NeedsAction }).Count
        $total = $script:State.FixReport.Count
        $script:LblFixSummary.Text = "Scan finished: $ok of $total checks OK, $need need attention."
        $script:LblFixSummary.ForeColor = $(if ($need -eq 0) { $C.green } elseif ($ok -gt 0) { $C.yellow } else { $C.red })
    }
    Layout-FixRows
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
        $btn.Font = New-Object System.Drawing.Font('Segoe UI', 9)
        $g = $script:Form.CreateGraphics()
        try { $tw = [int][math]::Ceiling($g.MeasureString($btn.Text, $btn.Font).Width) } finally { $g.Dispose() }
        $btnW = [int][math]::Max(140, [math]::Min(430, $tw + 30))
        $btn.Size = New-Object System.Drawing.Size($btnW, 30)
        $btn.AutoEllipsis = $true
        $btn.Location = New-Object System.Drawing.Point(690, 7)
        $rowPanel.Controls.Add($btn)
    }
    $script:FixRowRefs += @{ Row = $rowPanel; Lbl = $lbl2; Btn = $btn }
    $script:FixRowsPanel.Controls.Add($rowPanel)
}

function Layout-FixRows {
    if (-not $script:FixRowsPanel) { return }
    try {
        $w = $script:FixRowsPanel.ClientSize.Width - 22
        if ($script:LblFixSummary) {
            $script:LblFixSummary.Width = $w
            $m = Measure-Text $script:LblFixSummary.Text $script:LblFixSummary.Font $w
            $script:LblFixSummary.Height = [int][math]::Max(22, $m.Lines * 22)
        }
        if ($script:FixTop) {
            $maxBottom = SY(96)
            foreach ($c in $script:FixTop.Controls) {
                if ($c -is [System.Windows.Forms.Button] -and $c.Tag -is [hashtable] -and $c.Tag.ContainsKey('X')) {
                    $c.Location = New-Object System.Drawing.Point((SX $c.Tag.X), (SY $c.Tag.Y))
                    $c.Size = New-Object System.Drawing.Size((SX $c.Tag.W), (SY $c.Tag.H))
                } elseif ($c -is [System.Windows.Forms.Label] -and $c.Width -gt 400) {
                    $c.Width = $script:FixTop.ClientSize.Width - 8
                    $m = Measure-Text $c.Text $c.Font $c.Width
                    $c.Height = [int][math]::Max(20, $m.Lines * 20)
                    $maxBottom = [int][math]::Max($maxBottom, ($c.Top + $c.Height + 4))
                }
            }
            $script:FixTop.Height = $maxBottom
        }
        foreach ($r in $script:FixRowRefs) {
            $r.Row.Width = $w
            $btnW = if ($r.Btn) { $r.Btn.Width } else { 0 }
            $bxp = $w - $btnW - 12
            $lblW = [int][math]::Max(200, $bxp - 70)
            $r.Lbl.Width = $lblW
            $m = Measure-Text $r.Lbl.Text $r.Lbl.Font $lblW
            $lh = [int]($m.Lines * 20 + 12)
            $rh = [int][math]::Max(44, $lh + 10)
            $r.Row.Height = $rh
            $r.Lbl.Height = $lh
            $ly = [int](($rh - $lh) / 2)
            $r.Lbl.Location = New-Object System.Drawing.Point(54, $ly)
            if ($r.Btn) {
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
        'MAP' { Show-SettingsPage }
        'MODS' { Show-ModsPage }
        'VER' { Start-Process 'https://github.com/BeamMP/BeamMP-Server/releases/latest' }
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
   supported - friends join via the VPN IP shown on the Home page.

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
    $btnRefresh.Tag = @{ X = 4; Y = 76; W = 90; H = 32 }
    $script:VpnTop.Controls.Add($btnRefresh)

    $btnAll = New-Btn '&Start all installed VPNs' 'Start every VPN that is installed on this PC.' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$started = 0`nforeach (`$app in Get-InstalledVpns | Where-Object { `$_.Installed -and `$_.Exe }) { `$r = Start-OrDownload-Vpn `$app 6; Say `$r; if (`$r -match 'connected') { `$started++ } }`nif (`$started -eq 0) { Say ""No VPN could be started. Install one first (see the rows below) and try again."" }`n`$State.VpnRefresh = (Get-Date).ToString('o')" 'vpns' }
    $btnAll.Size = New-Object System.Drawing.Size(150, 32)
    $btnAll.Location = New-Object System.Drawing.Point(100, 76)
    $btnAll.Tag = @{ X = 100; Y = 76; W = 150; H = 32 }
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
            $maxBottom = SY(110)
            foreach ($c in $script:VpnTop.Controls) {
                if ($c -is [System.Windows.Forms.Button] -and $c.Tag -is [hashtable] -and $c.Tag.ContainsKey('X')) {
                    $c.Location = New-Object System.Drawing.Point((SX $c.Tag.X), (SY $c.Tag.Y))
                    $c.Size = New-Object System.Drawing.Size((SX $c.Tag.W), (SY $c.Tag.H))
                } elseif ($c -is [System.Windows.Forms.Label] -and $c.Width -gt 400) {
                    $c.Width = $script:VpnTop.ClientSize.Width - 8
                    $m = Measure-Text $c.Text $c.Font $c.Width
                    $c.Height = [int][math]::Max(20, $m.Lines * 20)
                    $maxBottom = [int][math]::Max($maxBottom, ($c.Top + $c.Height + 4))
                }
            }
            $script:VpnTop.Height = $maxBottom
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
        if ($script:VpnNote) {
            $script:VpnNote.Width = $w
            $m = Measure-Text $script:VpnNote.Text $script:VpnNote.Font $w
            $script:VpnNote.Height = [int][math]::Max(30, $m.Lines * 18 + 6)
        }
    } catch { Write-Log "[LAYOUT-ERROR] VPNROWS $($_.Exception.Message)" }
}

# Makes a control accept dropped .zip mod files (green highlight while dragging).
function Add-DropTarget($Ctrl) {
    $Ctrl.AllowDrop = $true
    $Ctrl.Add_DragEnter({
        param($s, $e)
        $s.Tag = $s.BackColor
        if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            $files = @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))
            if ($files | Where-Object { $_.ToLower().EndsWith('.zip') }) {
                $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
                $s.BackColor = [System.Drawing.Color]::FromArgb(42, 88, 52)
            } else {
                $e.Effect = [System.Windows.Forms.DragDropEffects]::None
                $s.BackColor = $s.Tag
            }
        } else {
            $e.Effect = [System.Windows.Forms.DragDropEffects]::None
            $s.BackColor = $s.Tag
        }
    })
    $Ctrl.Add_DragLeave({ param($s, $e) if ($s.Tag) { $s.BackColor = $s.Tag } })
    $Ctrl.Add_DragDrop({
        param($s, $e)
        if ($s.Tag) { $s.BackColor = $s.Tag }
        if (-not $e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { return }
        $files = @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)) | Where-Object { $_.ToLower().EndsWith('.zip') }
        if (-not $files.Count) { return }
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $clientDir = $script:RootDir + 'Resources\Client'
        if (-not (Test-Path -LiteralPath $clientDir)) { New-Item -ItemType Directory -Path $clientDir -Force | Out-Null }
        $quar = $script:ServerDir + 'Quarantine'
        $added = 0
        $bad = 0
        foreach ($f in $files) {
            $name = Split-Path $f -Leaf
            try {
                $suspicious = $false
                $arc = [System.IO.Compression.ZipFile]::OpenRead($f)
                try {
                    foreach ($en in $arc.Entries) { if ($en.FullName -match '\.(exe|vbs|cmd|scr|pif)$') { $suspicious = $true; break } }
                } finally { $arc.Dispose() }
                if ($suspicious) {
                    if (-not (Test-Path -LiteralPath $quar)) { New-Item -ItemType Directory -Path $quar -Force | Out-Null }
                    Move-Item -LiteralPath $f -Destination (Join-Path $quar $name) -Force
                    $bad++
                    Add-Log "[SECURITY] $name contains an executable - moved to Quarantine, not added."
                } else {
                    $dest = Join-Path $clientDir $name
                    $replaced = Test-Path -LiteralPath $dest
                    Copy-Item -LiteralPath $f -Destination $dest -Force
                    $added++
                    Add-Log "[INFO] Mod added: $name$(if ($replaced) { ' (replaced an existing file)' })"
                }
            } catch { Add-Log "[ERROR] Could not add $name : $($_.Exception.Message)" }
        }
        Show-ModsPage
        if ($bad -gt 0) {
            [System.Windows.Forms.MessageBox]::Show("Added $added mod(s). $bad file(s) contained executables and were moved to Quarantine.", 'Mods', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        } elseif ($added -gt 0) {
            Add-Log "[INFO] $added mod(s) added to Resources\Client."
        }
    })
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
    $script:ListEnabled.SelectionMode = 'MultiExtended'
    $script:ListEnabled.Add_KeyDown({
        param($s, $e)
        if ($e.Control -and $e.KeyCode -eq 'A') {
            $s.ClearSelected()
            for ($i = 0; $i -lt $s.Items.Count; $i++) { $s.SetSelected($i, $true) }
            $e.SuppressKeyPress = $true
        }
    })

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
    $script:ListDisabled.SelectionMode = 'MultiExtended'
    $script:ListDisabled.Add_KeyDown({
        param($s, $e)
        if ($e.Control -and $e.KeyCode -eq 'A') {
            $s.ClearSelected()
            for ($i = 0; $i -lt $s.Items.Count; $i++) { $s.SetSelected($i, $true) }
            $e.SuppressKeyPress = $true
        }
    })

    $script:ModsListPanel.Controls.Add($script:ListEnabled)
    $script:ModsListPanel.Controls.Add($script:ListDisabled)
    Add-DropTarget $script:ModsListPanel
    Add-DropTarget $script:ListEnabled
    Add-DropTarget $script:ListDisabled

    $script:ModsTip = New-Lbl 'Tip: Ctrl+click selects mods one by one, Shift+click selects a range, Ctrl+A selects all - like Windows Explorer. Disable / Enable acts on every selected mod.' $C.dim 8.5 18  $false 940
    $script:ModsTip.Dock = 'Bottom'
    $script:ModsTip.Height = 24
    $script:ModsListPanel.Controls.Add($script:ModsTip)

    $script:ModsTop = New-Object System.Windows.Forms.Panel
    $script:ModsTop.Dock = 'Top'
    $script:ModsTop.Height = 96
    $script:ModsTop.BackColor = $C.bg

    $head = New-Lbl 'Mod Manager  -  Resources\Client' $C.blue 14 26 $true
    $head.Location = New-Object System.Drawing.Point(4, 2)
    $script:ModsTop.Controls.Add($head)
    $sub = New-Lbl 'Drop .zip mod files anywhere here to add them (they are scanned for executables first). Disabled mods are moved to Server\Backups\mods and are NOT loaded. .zip mods are synced to everyone who joins automatically.' $C.dim 9 20  $false 940
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

    $btnRefresh = New-Btn '&Refresh list' 'Reload the mod list from disk.' { Refresh-ModListsAsync }
    $btnRefresh.Size = New-Object System.Drawing.Size(110, 32)
    $btnRefresh.Location = New-Object System.Drawing.Point(588, 54)
    $script:ModsTop.Controls.Add($btnRefresh)

    $p.Controls.Add($script:ModsListPanel)
    $p.Controls.Add($script:ModsTop)
    $script:Content.Controls.Add($p)
    $script:PageLayout = { Layout-Mods }
    Populate-ModLists
    if (-not $script:State.ModsInfo) { Refresh-ModListsAsync }
}

function Populate-ModLists {
    if (-not $script:ListEnabled) { return }
    $info = $script:State.ModsInfo
    $script:ListEnabled.Items.Clear()
    $script:ListDisabled.Items.Clear()
    if (-not $info) {
        [void]$script:ListEnabled.Items.Add('(loading mods...)')
        return
    }
    foreach ($f in @($info.Enabled)) { [void]$script:ListEnabled.Items.Add(("{0}  ({1:N1} MB)" -f $f.Name, ($f.Length / 1MB))) }
    foreach ($f in @($info.Disabled)) { [void]$script:ListDisabled.Items.Add($f.Name) }
    Add-Log "[INFO] Mods: $(@($info.Enabled).Count) enabled, $(@($info.Disabled).Count) disabled."
}

function Refresh-ModListsAsync {
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.ModsInfo = Get-ModsInfo" 'modslist'
}

function Layout-Mods {
    if (-not $script:ModsListPanel) { return }
    try {
        $script:ModsTop.Height = SY(96)
        foreach ($c in $script:ModsTop.Controls) {
            if ($c -is [System.Windows.Forms.Label] -and $c.Width -gt 400) {
                $c.Width = $script:ModsTop.ClientSize.Width - 8
                $m = Measure-Text $c.Text $c.Font $c.Width
                $c.Height = [int][math]::Max(20, $m.Lines * 20)
            }
        }
        $script:ModsTop.Height = [int][math]::Max($script:ModsTop.Height, (SY 86) + 6)
        $w = $script:ModsListPanel.ClientSize.Width
        $h = $script:ModsListPanel.ClientSize.Height
        $tipH = 24
        if ($script:ModsTip) {
            $tm = Measure-Text $script:ModsTip.Text $script:ModsTip.Font $w
            $tipH = [int][math]::Max(24, $tm.Lines * 18 + 4)
            $script:ModsTip.Height = $tipH
        }
        $colW = [int](($w - 10) / 2)
        $listH = [int][math]::Max(60, $h - 32 - $tipH)
        $x2 = $colW + 10
        $script:ListEnabled.Size = New-Object System.Drawing.Size($colW, $listH)
        $script:ListDisabled.Size = New-Object System.Drawing.Size($colW, $listH)
        $script:ListDisabled.Location = New-Object System.Drawing.Point($x2, 24)
        foreach ($c in $script:ModsListPanel.Controls) {
            if ($c -is [System.Windows.Forms.Label] -and $c.AutoSize -and $c.Text -like 'Disabled mods*') { $c.Location = New-Object System.Drawing.Point($x2, 2) }
        }
    } catch { Write-Log "[LAYOUT-ERROR] MODS $($_.Exception.Message)" }
}

function ModAction([string]$Which) {
    $names = @()
    if ($Which -eq 'disable') {
        if ($script:ListEnabled.SelectedItems.Count -lt 1) { Add-Log "[INFO] Select at least one mod in the 'Enabled mods' list first (Ctrl+click / Shift+click for several)."; return }
        foreach ($item in $script:ListEnabled.SelectedItems) {
            $n = [string]$item -replace '\s+\(\d[\d.,]*\s*MB\)\s*$', ''
            if ($n) { $names += $n }
        }
    } else {
        if ($script:ListDisabled.SelectedItems.Count -lt 1) { Add-Log "[INFO] Select at least one mod in the 'Disabled mods' list first (Ctrl+click / Shift+click for several)."; return }
        foreach ($item in $script:ListDisabled.SelectedItems) { $names += [string]$item }
    }
    if (-not $names.Count) { Add-Log "[INFO] No mod selected."; return }
    $argStr = ($names | ForEach-Object { QStr $_ }) -join ', '
    $cmd = if ($Which -eq 'disable') { 'Disable-Mod' } else { 'Enable-Mod' }
    Add-Log "[INFO] Applying to $($names.Count) mod(s)..."
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nforeach (`$n in @($argStr)) { Say ($cmd -Name `$n) }`n`$State.ModsRefresh = (Get-Date).ToString('o')" 'mods'
}

function Show-SettingsPage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $C.bg
    $p.AutoScroll = $true

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

    $script:LblSettings5 = New-Lbl 'Map (what everyone plays on) - it applies on the next server start:' $C.dim 9.5 20  $false 600
    $script:LblSettings5.Location = New-Object System.Drawing.Point(8, 440)
    $p.Controls.Add($script:LblSettings5)
    $script:CmbMaps = New-Object System.Windows.Forms.ComboBox
    $script:CmbMaps.DropDownStyle = 'DropDownList'
    $script:CmbMaps.Location = New-Object System.Drawing.Point(8, 464)
    $script:CmbMaps.Size = New-Object System.Drawing.Size(380, 26)
    $script:CmbMaps.BackColor = $C.panel
    $script:CmbMaps.ForeColor = [System.Drawing.Color]::White
    $script:CmbMaps.FlatStyle = 'Flat'
    $script:CmbMaps.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $p.Controls.Add($script:CmbMaps)
    $script:BtnApplyMap = New-Btn '&Apply map' 'Set the chosen map on the server. Map mods are sent to players automatically when they join. If the server is running it restarts to apply the map.' { Apply-MapSelection }
    $script:BtnApplyMap.Size = New-Object System.Drawing.Size(110, 32)
    $script:BtnApplyMap.Location = New-Object System.Drawing.Point(8, 496)
    $p.Controls.Add($script:BtnApplyMap)
    $script:BtnScanMaps = New-Btn '&Scan maps' 'Re-scan the game and mod folders for maps (do this after installing a new map).' { Refresh-MapCombo $true }
    $script:BtnScanMaps.Size = New-Object System.Drawing.Size(110, 32)
    $script:BtnScanMaps.Location = New-Object System.Drawing.Point(124, 496)
    $p.Controls.Add($script:BtnScanMaps)

    $script:LblSettings6 = New-Lbl 'Server visibility (who can find it in the BeamMP list):' $C.dim 9.5 20  $false 600
    $script:LblSettings6.Location = New-Object System.Drawing.Point(8, 544)
    $p.Controls.Add($script:LblSettings6)
    $isPriv = Get-ServerPrivate
    $script:RadioPublic = New-Object System.Windows.Forms.RadioButton
    $script:RadioPublic.Text = 'Public - listed for everyone (strangers can find and join)'
    $script:RadioPublic.ForeColor = [System.Drawing.Color]::White
    $script:RadioPublic.BackColor = $C.bg
    $script:RadioPublic.FlatStyle = 'Flat'
    $script:RadioPublic.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $script:RadioPublic.Location = New-Object System.Drawing.Point(12, 568)
    $script:RadioPublic.Size = New-Object System.Drawing.Size(430, 26)
    $script:RadioPublic.Checked = -not $isPriv
    $p.Controls.Add($script:RadioPublic)
    $script:RadioPrivate = New-Object System.Windows.Forms.RadioButton
    $script:RadioPrivate.Text = 'Private - hidden from the list (only people you send the address to can join)'
    $script:RadioPrivate.ForeColor = [System.Drawing.Color]::White
    $script:RadioPrivate.BackColor = $C.bg
    $script:RadioPrivate.FlatStyle = 'Flat'
    $script:RadioPrivate.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $script:RadioPrivate.Location = New-Object System.Drawing.Point(12, 596)
    $script:RadioPrivate.Size = New-Object System.Drawing.Size(470, 26)
    $script:RadioPrivate.Checked = $isPriv
    $p.Controls.Add($script:RadioPrivate)
    $script:LblSettingsVisHint = New-Lbl 'Private: friends join via Direct Connect using the address shown on the Home page (IP:port). A private server cannot be found through Search.' $C.yellow 9 36  $false 720
    $script:LblSettingsVisHint.Location = New-Object System.Drawing.Point(12, 626)
    $script:LblSettingsVisHint.Width = 720
    $p.Controls.Add($script:LblSettingsVisHint)
    $script:BtnApplyVis = New-Btn '&Apply visibility' 'Save the public/private choice. If the server is running it restarts to apply it.' { Apply-Visibility }
    $script:BtnApplyVis.Size = New-Object System.Drawing.Size(150, 32)
    $script:BtnApplyVis.Location = New-Object System.Drawing.Point(8, 660)
    $p.Controls.Add($script:BtnApplyVis)

    $script:LblSettingsResult = New-Lbl '' $C.green 9.5 40  $false 800
    $script:LblSettingsResult.Location = New-Object System.Drawing.Point(8, 700)
    $p.Controls.Add($script:LblSettingsResult)

    $script:Content.Controls.Add($p)
    $script:PageLayout = { Layout-Settings }
    Refresh-MapCombo
}

function Refresh-MapCombo([bool]$ForceRescan = $false) {
    if (-not $script:CmbMaps) { return }
    if ($ForceRescan -or -not $script:CachedMaps) {
        Add-Log "[INFO] Scanning for maps (game + mod folders)..."
        $script:CachedMaps = @()
        $script:CoreText = "`$script:CorePath = '" + ($script:CorePath -replace "'", "''") + "'`r`n" + (Get-Content -LiteralPath $script:CorePath -Raw)
        $ps = [powershell]::Create()
        $null = $ps.AddScript($script:CoreText)
        $null = $ps.AddScript('Get-AvailableMaps')
        try {
            $script:CachedMaps = @($ps.Invoke())
        } catch { Add-Log "[ERROR] Map scan failed: $($_.Exception.Message)" }
        $ps.Dispose()
    }
    $cur = Get-ServerMap
    $curName = Get-MapNameFromPath $cur
    $script:CmbMaps.Items.Clear()
    $script:MapPlaceholder = $false
    foreach ($m in $script:CachedMaps) {
        $disp = $m.Name + $(if ($m.Kind -eq 'Vanilla') { '   (Vanilla)' } else { '   [MAP MOD]' })
        [void]$script:CmbMaps.Items.Add($disp)
    }
    if ($curName) {
        $idx = -1
        for ($i = 0; $i -lt $script:CachedMaps.Count; $i++) { if ($script:CachedMaps[$i].Name -ieq $curName) { $idx = $i; break } }
        if ($idx -ge 0) { $script:CmbMaps.SelectedIndex = $idx }
        else {
            $script:MapPlaceholder = $true
            [void]$script:CmbMaps.Items.Insert(0, "$curName   (current, not found in scan)")
            $script:CmbMaps.SelectedIndex = 0
        }
    } elseif ($script:CachedMaps.Count) { $script:CmbMaps.SelectedIndex = 0 }
    Add-Log "[INFO] Map scan done - $($script:CachedMaps.Count) map(s) available."
}

function Apply-MapSelection {
    if (-not $script:CmbMaps) { return }
    $idx = $script:CmbMaps.SelectedIndex
    if ($idx -lt 0) { Add-Log "[INFO] Select a map first."; return }
    if ($script:MapPlaceholder -and $idx -eq 0) { Add-Log "[INFO] The current map was not found in the scan - pick another map from the list."; return }
    $map = $script:CachedMaps[$idx]
    if (-not $map) { Add-Log "[INFO] Select a map first."; return }
    $zipArg = ''
    if ($map.Zip) { $zipArg = " -ZipToHost " + (QStr $map.Zip) }
    Add-Log "[INFO] Applying map $($map.Name)..."
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Set-ServerMap -LevelName $(QStr $map.Name)$zipArg)`n`$State.MapRefresh = (Get-Date).ToString('o')" 'setmap'
}

function Apply-Visibility {
    if (-not $script:RadioPrivate) { return }
    $priv = if ($script:RadioPrivate.Checked) { $true } else { $false }
    Add-Log "[INFO] Applying visibility: $(if ($priv) { 'private' } else { 'public' })..."
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Set-ServerVisibility -Private $($priv.ToString().ToLower()))`n`$State.VisRefresh = (Get-Date).ToString('o')" 'setvis'
}

function Layout-Settings {
    if (-not $script:TxtName) { return }
    try {
        $w = $script:Content.ClientSize.Width - 16
        $y36 = SY 36; $y74 = SY 74; $y96 = SY 96; $y130 = SY 130; $y152 = SY 152
        $y188 = SY 188; $y240 = SY 240; $y264 = SY 264; $y316 = SY 316; $y340 = SY 340
        $y390 = SY 390; $y440 = SY 440; $y464 = SY 464; $y496 = SY 496; $y540 = SY 540
        $y544 = SY 544; $y568 = SY 568; $y596 = SY 596; $y626 = SY 626; $y660 = SY 660; $y700 = SY 700
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
        $script:LblSettings5.Location = New-Object System.Drawing.Point(8, $y440)
        $script:LblSettings5.Width = $w
        $cw2 = [int][math]::Min($w, (SX 380))
        $script:CmbMaps.Location = New-Object System.Drawing.Point(8, $y464)
        $script:CmbMaps.Size = New-Object System.Drawing.Size($cw2, 26)
        $script:BtnApplyMap.Location = New-Object System.Drawing.Point(8, $y496)
        $script:BtnScanMaps.Location = New-Object System.Drawing.Point(124, $y496)
        $script:LblSettings6.Location = New-Object System.Drawing.Point(8, $y544)
        $script:LblSettings6.Width = $w
        $script:RadioPublic.Location = New-Object System.Drawing.Point(12, $y568)
        $script:RadioPrivate.Location = New-Object System.Drawing.Point(12, $y596)
        $script:LblSettingsVisHint.Width = [int][math]::Min($w, (SX 720))
        $script:LblSettingsVisHint.Location = New-Object System.Drawing.Point(12, $y626)
        $script:BtnApplyVis.Location = New-Object System.Drawing.Point(8, $y660)
        $script:LblSettingsResult.Location = New-Object System.Drawing.Point(8, $y700)
        $script:LblSettingsResult.Width = $w
        $m = Measure-Text $script:LblSettingsResult.Text $script:LblSettingsResult.Font $w
        $script:LblSettingsResult.Height = [int][math]::Max(40, $m.Lines * 20 + 6)
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
# TOOL SELF-UPDATE (check GitHub on every open; download + self-install; delete old versions)
# ---------------------------------------------------------------------------------------
function Start-ToolUpdateCheck {
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.ToolUpdate = Get-ToolUpdateInfo -CurrentVersion '$($script:AppVersion)'" 'toolcheck'
}

function Show-UpdateDialog {
    $u = $script:State.ToolUpdate
    if (-not $u) { return }
    $notes = (($u.Notes -replace 'https?://\S+', '[link]') -split "`n" | Where-Object { $_ -match '[A-Za-z0-9]' } | Select-Object -First 6) -join "`n"
    $msg = "A new version of K BNG M Hoster is available:  $($u.Tag)`n`nWhat's new (short):`n$notes`n`nDownload and install it now?`n(Your key, mods and settings are kept - old downloaded versions are deleted automatically.)"
    $r = [System.Windows.Forms.MessageBox]::Show($msg, 'K BNG M Hoster - update available', [System.Windows.Forms.MessageBoxButtons]::YesNoCancel, [System.Windows.Forms.MessageBoxIcon]::Information)
    if ($r -eq 'Yes') {
        Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay ""Downloading the update, one moment...""`ntry { `$State.ToolUpdateReady = Invoke-ToolDownload -Tag '$($u.Tag)' -ZipUrl '$($u.ZipUrl)' -ZipName '$($u.ZipName)' } catch { `$State.ToolUpdateErr = `$_.Exception.Message }" 'toolupdate'
    } elseif ($r -eq 'No') {
        Start-Process $u.Url
        Add-Log "[INFO] Update page opened in your browser."
    } else {
        Add-Log "[INFO] Update skipped - I will ask again next time."
    }
}

function Ask-ApplyUpdate {
    $staging = $script:State.ToolUpdateReady
    if (-not $staging -or -not (Test-Path -LiteralPath $staging)) { Add-Log '[INFO] The downloaded update is gone - I will re-check next time.'; return }
    $tag = $script:State.ToolUpdate.Tag
    $r = [System.Windows.Forms.MessageBox]::Show(
        "The update ($tag) is downloaded and ready.`n`nClose the app now - the new version installs itself and starts again automatically (about 10 seconds).",
        'K BNG M Hoster - update ready', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($r -ne 'Yes') { Add-Log '[INFO] Update not applied yet - I will ask again next time.'; return }
    $updates = $script:ServerDir + 'Backups\updates'
    if (-not (Test-Path -LiteralPath $updates)) { New-Item -ItemType Directory -Path $updates -Force | Out-Null }
    $updaterPath = Join-Path $updates 'apply_update.ps1'
    $tpl = @'
$ErrorActionPreference = 'Stop'
$log = '__SRV__Logs\updater.log'
function WLog([string]$m) { try { Add-Content -LiteralPath $log -Value ((Get-Date -Format 'HH:mm:ss') + '  ' + $m) } catch { } }
try {
    WLog 'Updater started.'
    for ($i = 0; $i -lt 40 -and (Get-Process -Id __PID__ -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
    Start-Sleep -Seconds 2
    foreach ($n in 'BeamMP-Server', 'BeamMP-Launcher') { for ($i = 0; $i -lt 20 -and (Get-Process -Name $n -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 } }
    WLog 'Old app is closed. Copying the new files...'
    $src = '__STAGE__'
    $appDir = '__APP__'
    $srv = '__SRV__'
    $skip = @('ServerConfig.toml', '.env', 'webhook.txt', 'staticip.cfg', 'Launcher.cfg', 'Server.log', 'Resources', 'Logs', 'Backups', 'Quarantine')
    foreach ($item in Get-ChildItem -LiteralPath (Join-Path $src 'Server') -Force) {
        if ($skip -contains $item.Name) { WLog ('Kept your ' + $item.Name + '.'); continue }
        $dst = Join-Path $srv $item.Name
        for ($try = 0; $try -lt 10; $try++) {
            try { Copy-Item -LiteralPath $item.FullName -Destination $dst -Recurse -Force -ErrorAction Stop; break }
            catch { if ($try -eq 9) { throw }; Start-Sleep -Seconds 1 }
        }
        WLog ('Updated ' + $item.Name + '.')
    }
    Copy-Item -LiteralPath (Join-Path $src 'Start_Here.bat') -Destination (Join-Path $appDir 'Start_Here.bat') -Force
    WLog 'Updated Start_Here.bat.'
    $updates = '__SRV__Backups\updates'
    Get-ChildItem -LiteralPath $updates -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '__TAG__' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $updates -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '__ZIP__' -and $_.Name -ne 'apply_update.ps1' } | Remove-Item -Force -ErrorAction SilentlyContinue
    WLog 'Old versions deleted.'
    WLog 'Done. Relaunching the app...'
    Start-Process -FilePath (Join-Path $appDir 'Start_Here.bat') -WorkingDirectory $appDir
    exit 0
} catch {
    WLog ('FAILED: ' + $_.Exception.Message)
    WLog 'The update did not finish - run Start_Here.bat again and retry the update.'
    exit 1
}
'@
    $updater = $tpl.Replace('__PID__', "$PID").Replace('__APP__', $script:AppDir).Replace('__SRV__', $script:ServerDir).Replace('__STAGE__', $staging).Replace('__TAG__', $tag).Replace('__ZIP__', $script:State.ToolUpdate.ZipName)
    Set-Content -LiteralPath $updaterPath -Value $updater -Encoding UTF8
    Add-Log '[INFO] Applying the update - the app closes now and restarts itself.'
    Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $updaterPath + '"') -WindowStyle Hidden
    $script:AllowClose = $true
    $script:Form.Close()
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
            'fixscan' { Update-FixRows }
            'fixall' {
                Update-FixRows
                Add-Log "[INFO] Fix all finished. Anything still listed needs your action (see the row buttons)."
            }
            'diag' { Show-DiagResult }
            'vpn' { Refresh-VpnRows }
            'vpns' { Refresh-VpnRows }
            'mods' { Refresh-ModListsAsync }
            'modscan' { Refresh-ModListsAsync }
            'modslist' { Populate-ModLists }
            'settings' { $script:LblSettingsResult.Text = 'Settings saved.'; $script:LblSettingsResult.ForeColor = $C.green }
            'update' { $script:LblSettingsResult.Text = $(if ($script:State.UpdateMsg) { "Update available: $($script:State.UpdateMsg)" } else { 'Checked.' }); $script:LblSettingsResult.ForeColor = $C.green }
            'setmap' {
                if ($script:LblSettingsResult) { $script:LblSettingsResult.Text = 'Map applied.'; $script:LblSettingsResult.ForeColor = $C.green }
                if ($script:State.Running) {
                    $r = [System.Windows.Forms.MessageBox]::Show(
                        'The map applies on the next server start. Restart the server now?',
                        'Map changed', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
                    if ($r -eq 'Yes') {
                        Add-Log "[INFO] Restarting the server to apply the new map..."
                        $script:RestartAfterStop = $true
                        Stop-ServerFlow
                    }
                } else {
                    Add-Log "[INFO] Map applied - it will be used on the next server start."
                }
            }
            'setvis' {
                if ($script:LblSettingsResult) { $script:LblSettingsResult.Text = 'Visibility saved.'; $script:LblSettingsResult.ForeColor = $C.green }
                if ($script:RadioPrivate) {
                    $script:RadioPrivate.Checked = Get-ServerPrivate
                    $script:RadioPublic.Checked = -not (Get-ServerPrivate)
                }
                if ($script:State.Running) {
                    $r = [System.Windows.Forms.MessageBox]::Show(
                        'The visibility applies on the next server start. Restart the server now?',
                        'Visibility changed', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
                    if ($r -eq 'Yes') {
                        Add-Log "[INFO] Restarting the server to apply the visibility..."
                        $script:RestartAfterStop = $true
                        Stop-ServerFlow
                    }
                } else {
                    Add-Log "[INFO] Visibility applied - it will be used on the next server start."
                }
                Refresh-Dashboard
            }
            'toolcheck' { if ($script:State.ToolUpdate) { Show-UpdateDialog } }
            'toolupdate' {
                if ($script:State.ToolUpdateReady) { Ask-ApplyUpdate }
                elseif ($script:State.ToolUpdateErr) {
                    [System.Windows.Forms.MessageBox]::Show("Update failed: $($script:State.ToolUpdateErr)", 'K BNG M Hoster - update failed', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
                    $script:State.ToolUpdateErr = ''
                }
            }
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
        } elseif ($script:RestartAfterStop) {
            $script:RestartAfterStop = $false
            Add-Log "[INFO] Restarting the server..."
            Start-ServerFlow
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
function Add-GuideLine([string]$Text, [string]$Color = 'text', [bool]$Bold = $false, [float]$Size = 10, [int]$Indent = -1) {
    if (-not $script:GuideBox) { return }
    if (-not $script:GuideBox.IsHandleCreated) { [void]$script:GuideBox.Handle }
    if ($Indent -lt 0) { $Indent = if ($Bold -and $Size -ge 12) { 0 } else { 24 } }
    $script:GuideBox.SelectionStart = $script:GuideBox.TextLength
    $script:GuideBox.SelectionLength = 0
    $script:GuideBox.SelectionIndent = $Indent
    $script:GuideBox.SelectionRightIndent = 6
    $script:GuideBox.SelectionColor = $C[$Color]
    $script:GuideBox.SelectionFont = New-Object System.Drawing.Font('Segoe UI', $Size, $(if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }))
    $script:GuideBox.AppendText($Text + [Environment]::NewLine)
}

function Show-GuidePage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $C.bg

    $script:GuideHead = New-Lbl 'Guide' $C.blue 16 30 $true
    $script:GuideHead.Location = New-Object System.Drawing.Point(16, 8)
    $p.Controls.Add($script:GuideHead)

    $script:GuideSub = New-Lbl 'Everything you need to know - no files to open. Use the buttons on top to jump between pages.' $C.dim 9 18
    $script:GuideSub.Location = New-Object System.Drawing.Point(16, 40)
    $p.Controls.Add($script:GuideSub)

    # Rounded card with real padding - the text never touches the edges.
    $script:GuideCard = New-Object System.Windows.Forms.Panel
    $script:GuideCard.BackColor = $C.panel
    $script:GuideCard.Padding = New-Object System.Windows.Forms.Padding(22, 16, 22, 16)
    $script:GuideCard.Location = New-Object System.Drawing.Point(14, 64)
    $script:GuideCard.Size = New-Object System.Drawing.Size(960, 420)
    $p.Controls.Add($script:GuideCard)

    $script:GuideBox = New-Object System.Windows.Forms.RichTextBox
    $script:GuideBox.ReadOnly = $true
    $script:GuideBox.DetectUrls = $false
    $script:GuideBox.BackColor = $C.panel
    $script:GuideBox.ForeColor = $C.text
    $script:GuideBox.BorderStyle = 'None'
    $script:GuideBox.WordWrap = $true
    $script:GuideBox.ScrollBars = 'Vertical'
    $script:GuideBox.Dock = 'Fill'
    # Create the handle FIRST with an explicit base font - otherwise the per-line
    # fonts below get rendered at the wrong size (the "broken size" look).
    $script:GuideBox.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    [void]$script:GuideBox.Handle
    $script:GuideBox.ZoomFactor = 1.0
    $script:GuideCard.Controls.Add($script:GuideBox)

    Add-GuideLine 'STEP 1  -  START THE SERVER' 'yellow' $true 12
    Add-GuideLine '  Double-click Start_Here.bat - this window opens, on the HOME'
    Add-GuideLine '  page (Ctrl+H): server status, Quick actions tiles and every'
    Add-GuideLine '  address your friends can use.'
    Add-GuideLine '  First time only: a small window asks for your server key.'
    Add-GuideLine '      1. Get your free key at https://keymaster.beammp.com'
    Add-GuideLine '      2. Paste it and click Save - it is stored privately in Server\.env'
    Add-GuideLine '  Click Start Server (or Ctrl+S). The BeamMP Launcher opens automatically.'
    Add-GuideLine '  In BeamNG: More... -> BeamMP -> Direct Connect, use the address'
    Add-GuideLine '  shown under "THIS PC (test it now)" to test on your own PC.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 2  -  HOW YOUR FRIENDS CONNECT' 'yellow' $true 12
    Add-GuideLine '  Send them ONE line from the Home page. In BeamNG they open'
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
    Add-GuideLine 'STEP 3  -  PUBLIC OR PRIVATE SERVER' 'yellow' $true 12
    Add-GuideLine '  Settings (Ctrl+T) -> "Server visibility": PUBLIC lists your server'
    Add-GuideLine '  for everyone in BeamMP Search. PRIVATE hides it from the list -'
    Add-GuideLine '  only people you send the address to can join, and the Home page'
    Add-GuideLine '  marks the internet line with "(private...)".'
    Add-GuideLine '  Private does NOT add a password - anyone with the address'
    Add-GuideLine '  (IP:port) can still join. It applies on the next server start.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 4  -  CANNOT CONNECT? RUN FIX PROBLEMS' 'yellow' $true 12
    Add-GuideLine '  Click Fix Problems (or Ctrl+F). It checks everything - key, port,'
    Add-GuideLine '  firewall, mods, disk space, VPNs, CGNAT, reachability - and'
    Add-GuideLine '  shows a summary of what is OK and what needs attention.'
    Add-GuideLine '  Press "Fix all possible" for one-click repairs (busy port,'
    Add-GuideLine '  firewall, broken map, UPnP). Anything left needs you -'
    Add-GuideLine '  follow the instructions on each row.'
    Add-GuideLine '  If your ISP uses CGNAT, port forwarding can NEVER work:'
    Add-GuideLine '  use the VPN Manager (Ctrl+V) instead - VPNs bypass CGNAT.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 5  -  MODS' 'yellow' $true 12
    Add-GuideLine '  Click Mods (or Ctrl+M). Drag & drop .zip mod files anywhere on'
    Add-GuideLine '  the page - they are scanned for executables and added for'
    Add-GuideLine '  everyone to download automatically when they join.'
    Add-GuideLine '  Suspicious files (exe, vbs, cmd, scr, pif) are quarantined.'
    Add-GuideLine '  Select several mods at once like in Windows Explorer:'
    Add-GuideLine '  Ctrl+click picks them one by one, Shift+click selects a whole'
    Add-GuideLine '  range, Ctrl+A selects everything - then Disable/Enable acts'
    Add-GuideLine '  on all of them at once.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 6  -  SETTINGS' 'yellow' $true 12
    Add-GuideLine '  Click Settings (or Ctrl+T): server name, max players, free port,'
    Add-GuideLine '  IP lock, your server key, public/private and the MAP everyone'
    Add-GuideLine '  plays on. No config files needed - the GUI saves everything.'
    Add-GuideLine '  Pick a map in Settings and press Apply map - vanilla maps work'
    Add-GuideLine '  instantly, and map MODS you have are sent to players'
    Add-GuideLine '  automatically when they join. The map applies on the next'
    Add-GuideLine '  server start (the tool offers to restart for you).'
    Add-GuideLine '  NEVER change the map from inside the game - it breaks the'
    Add-GuideLine '  multiplayer screen (player list and ping disappear). Always'
    Add-GuideLine '  change it here instead.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 7  -  BEFORE SHARING THE FOLDER' 'yellow' $true 12
    Add-GuideLine '  Click Clean Info (the red button) - it wipes your key, webhook,'
    Add-GuideLine '  logs, backups and IP files so the folder is safe to zip and share.'
    Add-GuideLine '  NEVER share Server\.env or Server\webhook.txt.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 8  -  STUCK? CHECK THE ACTIVITY LOG' 'yellow' $true 12
    Add-GuideLine '  The log at the bottom of the window says exactly what the tool is'
    Add-GuideLine '  doing and why. Every button also explains itself in a tooltip -'
    Add-GuideLine '  hover any button to see what it does.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 9  -  KEEPING THE APP UPDATED' 'yellow' $true 12
    Add-GuideLine '  Every time this window opens, the tool checks GitHub for a new'
    Add-GuideLine '  version. If one exists it offers to download and install it'
    Add-GuideLine '  automatically - your key, mods and settings are kept, and old'
    Add-GuideLine '  downloaded versions are deleted.'
    Add-GuideLine ''

    $script:Content.Controls.Add($p)
    $script:PageLayout = { Layout-Guide }
}

function Layout-Guide {
    if (-not $script:GuideBox) { return }
    try {
        $w = $script:Content.ClientSize.Width
        $h = $script:Content.ClientSize.Height
        if ($w -le 0 -or $h -le 0) { return }
        $script:GuideHead.Location = New-Object System.Drawing.Point((SX 16), (SY 8))
        $script:GuideSub.Location = New-Object System.Drawing.Point((SX 16), (SY 40))
        $script:GuideCard.Location = New-Object System.Drawing.Point((SX 14), (SY 64))
        $script:GuideCard.Size = New-Object System.Drawing.Size(($w - (SX 28)), [int][math]::Max(140, ($h - (SY 78))))
        Set-Round $script:GuideCard 10
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
            'H' { Show-HomePage; $e.SuppressKeyPress = $true }
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
        Show-HomePage
    } elseif ($Help) {
        Show-GuidePage
    } elseif ($Fix) {
        Show-FixPage
    } elseif ($Mods) {
        Show-ModsPage
    } else {
        Show-HomePage
    }
    Layout-Chrome
    Set-Round $script:Form 12
    if ($script:PageLayout) { & $script:PageLayout }
    Start-ToolUpdateCheck
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


