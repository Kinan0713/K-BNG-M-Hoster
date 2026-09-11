# ========================================================================================
# K BNG M Hoster v0.7.0 - Simplest Edition (GUI)
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
    Frp           = ''
    FrpError      = ''
}
$script:AppVersion = '0.7.0'
$script:CorePath = Join-Path $PSScriptRoot 'HosterCore.ps1'
$script:CoreText = "`$script:CorePath = '" + ($script:CorePath -replace "'", "''") + "'`r`n" + (Get-Content -LiteralPath $script:CorePath -Raw)
$script:PendingAction = $null
$script:Busy = $false
# Actions requested while another task runs are QUEUED here (never dropped),
# so toggles and settings always persist even in quick succession.
$script:ActionQueue = New-Object System.Collections.Queue
$script:SuppressSettingEvents = $false
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
$Theme = @{
    bg      = [System.Drawing.Color]::FromArgb(30, 30, 30)
    panel   = [System.Drawing.Color]::FromArgb(37, 37, 40)
    card    = [System.Drawing.Color]::FromArgb(42, 42, 46)
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
    $b.UseMnemonic = $false
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderColor = $Theme.border
    $b.FlatAppearance.MouseOverBackColor = $Theme.btnHov
    $b.BackColor = $Theme.btn
    $b.ForeColor = $Theme.text
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $b.AutoSize = $false
    $b.Width = 96
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
    $l.UseMnemonic = $false
    $l.ForeColor = $Color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.Font = New-Object System.Drawing.Font('Segoe UI', $Size, $(if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }))
    if ($Width) { $l.AutoSize = $false; $l.Width = $Width } else { $l.AutoSize = $true }
    $l.Height = $Height
    return $l
}

# A small "copy this exact text" button. Values are baked into the handler so
# every copy button keeps its OWN text (safe in loops).
function New-CopyButton([string]$Text, [string]$Tip, [string]$CopyValue, [string]$LogText) {
    $safeValue = $CopyValue.Replace("'", "''")
    $safeLog = $LogText.Replace("'", "''")
    $body = "try { [System.Windows.Forms.Clipboard]::SetText('$safeValue'); Add-Log '[OK] Copied: $safeLog' } catch { Add-Log ('[ERROR] Clipboard busy: ' + `$_.Exception.Message) }"
    $sb = [scriptblock]::Create($body)
    $b = New-Btn $Text $Tip $sb
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $b.Height = 28
    return $b
}

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

# Starts one core action in a fresh background runspace (UI never freezes).
function Start-CoreActionImpl([string]$Script, [string]$Tag) {
    $ps = [powershell]::Create()
    $null = $ps.AddScript($script:CoreText)
    $null = $ps.AddScript($Script).AddArgument($script:Queue).AddArgument($script:State)
    $handle = $ps.BeginInvoke()
    $script:Busy = $true
    $script:PendingAction = @{ Ps = $ps; Handle = $handle; Tag = $Tag }
    Update-BusyUi
}

# Public entry: runs now when free, otherwise QUEUES so no action is ever lost.
function Start-CoreAction {
    param([string]$Script, [string]$Tag = 'action')
    if ($script:Busy -or $script:Starting) {
        $script:ActionQueue.Enqueue(@{ Script = $Script; Tag = $Tag })
        return
    }
    Start-CoreActionImpl -Script $Script -Tag $Tag
}

function QStr([string]$Value) {
    return "'" + ($Value -replace "'", "''") + "'"
}

function Update-BusyUi {
    $busy = $script:Busy -or $script:Starting
    if ($script:LicenseLocked) { $busy = $true }
    foreach ($b in @($script:BtnFix, $script:BtnNetwork, $script:BtnMods, $script:BtnSettings, $script:BtnTransfer)) {
        if ($b) { $b.Enabled = -not $busy }
    }
}

function Get-TextWidth([string]$Text, [System.Drawing.Font]$Font) {
    try {
        return [System.Windows.Forms.TextRenderer]::MeasureText($Text, $Font).Width
    } catch { return [int]($Text.Length * 8) }
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

# ---------------------------------------------------------------------------------------
# RESPONSIVE LAYOUT HELPERS
# Every page = docked chrome + scrollable stack of rounded cards. Cards are
# TableLayoutPanels (fixed label column + stretching content column) inside
# auto-sizing panels; everything scales through Dock/Anchor - no pixel math.
# ---------------------------------------------------------------------------------------

# A rounded section card. Returns the card (its .Tag holds the inner TLP).
function New-Card([string]$Title, [string]$Subtitle = '') {
    $card = New-Object System.Windows.Forms.Panel
    $card.BackColor = $Theme.card
    $card.Dock = 'Top'
    $card.AutoSize = $true
    $card.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    # Extra bottom padding = the breathing room between stacked sections
    # (docked controls ignore Margin, so spacing lives in the padding).
    $card.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 26)
    $card.Add_SizeChanged({ Set-Round $this 10 })
    $card.Add_HandleCreated({ Set-Round $this 10 })
    $t = New-Object System.Windows.Forms.TableLayoutPanel
    $t.Dock = 'Fill'
    $t.AutoSize = $true
    $t.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $t.ColumnCount = 2
    $null = $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 270)))
    $null = $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $card.Controls.Add($t)
    $lblT = New-Object System.Windows.Forms.Label
    $lblT.Text = $Title
    $lblT.AutoSize = $true
    $lblT.Anchor = 'Left'
    $lblT.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $lblT.ForeColor = $Theme.blue
    $r = $t.RowCount; $t.RowCount = $r + 1
    $t.Controls.Add($lblT, 0, $r); $t.SetColumnSpan($lblT, 2)
    if ($Subtitle) {
        $lblS = New-Object System.Windows.Forms.Label
        $lblS.Text = $Subtitle
        $lblS.AutoSize = $true; $lblS.Anchor = 'Left'
        $lblS.ForeColor = $Theme.dim
        $lblS.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
        $r = $t.RowCount; $t.RowCount = $r + 1
        $t.Controls.Add($lblS, 0, $r); $t.SetColumnSpan($lblS, 2)
    }
    $card.Tag = $t
    return $card
}

# Label in the fixed column + control stretching in the content column.
function Add-Row($Card, [string]$Label, $Control) {
    $t = $Card.Tag
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Label
    $lbl.AutoSize = $true; $lbl.Anchor = 'Left'
    $lbl.ForeColor = $Theme.dim
    $lbl.Margin = New-Object System.Windows.Forms.Padding(0, 6, 8, 2)
    $Control.Anchor = 'Left,Right'
    $Control.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)
    $r = $t.RowCount; $t.RowCount = $r + 1
    $t.Controls.Add($lbl, 0, $r)
    $t.Controls.Add($Control, 1, $r)
}

# Full-width row (checkbox / wrapped note / button bar). IMPORTANT: the control
# is placed directly with a column span - adding a label next to it corrupts
# the stretch of every following content column.
function Add-RowFull($Card, $Control) {
    $t = $Card.Tag
    $Control.Anchor = 'Left,Right'
    $Control.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)
    $r = $t.RowCount; $t.RowCount = $r + 1
    $t.Controls.Add($Control, 0, $r)
    $t.SetColumnSpan($Control, 2)
}

# Wrapped, multi-line note text.
function Add-RowNote($Card, [string]$Text, [System.Drawing.Color]$Color) {
    $w = New-Object System.Windows.Forms.Label
    $w.Text = $Text
    $w.Dock = 'Fill'
    $w.AutoSize = $true
    $w.ForeColor = $Color
    $w.Font = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $w.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 6)
    Add-RowFull $Card $w
    return $w
}

# Horizontal bar of buttons (or any small controls). The bar has a FIXED height:
# nested auto-size bars inside a card's table made the row height stale, which
# clipped the bar's bottom buttons (the FRP button bar overflowed its card).
# 44px fits any button up to 36px plus the bar's padding. Bars that genuinely
# need to grow (e.g. the Home VPN copy-button flow) override AutoSize.
function New-ButtonBar {
    $fl = New-Object System.Windows.Forms.FlowLayoutPanel
    $fl.AutoSize = $false
    $fl.Height = 44
    $fl.WrapContents = $false
    $fl.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $fl.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
    return $fl
}

# A dark inset text box that fits the card look.
function New-SettingsInput {
    $t = New-Object System.Windows.Forms.TextBox
    $t.BackColor = $Theme.bg
    $t.ForeColor = [System.Drawing.Color]::White
    $t.BorderStyle = 'FixedSingle'
    $t.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    return $t
}

# The scrollable card stack used by every page: body (AutoScroll) > content
# (auto-size, width clamped) > cards (Dock Top). Cards mount in REVERSE order
# because Dock Top stacks bottom-up.
function New-CardStack($Page) {
    $body = New-Object System.Windows.Forms.Panel
    $body.Dock = 'Fill'
    $body.BackColor = $Theme.bg
    $body.AutoScroll = $true
    $content = New-Object System.Windows.Forms.Panel
    $content.Location = New-Object System.Drawing.Point(8, 4)
    $content.Anchor = 'Top,Left,Right'
    $content.AutoSize = $true
    $content.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $content.MinimumSize = New-Object System.Drawing.Size([int][math]::Max(($Page.ClientSize.Width - 16), 200), 0)
    $body.Controls.Add($content)
    # Script-scope references so the resize handler resolves them reliably
    # (function-scope closures would lose $body/$content after the call).
    $script:StackRefs = @{ Body = $body; Content = $content }
    $body.Add_Resize({
        $script:StackRefs.Content.MinimumSize = New-Object System.Drawing.Size([int][math]::Max(($script:StackRefs.Body.ClientSize.Width - 16), 200), 0)
    })
    $Page.Controls.Add($body)
    $script:MountCards = {
        param($CardList, $Content)
        $Content.Controls.Clear()
        for ($i = $CardList.Count - 1; $i -ge 0; $i--) { $Content.Controls.Add($CardList[$i]) }
    }
    return $script:StackRefs
}

# Page header bar: title on the left, actions on the right (right-aligned flow).
# The optional hint becomes a tooltip on the title - a second left-docked label
# pushed the action buttons off-screen on narrow windows.
function New-PageTop($Page, [string]$Title, [string]$Hint = '') {
    $top = New-Object System.Windows.Forms.Panel
    $top.Dock = 'Top'
    $top.Height = 56
    $top.BackColor = $Theme.bg
    $top.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 4)
    $lbl = New-Lbl $Title $Theme.blue 14 26 $true
    $lbl.Dock = 'Left'
    $lbl.Width = 220
    $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    if ($Hint) { $script:Tip.SetToolTip($lbl, $Hint) }
    $top.Controls.Add($lbl)
    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = 'Fill'
    $flow.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $flow.WrapContents = $false
    $flow.Padding = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)
    $top.Controls.Add($flow)
    return @{ Bar = $top; Flow = $flow; Title = $lbl }
}

# ---------------------------------------------------------------------------------------
# MAIN FORM
# ---------------------------------------------------------------------------------------
$script:Form = New-Object System.Windows.Forms.Form
$script:Form.Text = 'K BNG M Hoster v0.7.0 - by Kinan (@raed713)'
$script:Form.Size = New-Object System.Drawing.Size(1000, 720)
$script:Form.MinimumSize = New-Object System.Drawing.Size(960, 660)
$script:Form.StartPosition = 'CenterScreen'
$script:Form.BackColor = $Theme.bg
$script:Form.ForeColor = $Theme.text
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
$header.BackColor = $Theme.panel
$title = New-Lbl 'K BNG M Hoster' ([System.Drawing.Color]::White) 19 34 $true
$title.AutoSize = $false
$title.Size = New-Object System.Drawing.Size(240, 34)
$title.Location = New-Object System.Drawing.Point(16, 6)
$script:LblSubtitle = New-Lbl 'v0.7.0  |  Update 7 - FRP tunnel + Playit.gg  |  by Kinan  |  Discord: @raed713' $Theme.dim 9 18
$script:LblSubtitle.Location = New-Object System.Drawing.Point(17, 44)
$script:LblVersionChip = New-Object System.Windows.Forms.Panel
$script:LblVersionChip.BackColor = [System.Drawing.Color]::FromArgb(52, 52, 58)
$script:LblVersionChip.Size = New-Object System.Drawing.Size(112, 34)
$script:LblVersionChip.Anchor = 'Top,Right'
$script:LblVersionChip.Location = New-Object System.Drawing.Point(0, 16)
$script:LblVersionChip.Margin = New-Object System.Windows.Forms.Padding(0, 0, 14, 0)
$chipText = New-Lbl 'v0.7.0' $Theme.blue 10 20 $true
$chipText.AutoSize = $false
$chipText.Width = 112
$chipText.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$chipText.Location = New-Object System.Drawing.Point(0, 7)
$script:LblVersionChip.Controls.Add($chipText)
Set-Round $script:LblVersionChip 10
$header.Controls.Add($title)
$header.Controls.Add($script:LblSubtitle)
$header.Controls.Add($script:LblVersionChip)
$header.Add_Resize({
    $script:LblVersionChip.Location = New-Object System.Drawing.Point(($header.ClientSize.Width - 128), 16)
})

# ---------------- Toolbar ----------------
$toolbar = New-Object System.Windows.Forms.Panel
$toolbar.Dock = 'Top'
$toolbar.Height = 52
$toolbar.BackColor = $Theme.bg

$toolbarFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$toolbarFlow.Dock = 'Fill'
$toolbarFlow.WrapContents = $false
$toolbarFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$toolbarFlow.Padding = New-Object System.Windows.Forms.Padding(10, 7, 10, 4)
$toolbar.Controls.Add($toolbarFlow)

$script:BtnHome = New-Btn 'Home' 'Server status and the addresses your friends use to join. (Ctrl+H)' { Show-HomePage }
$script:BtnHome.Width = 64
$script:BtnStart = New-Btn 'Start Server' 'Start the BeamMP server and open the launcher. Friends join via the addresses shown on the Home page. (Ctrl+S)' { Start-ServerFlow }
$script:BtnStart.Width = 124
$script:BtnStart.BackColor = [System.Drawing.Color]::FromArgb(35, 100, 60)
$script:BtnStart.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(63, 185, 80)
$script:BtnStart.Font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Bold)
$script:BtnStop = New-Btn 'Stop' 'Stop the running server. Closing the launcher window also stops it. (Ctrl+X)' { Stop-ServerFlow }
$script:BtnStop.Width = 58
$script:BtnStop.Enabled = $false
$script:BtnSettings = New-Btn 'Settings' 'Server name, players, map, visibility, port and your server key - everything in one scroll. (Ctrl+T)' { Show-SettingsPage }
$script:BtnSettings.Width = 84
$script:BtnMods = New-Btn 'Mods' 'Manage your mods: enable, disable, scan for suspicious files. (Ctrl+M)' { Show-ModsPage }
$script:BtnMods.Width = 62
$script:BtnFix = New-Btn 'Fix' 'Scan your setup and repair common issues (key, port, firewall, CGNAT). (Ctrl+F)' { Show-FixPage }
$script:BtnFix.Width = 66
$script:BtnNetwork = New-Btn 'Network' 'FRP tunnel, VPN tools (Radmin / Hamachi / ZeroTier / Tailscale / Playit.gg) and CGNAT help. (Ctrl+V)' { Show-NetworkPage }
$script:BtnNetwork.Width = 88
$script:BtnTransfer = New-Btn 'Transfer' 'Export + split your server mods for cloud upload, install downloaded mods and delete only the ones you pick. (Ctrl+U)' { Show-TransferPage }
$script:BtnTransfer.Width = 84
$script:BtnMore = New-Btn 'More' 'Guide, Extra, Support, Open Folder, Clean Info. (menu)' { Show-MoreMenu }
$script:BtnMore.Width = 74

$script:MoreMenu = New-Object System.Windows.Forms.ContextMenuStrip
$script:MoreMenu.BackColor = $Theme.panel
$script:MoreMenu.ForeColor = $Theme.text
$script:MoreMenu.ShowImageMargin = $false
function Add-MenuItem([string]$Text, [string]$Tip, [scriptblock]$OnClick) {
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem
    $mi.Text = $Text
    $mi.ForeColor = $Theme.text
    $mi.BackColor = $Theme.panel
    if ($Tip) { $mi.ToolTipText = $Tip }
    if ($OnClick) { $mi.Add_Click($OnClick) }
    $script:MoreMenu.Items.Add($mi)
    return $mi
}
Add-MenuItem 'Guide (Ctrl+G)' 'How everything works, step by step - the whole README inside the app.' { Show-GuidePage } | Out-Null
Add-MenuItem 'Extra (Ctrl+E)' 'Open windows (restore them from here), and the one-click "Submit issue" button.' { Show-ExtraPage } | Out-Null
Add-MenuItem 'Support (Discord)' 'Get help with K BNG M Hoster on Discord.' {
    try { Start-Process "https://discord.gg/2Ckw5SgJvw" } catch { Add-Log '[INFO] Could not open Discord link. Please visit: https://discord.gg/2Ckw5SgJvw' }
} | Out-Null
Add-MenuItem 'Open Folder' 'Open the K BNG M Hoster folder in Explorer.' { Start-Process explorer.exe -ArgumentList ('"' + $script:AppDir + '"') } | Out-Null
$miClean = Add-MenuItem 'Clean Info' 'Remove personal/runtime files (key, logs, webhook, IP files) so the folder is safe to zip and share.' { Run-CleanFlow }
$miClean.ForeColor = [System.Drawing.Color]::FromArgb(255, 120, 110)

function Show-MoreMenu {
    $script:MoreMenu.Show($script:BtnMore, (New-Object System.Drawing.Point(0, $script:BtnMore.Height)))
}

$toolbarFlow.Controls.Add($script:BtnHome)
$toolbarFlow.Controls.Add($script:BtnStart)
$toolbarFlow.Controls.Add($script:BtnStop)
$toolbarFlow.Controls.Add($script:BtnSettings)
$toolbarFlow.Controls.Add($script:BtnMods)
$toolbarFlow.Controls.Add($script:BtnFix)
$toolbarFlow.Controls.Add($script:BtnNetwork)
$toolbarFlow.Controls.Add($script:BtnTransfer)
$toolbarFlow.Controls.Add($script:BtnMore)

# ---------------- Status bar ----------------
$statusBar = New-Object System.Windows.Forms.Panel
$statusBar.Dock = 'Bottom'
$statusBar.Height = 26
$statusBar.BackColor = $Theme.panel
$script:LblPlayers = New-Lbl '' $Theme.blue 8.5 20 $true 260
$script:LblPlayers.Dock = 'Right'
$script:LblPlayers.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$script:LblShortcuts = New-Lbl 'Ctrl+H Home | Ctrl+S Start | Ctrl+X Stop | Ctrl+T Settings | Ctrl+M Mods | Ctrl+F Fix | Ctrl+V Network | Ctrl+U Transfer | Ctrl+D Diagnose | Ctrl+C Copy IP | Ctrl+G Guide | Ctrl+E Extra | F11 Fullscreen' $Theme.dim 8 20
$script:LblShortcuts.Dock = 'Fill'
$script:LblShortcuts.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:LblShortcuts.AutoEllipsis = $true
$script:LblShortcuts.Padding = New-Object System.Windows.Forms.Padding(10, 0, 4, 0)
$statusBar.Controls.Add($script:LblShortcuts)
$statusBar.Controls.Add($script:LblPlayers)

# ---------------- Log panel ----------------
$logPanel = New-Object System.Windows.Forms.Panel
$logPanel.Dock = 'Bottom'
$logPanel.Height = 190
$logPanel.BackColor = $Theme.bg
$logHead = New-Object System.Windows.Forms.Panel
$logHead.Dock = 'Top'
$logHead.Height = 28
$logHead.BackColor = $Theme.bg
$logTitle = New-Lbl 'Activity log  (everything the tool does, and why)' $Theme.dim 8.5 20
$logTitle.Dock = 'Fill'
$logTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$logTitle.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
$btnClearLog = New-Btn 'Clear' 'Clear the activity log (does not affect the server).' { $script:LogBox.Clear() }
$btnClearLog.Dock = 'Right'
$btnClearLog.Size = New-Object System.Drawing.Size(56, 24)
$logHead.Controls.Add($logTitle)
$logHead.Controls.Add($btnClearLog)
$logInner = New-Object System.Windows.Forms.Panel
$logInner.Dock = 'Fill'
$logInner.Padding = New-Object System.Windows.Forms.Padding(12, 0, 12, 8)
$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.ReadOnly = $true
$script:LogBox.BackColor = $Theme.log
$script:LogBox.ForeColor = [System.Drawing.Color]::FromArgb(212, 212, 212)
$script:LogBox.BorderStyle = 'None'
$script:LogBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$script:LogBox.WordWrap = $false
$script:LogBox.ScrollBars = 'Vertical'
$script:LogBox.Dock = 'Fill'
$logInner.Controls.Add($script:LogBox)
$logPanel.Controls.Add($logInner)
$logPanel.Controls.Add($logHead)

# ---------------- Content area (added FIRST so the docked bars lay out around it) --------
$script:Content = New-Object System.Windows.Forms.Panel
$script:Content.Dock = 'Fill'
$script:Content.BackColor = $Theme.bg

$script:Form.Controls.Add($script:Content)
$script:Form.Controls.Add($statusBar)
$script:Form.Controls.Add($logPanel)
$script:Form.Controls.Add($toolbar)
$script:Form.Controls.Add($header)

$script:LayoutPending = $false
$script:DoRelayout = {
    $script:LayoutPending = $false
    if ($script:PageLayout) { & $script:PageLayout }
}
$script:Form.Add_Resize({
    try {
        if ($script:Form.WindowState -ne 'Maximized' -and -not $script:Fullscreen) { Set-Round $script:Form 12 }
        if (-not $script:LayoutPending) {
            $script:LayoutPending = $true
            [void]$script:Form.BeginInvoke([System.Windows.Forms.MethodInvoker]$script:DoRelayout)
        }
    } catch { Write-Log "[LAYOUT-ERROR] $($_.Exception.Message)" }
})

# ---------------------------------------------------------------------------------------
# HOME PAGE (status + connect info + start/stop)
# ---------------------------------------------------------------------------------------
function Show-HomePage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg

    # Status card (top)
    $script:StatusCard = New-Object System.Windows.Forms.Panel
    $script:StatusCard.Dock = 'Top'
    $script:StatusCard.AutoSize = $true
    $script:StatusCard.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $script:StatusCard.BackColor = $Theme.panel
    $script:StatusCard.Padding = New-Object System.Windows.Forms.Padding(16, 10, 16, 10)
    $script:StatusCard.Add_SizeChanged({ Set-Round $this 10 })
    $script:StatusCard.Add_HandleCreated({ Set-Round $this 10 })
    $stTlp = New-Object System.Windows.Forms.TableLayoutPanel
    $stTlp.Dock = 'Fill'
    $stTlp.AutoSize = $true
    $stTlp.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $stTlp.ColumnCount = 2
    $null = $stTlp.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 55)))
    $null = $stTlp.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 45)))
    $script:StatusCard.Controls.Add($stTlp)

    $script:LblStatusBig = New-Lbl 'SERVER STOPPED' $Theme.red 20 34 $true
    $script:LblStatusBig.AutoSize = $true
    $script:LblStatusBig.Anchor = 'Left'
    $script:LblStatusBig.Font = New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)
    $r = $stTlp.RowCount; $stTlp.RowCount = $r + 1
    $stTlp.Controls.Add($script:LblStatusBig, 0, $r)

    $script:LblStatusHint = New-Lbl 'Press Start Server (or Ctrl+S). Everything is automatic: key check, safety scan, firewall, port, then it opens the BeamMP Launcher.' $Theme.dim 9.5 40
    $script:LblStatusHint.Dock = 'Fill'
    $script:LblStatusHint.AutoSize = $true
    $script:LblStatusHint.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $stTlp.Controls.Add($script:LblStatusHint, 1, $r)

    $script:LblServerMeta = New-Lbl '' $Theme.dim 9.5 20
    $script:LblServerMeta.AutoSize = $true
    $script:LblServerMeta.Anchor = 'Left'
    $script:LblServerMeta.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    $r = $stTlp.RowCount; $stTlp.RowCount = $r + 1
    $stTlp.Controls.Add($script:LblServerMeta, 0, $r); $stTlp.SetColumnSpan($script:LblServerMeta, 2)

    $script:LblCgnatBadge = New-Lbl '' $Theme.yellow 9.5 20
    $script:LblCgnatBadge.Dock = 'Fill'
    $script:LblCgnatBadge.AutoSize = $true
    $script:LblCgnatBadge.Visible = $false
    $script:LblCgnatBadge.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    $r = $stTlp.RowCount; $stTlp.RowCount = $r + 1
    $stTlp.Controls.Add($script:LblCgnatBadge, 0, $r); $stTlp.SetColumnSpan($script:LblCgnatBadge, 2)
    $p.Controls.Add($script:StatusCard)

    # Connect info card (fills the rest, scrolls)
    $script:ConnCard = New-Object System.Windows.Forms.Panel
    $script:ConnCard.Dock = 'Fill'
    $script:ConnCard.BackColor = $Theme.bg
    $script:ConnCard.AutoScroll = $true
    $script:ConnContent = New-Object System.Windows.Forms.Panel
    $script:ConnContent.Location = New-Object System.Drawing.Point(12, 8)
    $script:ConnContent.Anchor = 'Top,Left,Right'
    $script:ConnContent.AutoSize = $true
    $script:ConnContent.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $script:ConnContent.MinimumSize = New-Object System.Drawing.Size([int][math]::Max(($script:ConnCard.ClientSize.Width - 24), 200), 0)
    $script:ConnCard.Controls.Add($script:ConnContent)
    $script:ConnCard.Add_Resize({
        $script:ConnContent.MinimumSize = New-Object System.Drawing.Size([int][math]::Max(($script:ConnCard.ClientSize.Width - 24), 200), 0)
    })

    $connTlp = New-Object System.Windows.Forms.TableLayoutPanel
    $connTlp.Dock = 'Top'
    $connTlp.AutoSize = $true
    $connTlp.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $connTlp.ColumnCount = 1
    $null = $connTlp.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $script:ConnContent.Controls.Add($connTlp)

    $connTitle = New-Lbl 'How your friends connect  (BeamNG -> More... -> BeamMP -> Direct Connect)' $Theme.blue 12 26 $true
    $connTitle.AutoSize = $true
    $connTitle.Anchor = 'Left'
    $r = $connTlp.RowCount; $connTlp.RowCount = $r + 1
    $connTlp.Controls.Add($connTitle, 0, $r)

    function Add-ConnLine([string]$VarName, [System.Drawing.Color]$Color, [bool]$Bold = $false) {
        $lbl = New-Lbl '' $Color 10 22 $Bold
        $lbl.Dock = 'Fill'
        $lbl.AutoSize = $true
        $lbl.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)
        $r = $connTlp.RowCount; $connTlp.RowCount = $r + 1
        $connTlp.Controls.Add($lbl, 0, $r)
        Set-Variable -Name $VarName -Value $lbl -Scope Script
    }
    Add-ConnLine 'LblConnThis' ([System.Drawing.Color]::White) $false
    Add-ConnLine 'LblConnLan' $Theme.dim $false
    Add-ConnLine 'LblConnVpn' $Theme.green $false
    Add-ConnLine 'LblConnTunnel' $Theme.blue $true
    Add-ConnLine 'LblConnTail' $Theme.blue $false
    Add-ConnLine 'LblConnPub' $Theme.dim $false
    Add-ConnLine 'LblConnRouter' $Theme.dim $false
    Add-ConnLine 'LblConnNote' $Theme.yellow $false

    $script:ConnVpnFlow = New-ButtonBar
    $script:ConnVpnFlow.AutoSize = $true
    $script:ConnVpnFlow.WrapContents = $true
    $r = $connTlp.RowCount; $connTlp.RowCount = $r + 1
    $connTlp.Controls.Add($script:ConnVpnFlow, 0, $r)

    $btnBar = New-ButtonBar
    $script:BtnDiag = New-Btn 'Diagnose' 'Run a full live diagnosis and show a plain-language report of any problem. (Ctrl+D)' { Run-Diagnose }
    $script:BtnDiag.Size = New-Object System.Drawing.Size(110, 36)
    $script:BtnCopy = New-Btn 'Copy IP' 'Copy the best address for your friends to the clipboard (FRP > LAN > VPN > Tailscale > internet). (Ctrl+C)' { Copy-ConnectionLine }
    $script:BtnCopy.Size = New-Object System.Drawing.Size(110, 36)
    $script:BtnInvite = New-Btn 'Copy invite' 'Copy a ready-made invite message (address + how to connect) to paste to your friends. Perfect for a private server.' { Copy-Invite }
    $script:BtnInvite.Size = New-Object System.Drawing.Size(130, 36)
    $script:BtnRefreshHome = New-Btn 'Refresh' 'Re-check every address and the server status right now. (The page also refreshes by itself every few seconds while the server runs.)' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.Conn = Get-ConnectionInfo`nSay ""Addresses refreshed."" " 'live' }
    $script:BtnRefreshHome.Size = New-Object System.Drawing.Size(90, 36)
    $btnBar.Controls.Add($script:BtnDiag)
    $btnBar.Controls.Add($script:BtnCopy)
    $btnBar.Controls.Add($script:BtnInvite)
    $btnBar.Controls.Add($script:BtnRefreshHome)
    $r = $connTlp.RowCount; $connTlp.RowCount = $r + 1
    $connTlp.Controls.Add($btnBar, 0, $r)

    $p.Controls.Add($script:ConnCard)
    $p.Controls.Add($script:StatusCard)
    $script:Content.Controls.Add($p)
    Refresh-Dashboard
}

function Refresh-Dashboard {
    if (-not $script:LblStatusBig) { return }
    $conn = $script:State.Conn
    $running = $script:State.Running
    $port = if ($conn) { $conn.Port } else { (Get-ServerPort) }
    $name = if ($script:State.ServerName) { $script:State.ServerName } else { 'K BNG M Server' }

    $script:LblStatusBig.Text = if ($running) { 'SERVER IS LIVE' } else { 'SERVER STOPPED' }
    $script:LblStatusBig.ForeColor = if ($running) { $Theme.green } else { $Theme.red }
    $script:LblServerMeta.Text = "Server: $name   |   Port: $port   |   $(if ($running) { 'Running - press Stop or close the launcher to shut it down' } else { 'Not running' })"
    if ($running) {
        $script:LblStatusHint.Text = 'The server is live. Start BeamNG via the BeamMP Launcher, then Direct Connect with one of the addresses below. Closing this app stops the server.'
        $script:LblStatusHint.ForeColor = $Theme.green
    } else {
        $script:LblStatusHint.Text = 'Press Start Server (or Ctrl+S). Everything is automatic: key check, safety scan, firewall, port, then it opens the BeamMP Launcher.'
        $script:LblStatusHint.ForeColor = $Theme.dim
    }
    $cgnat = if ($conn) { $conn.Cgnat } else { $false }
    if ($cgnat) {
        $script:LblCgnatBadge.Visible = $true
        $script:LblCgnatBadge.Text = '[CGNAT detected] Your ISP shares one public IP - port forwarding can never work. Friends must use FRP, a VPN (Network tab) or your ISP must give you a real public IP.'
    } else {
        $script:LblCgnatBadge.Visible = $false
        $script:LblCgnatBadge.Text = ''
    }

    $script:LblConnThis.Text = "THIS PC (test it now):   127.0.0.1  :  $port"
    $script:LblConnLan.Text = if ($conn -and $conn.LAN) { "Friends (same WiFi):      $($conn.LAN)  :  $port" } else { 'Friends (same WiFi):     (LAN IP not detected)' }
    $vpnLines = @()
    if ($conn) { $vpnLines = @($conn.Vpn | Where-Object { $_.Ip }) }
    # Tunnel addresses: the FRP tunnel takes priority while it is running,
    # the Playit.gg agent address is shown otherwise.
    $playitAddress = Get-PlayitAddress
    if ($running -and $script:State.Frp) {
        $script:LblConnTunnel.Text = "Friends (FRP tunnel):      $($script:State.Frp)   (no port forwarding needed)"
        $script:LblConnTunnel.Visible = $true
    } elseif ($playitAddress) {
        $script:LblConnTunnel.Text = "Friends (Playit.gg):      $playitAddress"
        $script:LblConnTunnel.Visible = $true
    } else {
        $script:LblConnTunnel.Visible = $false
    }
    if ($vpnLines.Count) {
        $vpnText = (($vpnLines | ForEach-Object { "$($_.Name) -> $($_.Ip):$port" }) -join '   ')
        if ($vpnLines.Count -ge 2) { $vpnText += '   (friends must use the SAME VPN as the line you send)' }
        $script:LblConnVpn.Text = "Friends (VPN):             $vpnText"
    } else {
        $script:LblConnVpn.Text = 'Friends (VPN):             (none running - see the Network tab)'
    }
    if ($script:ConnVpnFlow) {
        $script:ConnVpnFlow.Controls.Clear()
        if ($vpnLines.Count -ge 1) {
            foreach ($v in $vpnLines) {
                $b = New-CopyButton "Copy $($v.Name) IP" "Copy the $($v.Name) IP:port address ($($v.Ip):$port) - only for friends on the SAME $($v.Name) network." "$($v.Ip):$port" "$($v.Name) address $($v.Ip):$port"
                $b.Size = New-Object System.Drawing.Size(150, 28)
                $script:ConnVpnFlow.Controls.Add($b)
            }
            $script:ConnVpnFlow.Visible = $true
        } else {
            $script:ConnVpnFlow.Visible = $false
        }
    }
    $script:LblConnTail.Text = if ($conn -and $conn.Tailscale) { "Friends (Tailscale):      $($conn.Tailscale)  :  $port" } else { 'Friends (Tailscale):      (not running)' }
    $isPrivate = Get-ServerPrivate
    $script:BtnInvite.Text = if ($isPrivate) { 'Copy invite (private)' } else { 'Copy invite' }
    $script:Tip.SetToolTip($script:BtnInvite, $(if ($isPrivate) { 'Your server is PRIVATE - friends cannot find it in the list. This copies the full invite message with the address and connect steps.' } else { 'Copy a ready-made invite message. For a public server friends can also just find it in the BeamMP list.' }))
    $privNote = if ($isPrivate) { '    (PRIVATE server - hidden from the list - only people you send this address to can join)' } else { '' }
    $script:LblConnPub.Text = if ($conn -and $conn.Public) { "Anyone (internet):        $($conn.Public)  :  $port$privNote" } else { 'Anyone (internet):        (public IP not detected)' }
    if ($running) {
        if ($script:State.UpnpOk) {
            $script:LblConnRouter.Text = "Router (UPnP):            port $port forwarded - internet players CAN connect."
            $script:LblConnRouter.ForeColor = $Theme.green
        } elseif ($cgnat) {
            $script:LblConnRouter.Text = "Router (UPnP):            CGNAT - forwarding impossible. Use the FRP tunnel or a VPN (Network tab) or ask your ISP for a public IP."
            $script:LblConnRouter.ForeColor = $Theme.red
        } else {
            $script:LblConnRouter.Text = "Router (UPnP):            NOT forwarded - use Fix or forward port $port (TCP+UDP) manually."
            $script:LblConnRouter.ForeColor = $Theme.yellow
        }
    } else {
        $script:LblConnRouter.Text = "Router (UPnP):            opens automatically when the server starts (start it to see the result)"
        $script:LblConnRouter.ForeColor = $Theme.dim
    }
    $badVpn = @()
    if ($conn) { $badVpn = @($conn.Vpn | Where-Object { -not $_.Ip }) }
    if ($badVpn.Count) {
        $script:LblConnNote.Text = "[NOTE] $($badVpn[0].Name) is running but has no VPN IP yet - click/join your network inside the VPN app, or start it from the Network tab.`nIMPORTANT: do NOT click your own server in the BeamMP server list - it uses your public IP and fails from inside your own network. Always use Direct Connect."
    } else {
        $script:LblConnNote.Text = "IMPORTANT: do NOT click your own server in the BeamMP server list - it uses your public IP and fails from inside your own network. Always use Direct Connect."
    }
    try { $script:Form.PerformLayout() } catch { }
}

# ---------------------------------------------------------------------------------------
# SETTINGS PAGE
# ---------------------------------------------------------------------------------------
function Show-SettingsPage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg

    $top = New-PageTop $p 'Settings' 'Everything in one scroll - most settings apply on the next server start.'
    $script:BtnSave = New-Btn 'Save settings' 'Save every setting on this page (name, players, cars, description, tags, toggles). Applies on the next server start.' { Save-Settings }
    $script:BtnSave.BackColor = [System.Drawing.Color]::FromArgb(35, 100, 60)
    $script:BtnSave.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(63, 185, 80)
    $script:BtnSave.Size = New-Object System.Drawing.Size(150, 34)
    $top.Flow.Controls.Add($script:BtnSave)
    $script:LblSettingsResult = New-Lbl '' $Theme.green 9 20
    $script:LblSettingsResult.AutoEllipsis = $true
    $top.Flow.Controls.Add($script:LblSettingsResult)
    $p.Controls.Add($top.Bar)

    $stack = New-CardStack $p
    $cards = @()

    # ---- Server identity ----
    $card = New-Card 'Server identity' 'How your server looks in the BeamMP list.'
    $script:TxtName = New-SettingsInput
    $script:TxtName.Height = 26
    Add-Row $card 'Server name:' $script:TxtName
    $flRow = New-ButtonBar
    $flRow.WrapContents = $false
    $script:TxtPlayers = New-SettingsInput
    $script:TxtPlayers.Width = 90
    $script:TxtPlayers.Height = 26
    $script:TxtCars = New-SettingsInput
    $script:TxtCars.Width = 90
    $script:TxtCars.Height = 26
    $flRow.Controls.Add($script:TxtPlayers)
    $flRow.Controls.Add((New-Lbl 'players' $Theme.dim 9 20))
    $flRow.Controls.Add($script:TxtCars)
    $flRow.Controls.Add((New-Lbl 'max cars per player' $Theme.dim 9 20))
    Add-Row $card 'Players / cars:' $flRow
    $script:TxtDescription = New-SettingsInput
    $script:TxtDescription.Multiline = $true
    $script:TxtDescription.Height = 56
    $script:TxtDescription.ScrollBars = 'Vertical'
    Add-Row $card 'Description (optional):' $script:TxtDescription
    $script:TxtTags = New-SettingsInput
    $script:TxtTags.Height = 26
    Add-Row $card 'Tags, comma separated:' $script:TxtTags
    Add-RowNote $card 'Example tags: Freeroam,KBnG,BeamMP - they help players find your server in the list.' $Theme.dim | Out-Null
    $cards += $card

    # ---- Visibility ----
    $card = New-Card 'Server visibility' 'Who can find your server in the BeamMP list.'
    $script:RadioPublic = New-Object System.Windows.Forms.RadioButton
    $script:RadioPublic.Text = 'Public - listed for everyone (strangers can find and join)'
    $script:RadioPublic.ForeColor = [System.Drawing.Color]::White
    $script:RadioPublic.BackColor = $Theme.card
    $script:RadioPublic.FlatStyle = 'Flat'
    $script:RadioPublic.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $script:RadioPublic.Height = 24
    Add-RowFull $card $script:RadioPublic
    $script:RadioPrivate = New-Object System.Windows.Forms.RadioButton
    $script:RadioPrivate.Text = 'Private - hidden from the list (only people you send the address to can join)'
    $script:RadioPrivate.ForeColor = [System.Drawing.Color]::White
    $script:RadioPrivate.BackColor = $Theme.card
    $script:RadioPrivate.FlatStyle = 'Flat'
    $script:RadioPrivate.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $script:RadioPrivate.Height = 24
    Add-RowFull $card $script:RadioPrivate
    $script:BtnApplyVis = New-Btn 'Apply visibility' 'Save the public/private choice. If the server is running it restarts to apply it.' { Apply-Visibility }
    $script:BtnApplyVis.Size = New-Object System.Drawing.Size(150, 32)
    Add-RowFull $card $script:BtnApplyVis
    Add-RowNote $card 'Private: friends join via Direct Connect using the address shown on the Home page (IP:port). A private server cannot be found through Search.' $Theme.yellow | Out-Null
    $cards += $card

    # ---- Server key ----
    $card = New-Card 'Server key' 'How BeamMP knows you own your server.'
    $keyBar = New-ButtonBar
    $script:BtnKey = New-Btn 'Set up / change my server key' 'Open the key setup dialog. Get your free key at https://keymaster.beammp.com' { Show-KeySetupDialog $script:Form }
    $script:BtnKey.Size = New-Object System.Drawing.Size(200, 34)
    $script:BtnUpdate = New-Btn 'Check for updates' 'Ask GitHub if a newer BeamMP-Server build exists (cached 24h).' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$msg = Check-ForUpdates`n`$State.UpdateMsg = `$msg`nif (`$msg) { Say `$msg } else { Say ""BeamMP-Server is up to date."" }" 'update' }
    $script:BtnUpdate.Size = New-Object System.Drawing.Size(170, 34)
    $keyBar.Controls.Add($script:BtnKey)
    $keyBar.Controls.Add($script:BtnUpdate)
    Add-RowFull $card $keyBar
    Add-RowNote $card 'Your key is stored privately on your PC and never shown again.' $Theme.dim | Out-Null
    $cards += $card

    # ---- Map ----
    $card = New-Card 'Map' 'What everyone plays on - applies on the next server start.'
    $script:TxtMapSearch = New-SettingsInput
    $script:TxtMapSearch.Height = 26
    $script:TxtMapSearch.Add_TextChanged({ Refresh-MapListBox })
    Add-Row $card 'Search maps (type to filter):' $script:TxtMapSearch
    $script:CmbMaps = New-Object System.Windows.Forms.ComboBox
    $script:CmbMaps.DropDownStyle = 'DropDownList'
    $script:CmbMaps.Height = 26
    $script:CmbMaps.BackColor = $Theme.bg
    $script:CmbMaps.ForeColor = [System.Drawing.Color]::White
    $script:CmbMaps.FlatStyle = 'Flat'
    $script:CmbMaps.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    Add-RowFull $card $script:CmbMaps
    $mapBar = New-ButtonBar
    $script:BtnApplyMap = New-Btn 'Apply map' 'Set the chosen map on the server. Map mods are sent to players automatically when they join. If the server is running it restarts to apply the map.' { Apply-MapSelection }
    $script:BtnApplyMap.Size = New-Object System.Drawing.Size(110, 32)
    $script:BtnScanMaps = New-Btn 'Scan maps' 'Re-scan the game and mod folders for maps (do this after installing a new map).' { Refresh-MapCombo $true }
    $script:BtnScanMaps.Size = New-Object System.Drawing.Size(110, 32)
    $mapBar.Controls.Add($script:BtnApplyMap)
    $mapBar.Controls.Add($script:BtnScanMaps)
    Add-RowFull $card $mapBar
    $cards += $card

    # ---- Port & connection ----
    $card = New-Card 'Port & connection' 'The door friends use to join your server.'
    $portBar = New-ButtonBar
    $portBar.WrapContents = $false
    $script:LblSettings3 = New-Lbl ("Port: $((Get-ServerPort))  (change it automatically if it is ever busy)") $Theme.dim 9.5 22
    $portBar.Controls.Add($script:LblSettings3)
    $script:BtnPort = New-Btn 'Use a free port' 'Pick a free port and save it. Remember: the router must forward the NEW port (TCP+UDP).' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Set-FreePort -Port (Get-FreePort))" 'setport' }
    $script:BtnPort.Size = New-Object System.Drawing.Size(130, 32)
    $portBar.Controls.Add($script:BtnPort)
    Add-RowFull $card $portBar
    $script:ChkLock = New-Object System.Windows.Forms.CheckBox
    $script:ChkLock.Text = 'Lock my IP while hosting (keeps the LAN IP fixed so router forwards never break when the DHCP lease renews)'
    $script:ChkLock.ForeColor = [System.Drawing.Color]::White
    $script:ChkLock.BackColor = $Theme.card
    $script:ChkLock.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $script:ChkLock.Height = 26
    $script:ChkLock.Checked = (Test-StaticIpLocked)
    $script:ChkLock.Add_CheckedChanged({
        if (-not $script:SuppressSettingEvents) { Persist-LockToggle }
    })
    Add-RowFull $card $script:ChkLock
    Add-RowNote $card 'The IP lock applies right away and returns to DHCP automatically when the session ends.' $Theme.dim | Out-Null
    $cards += $card

    # ---- Behavior (optional) ----
    $card = New-Card 'Behavior switches (optional)' 'Tick = enabled. Saved with the Save settings button above.'
    $script:ChkAllowGuests = New-Object System.Windows.Forms.CheckBox
    $script:ChkAllowGuests.Text = 'Allow guests (players without a BeamMP auth key)'
    $script:ChkAllowGuests.ForeColor = [System.Drawing.Color]::White
    $script:ChkAllowGuests.BackColor = $Theme.card
    $script:ChkAllowGuests.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $script:ChkAllowGuests.Height = 24
    Add-RowFull $card $script:ChkAllowGuests
    $script:ChkLogChat = New-Object System.Windows.Forms.CheckBox
    $script:ChkLogChat.Text = 'Log chat messages to the server log'
    $script:ChkLogChat.ForeColor = [System.Drawing.Color]::White
    $script:ChkLogChat.BackColor = $Theme.card
    $script:ChkLogChat.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $script:ChkLogChat.Height = 24
    Add-RowFull $card $script:ChkLogChat
    $script:ChkInfoPacket = New-Object System.Windows.Forms.CheckBox
    $script:ChkInfoPacket.Text = 'Send periodic info packets (server list refresh)'
    $script:ChkInfoPacket.ForeColor = [System.Drawing.Color]::White
    $script:ChkInfoPacket.BackColor = $Theme.card
    $script:ChkInfoPacket.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $script:ChkInfoPacket.Height = 24
    Add-RowFull $card $script:ChkInfoPacket
    $script:ChkDebug = New-Object System.Windows.Forms.CheckBox
    $script:ChkDebug.Text = 'Debug mode (more detail written to the server log)'
    $script:ChkDebug.ForeColor = [System.Drawing.Color]::White
    $script:ChkDebug.BackColor = $Theme.card
    $script:ChkDebug.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $script:ChkDebug.Height = 24
    Add-RowFull $card $script:ChkDebug
    $cards += $card

    # ---- Presets ----
    $card = New-Card 'Presets' 'Save a whole setup (settings + enabled mods) under a name, load it back later. Great for different game nights.'
    $preRow = New-ButtonBar
    $preRow.WrapContents = $false
    $script:TxtPresetName = New-SettingsInput
    $script:TxtPresetName.Width = 200
    $script:TxtPresetName.Height = 26
    $preRow.Controls.Add($script:TxtPresetName)
    $preRow.Controls.Add((New-Lbl 'or pick one:' $Theme.dim 9 20))
    $script:CmbPresets = New-Object System.Windows.Forms.ComboBox
    $script:CmbPresets.DropDownStyle = 'DropDownList'
    $script:CmbPresets.Width = 220
    $script:CmbPresets.Height = 26
    $script:CmbPresets.BackColor = $Theme.bg
    $script:CmbPresets.ForeColor = [System.Drawing.Color]::White
    $script:CmbPresets.FlatStyle = 'Flat'
    $script:CmbPresets.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $preRow.Controls.Add($script:CmbPresets)
    Add-RowFull $card $preRow
    $preBar = New-ButtonBar
    $script:BtnSavePreset = New-Btn 'Save preset' 'Save the current settings + enabled mods under the name you typed (or the selected one).' { Save-PresetFlow }
    $script:BtnSavePreset.Size = New-Object System.Drawing.Size(110, 32)
    $script:BtnLoadPreset = New-Btn 'Load preset' 'Apply the selected preset: restores its settings and switches the mods to match it.' { Load-PresetFlow }
    $script:BtnLoadPreset.Size = New-Object System.Drawing.Size(110, 32)
    $script:BtnDeletePreset = New-Btn 'Delete preset' 'Delete the selected preset (asks first).' { Delete-PresetFlow }
    $script:BtnDeletePreset.Size = New-Object System.Drawing.Size(110, 32)
    $preBar.Controls.Add($script:BtnSavePreset)
    $preBar.Controls.Add($script:BtnLoadPreset)
    $preBar.Controls.Add($script:BtnDeletePreset)
    Add-RowFull $card $preBar
    Add-RowNote $card 'Presets are saved privately in the Server\Presets folder - they are not uploaded anywhere. Loading a preset restarts the server if it is running.' $Theme.dim | Out-Null
    $cards += $card

    & $script:MountCards $cards $stack.Content
    $script:Content.Controls.Add($p)
    $script:SuppressSettingEvents = $true
    $script:ChkLock.Checked = (Test-StaticIpLocked)
    $script:SuppressSettingEvents = $false
    Refresh-SettingsFields
    Refresh-MapCombo
    Refresh-PresetCombo
    Refresh-Dashboard
}

# Fills the settings inputs from the current ServerConfig.toml values.
function Refresh-SettingsFields {
    try {
        if (-not $script:TxtName) { return }
        $script:SuppressSettingEvents = $true
        try {
            $script:TxtName.Text = Get-ConfigValue 'Name'
            $script:TxtPlayers.Text = Get-ConfigValue 'MaxPlayers'
            $script:TxtCars.Text = Get-ConfigValue 'MaxCars'
            $script:TxtDescription.Text = Get-ConfigValue 'Description'
            $script:TxtTags.Text = Get-ConfigValue 'Tags'
            $script:ChkAllowGuests.Checked = ((Get-ConfigValue 'AllowGuests') -match 'true|1')
            $script:ChkLogChat.Checked = ((Get-ConfigValue 'LogChat') -match 'true|1')
            $script:ChkDebug.Checked = ((Get-ConfigValue 'Debug') -match 'true|1')
            $script:ChkInfoPacket.Checked = ((Get-ConfigValue 'InformationPacket') -match 'true|1')
            $isPriv = Get-ServerPrivate
            $script:RadioPublic.Checked = -not $isPriv
            $script:RadioPrivate.Checked = $isPriv
        } finally {
            $script:SuppressSettingEvents = $false
        }
    } catch { Write-Log "[ERROR] Could not read settings: $($_.Exception.Message)" }
}

function Refresh-PresetCombo {
    if (-not $script:CmbPresets) { return }
    $keep = $script:CmbPresets.SelectedItem
    $script:CmbPresets.Items.Clear()
    foreach ($n in Get-Presets) { [void]$script:CmbPresets.Items.Add($n) }
    if ($keep -and $script:CmbPresets.Items.Contains($keep)) { $script:CmbPresets.SelectedItem = $keep }
    elseif ($script:CmbPresets.Items.Count) { $script:CmbPresets.SelectedIndex = 0 }
}

function Save-PresetFlow {
    $name = $script:TxtPresetName.Text.Trim()
    if (-not $name) { $name = $script:CmbPresets.SelectedItem }
    if (-not $name) { Add-Log "[INFO] Type a preset name first."; return }
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Save-Preset $(QStr $name))`n`$State.PresetChanged = (Get-Date).ToString('o')" 'preset'
}

function Load-PresetFlow {
    $name = $script:CmbPresets.SelectedItem
    if (-not $name) { Add-Log "[INFO] Select a preset first."; return }
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Load-Preset $(QStr $name))`n`$State.PresetChanged = (Get-Date).ToString('o')" 'preset'
}

function Delete-PresetFlow {
    $name = $script:CmbPresets.SelectedItem
    if (-not $name) { Add-Log "[INFO] Select a preset first."; return }
    $r = [System.Windows.Forms.MessageBox]::Show("Delete preset '$name'? This cannot be undone.", 'Delete preset', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($r -ne 'Yes') { return }
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Delete-Preset $(QStr $name))`n`$State.PresetChanged = (Get-Date).ToString('o')" 'preset'
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
    Refresh-MapListBox
    Add-Log "[INFO] Map scan done - $($script:CachedMaps.Count) map(s) available."
}

# Rebuilds the combo from $script:CachedMaps, honoring the search filter text.
function Refresh-MapListBox {
    if (-not $script:CmbMaps) { return }
    $q = ''
    if ($script:TxtMapSearch) { $q = $script:TxtMapSearch.Text.Trim() }
    $script:FilteredMaps = @($script:CachedMaps | Where-Object { -not $q -or $_.Name -like "*$q*" -or $_.Path -like "*$q*" })
    $script:CmbMaps.Items.Clear()
    $script:MapPlaceholder = $false
    foreach ($m in $script:FilteredMaps) {
        $disp = $m.Name + $(if ($m.Kind -eq 'Vanilla') { '   (Vanilla)' } else { '   [MAP MOD]' })
        [void]$script:CmbMaps.Items.Add($disp)
    }
    $cur = Get-ServerMap
    $curName = Get-MapNameFromPath $cur
    if ($curName -and -not $q) {
        $idx = -1
        for ($i = 0; $i -lt $script:FilteredMaps.Count; $i++) { if ($script:FilteredMaps[$i].Name -ieq $curName) { $idx = $i; break } }
        if ($idx -ge 0) { $script:CmbMaps.SelectedIndex = $idx }
        else {
            $script:MapPlaceholder = $true
            [void]$script:CmbMaps.Items.Insert(0, "$curName   (current, not found in scan)")
            $script:CmbMaps.SelectedIndex = 0
        }
    } elseif ($script:FilteredMaps.Count -and $script:CmbMaps.SelectedIndex -lt 0) { $script:CmbMaps.SelectedIndex = 0 }
}

function Apply-MapSelection {
    if (-not $script:CmbMaps) { return }
    $idx = $script:CmbMaps.SelectedIndex
    if ($idx -lt 0) { Add-Log "[INFO] Select a map first."; return }
    if ($script:MapPlaceholder -and $idx -eq 0) { Add-Log "[INFO] The current map was not found in the scan - pick another map from the list."; return }
    $map = $script:FilteredMaps[$idx]
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

function Save-Settings {
    $vals = @{}
    $name = $script:TxtName.Text.Trim()
    if ($name) {
        if ($name -notmatch '^[^"]{1,60}$') {
            Add-Log "[ERROR] Server name must be 60 characters or fewer and cannot contain double quotes."
            return
        }
        $vals['Name'] = '"' + $name + '"'
    }
    foreach ($pair in @(@{ Key = 'MaxPlayers'; Txt = $script:TxtPlayers }, @{ Key = 'MaxCars'; Txt = $script:TxtCars })) {
        $v = $pair.Txt.Text.Trim()
        if ($v) {
            if ($v -notmatch '^\d+$') { Add-Log "[ERROR] $($pair.Key) must be a number."; return }
            $vals[$pair.Key] = [int]$v
        }
    }
    $desc = $script:TxtDescription.Text.Trim().Replace('"', "'")
    if ($desc) { $vals['Description'] = '"' + $desc + '"' } else { $vals['Description'] = '""' }
    $tags = $script:TxtTags.Text.Trim().Replace('"', "'")
    if ($tags) { $vals['Tags'] = '"' + $tags + '"' } else { $vals['Tags'] = '""' }
    $vals['AllowGuests'] = $script:ChkAllowGuests.Checked.ToString().ToLower()
    $vals['LogChat'] = $script:ChkLogChat.Checked.ToString().ToLower()
    $vals['Debug'] = $script:ChkDebug.Checked.ToString().ToLower()
    $vals['InformationPacket'] = $script:ChkInfoPacket.Checked.ToString().ToLower()

    # FRP tunnel settings (persisted to the [FRP] section of ServerConfig.toml) -
    # the fields live on the Network page; keep them when that page was opened.
    if ($script:ChkFrp) {
        $vals['FRPEnabled'] = $script:ChkFrp.Checked.ToString().ToLower()
        $frpServer = $script:TxtFrpServer.Text.Trim()
        if ($frpServer) {
            if ($frpServer -notmatch '^[A-Za-z0-9.\-]+$') {
                Add-Log "[ERROR] FRP server address may only contain letters, numbers, dots and dashes (hostname or IP - the port goes in its own box)."
                return
            }
            $vals['FRPServerAddress'] = '"' + $frpServer + '"'
        }
        $frpPort = $script:TxtFrpPort.Text.Trim()
        if (-not $frpPort) { $frpPort = '7000' }
        if ($frpPort -notmatch '^\d+$' -or [int]$frpPort -lt 1 -or [int]$frpPort -gt 65535) {
            Add-Log "[ERROR] FRP server port must be a number between 1 and 65535."
            return
        }
        $vals['FRPServerPort'] = [int]$frpPort
        $frpToken = $script:TxtFrpToken.Text
        if ($frpToken) {
            $vals['FRPToken'] = '"' + ($frpToken.Replace('"', '')) + '"'
        }
    }

    # Save the IP lock checkbox state - same single background action as the
    # config write below, so a busy UI can never drop one of the two saves.
    $lockNow = Test-StaticIpLocked
    $lockPart = ''
    if ($script:ChkLock.Checked -and -not $lockNow) {
        $lockPart = "`nSay ""Enabling the IP lock...""`nif (Set-StaticLanIp) { Say ""IP lock enabled - it will be applied on the next server start."" } else { Say ""Could not enable the lock (was the Windows window cancelled?)."" }"
    } elseif (-not $script:ChkLock.Checked -and $lockNow) {
        $lockPart = "`nSay ""Disabling the IP lock...""`nif (Restore-DhcpLanIp) { Remove-Item -LiteralPath (`$script:ServerDir + 'staticip.cfg') -Force -ErrorAction SilentlyContinue; Say ""Lock disabled - your IP returns to DHCP now."" } else { Say ""Could not disable it (was the Windows window cancelled?)."" }"
    }
    
    # Build the action-script hashtable literal. Boolean strings MUST be
    # double-quoted here: a bare "true"/"false" inside @{...} is parsed as a
    # COMMAND by PowerShell, which silently killed the whole save for every
    # toggle (the original persistence bug).
    $valsText = ($vals.GetEnumerator() | ForEach-Object {
        $v = $_.Value
        if ($v -is [string] -and ($v -eq 'true' -or $v -eq 'false')) { $v = '"' + $v + '"' }
        "'$($_.Key)' = $v"
    }) -join '; '
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue$lockPart`nSay (Set-ServerConfig -Values @{$valsText})`n`$State.SettingsSaved = (Get-Date).ToString('o')" 'settings'
    
    Add-Log "[OK] Settings saved (applies on the next server start)."
    Refresh-Dashboard
}

# Immediate persistence for toggles - every change is queued and written right
# away (the action queue never drops it), without waiting for the Save button.
function Persist-FrpToggle {
    if (-not $script:ChkFrp) { return }
    $v = $script:ChkFrp.Checked.ToString().ToLower()
    Add-Log "[INFO] FRP tunnel: $($script:ChkFrp.Checked) - saving..."
    # $v is embedded QUOTED ("true"/"false") - a bare literal would be parsed
    # as a command and silently drop the save.
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Set-ServerConfig -Values @{ FRPEnabled = ""$v"" })" 'frptoggle'
}

function Persist-LockToggle {
    if (-not $script:ChkLock) { return }
    Add-Log "[INFO] IP lock: $($script:ChkLock.Checked) - applying..."
    if ($script:ChkLock.Checked) {
        Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay ""Enabling the IP lock...""`nif (Set-StaticLanIp) { Say ""IP lock enabled."" } else { Say ""Could not enable the lock (was the Windows window cancelled?)."" }" 'locktoggle'
    } else {
        Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay ""Disabling the IP lock...""`nif (Restore-DhcpLanIp) { Remove-Item -LiteralPath (`$script:ServerDir + 'staticip.cfg') -Force -ErrorAction SilentlyContinue; Say ""Lock disabled - your IP returns to DHCP now."" } else { Say ""Could not disable it (was the Windows window cancelled?)."" }" 'locktoggle'
    }
}

# ---------------------------------------------------------------------------------------
# NETWORK PAGE (FRP tunnel + VPN tools + CGNAT help)
# ---------------------------------------------------------------------------------------
function Show-NetworkPage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg

    $top = New-PageTop $p 'Network' 'Everything about how friends reach you: FRP tunnel, VPNs and CGNAT.'
    $btnRefresh = New-Btn 'Refresh' 'Re-check which VPNs are installed / running and their IPs.' { Show-NetworkPage }
    $btnRefresh.Size = New-Object System.Drawing.Size(90, 34)
    $top.Flow.Controls.Add($btnRefresh)
    $p.Controls.Add($top.Bar)

    $stack = New-CardStack $p
    $cards = @()

    # ---- FRP tunnel ----
    $card = New-Card 'FRP tunnel (Fast Reverse Proxy)' 'Host without router port forwarding - works even behind CGNAT.'
    $script:ChkFrp = New-Object System.Windows.Forms.CheckBox
    $script:ChkFrp.Text = 'Enable FRP tunnel (friends join through your FRP server)'
    $script:ChkFrp.ForeColor = [System.Drawing.Color]::White
    $script:ChkFrp.BackColor = $Theme.card
    $script:ChkFrp.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $script:ChkFrp.Height = 26
    $script:ChkFrp.Add_CheckedChanged({
        if (-not $script:SuppressSettingEvents) { Persist-FrpToggle }
    })
    Add-RowFull $card $script:ChkFrp
    $script:TxtFrpServer = New-SettingsInput
    $script:TxtFrpServer.Height = 26
    Add-Row $card 'FRP server address (hostname or IP):' $script:TxtFrpServer
    $frpRow = New-ButtonBar
    $frpRow.WrapContents = $false
    $script:TxtFrpPort = New-SettingsInput
    $script:TxtFrpPort.Width = 90
    $script:TxtFrpPort.Height = 26
    $frpRow.Controls.Add($script:TxtFrpPort)
    $frpRow.Controls.Add((New-Lbl 'server port (almost always 7000)' $Theme.dim 9 20))
    Add-Row $card 'FRP server port:' $frpRow
    $script:TxtFrpToken = New-SettingsInput
    $script:TxtFrpToken.Height = 26
    $script:TxtFrpToken.UseSystemPasswordChar = $true
    Add-Row $card 'FRP token (stays masked):' $script:TxtFrpToken
    Add-RowNote $card 'The frpc client is bundled with the app - it is extracted into Server\bin\frpc.exe automatically on first use, nothing to install. The runtime config with your token exists only while the tunnel runs and is deleted when it stops. Toggling saves immediately; the other fields save with the Save settings button on the Settings page. Not sure what address/port/token to type? Press the FRP setup guide button below.' $Theme.yellow | Out-Null
    $frpBar = New-ButtonBar
    $btnFrpGuide = New-Btn 'FRP setup guide' 'Step by step: how to get an frps server, what values go where, and how your friends then join.' { Show-FrpSetupGuide }
    $btnFrpGuide.Size = New-Object System.Drawing.Size(160, 32)
    $frpBar.Controls.Add($btnFrpGuide)
    $script:BtnFrpHelp = New-Btn 'FRP info (frps download)' 'Open the FRP GitHub releases page - you need frps.exe from here if you run your own FRP server (see the setup guide). The frpc client side is already bundled with this app.' { Start-Process 'https://github.com/fatedier/frp/releases' }
    $script:BtnFrpHelp.Size = New-Object System.Drawing.Size(220, 32)
    $frpBar.Controls.Add($script:BtnFrpHelp)
    Add-RowFull $card $frpBar
    $cards += $card

    # ---- VPN tools ----
    $card = New-Card 'VPN tools' 'Radmin VPN / Hamachi / ZeroTier / Tailscale / Playit.gg - the fallback when forwarding cannot work.'
    Add-RowNote $card 'SAFETY: a VPN puts friends on a virtual LAN with your PC - they can reach file sharing / Remote Desktop etc. Only invite people you TRUST. Never invite random players into your VPN network.' $Theme.yellow | Out-Null
    $script:VpnRowsWrap = New-Object System.Windows.Forms.Panel
    $script:VpnRowsWrap.AutoSize = $true
    $script:VpnRowsWrap.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $script:VpnRowsWrap.BackColor = $Theme.card
    Add-RowFull $card $script:VpnRowsWrap
    $cards += $card

    # ---- CGNAT ----
    $card = New-Card 'Behind CGNAT?' 'Some ISPs share one public IP - then port forwarding can never work.'
    Add-RowNote $card 'If Fix reports CGNAT, use the FRP tunnel (above) or ANY VPN from the VPN tools above - Radmin VPN, Hamachi, ZeroTier, Tailscale and Playit.gg all work behind CGNAT, and each has its own Start / Download / Copy buttons in that list. Or ask your ISP for a real public IP - nothing in the router can change this.' $Theme.dim | Out-Null
    $cgnatBar = New-ButtonBar
    $btnCgnat = New-Btn 'Explain CGNAT' 'What CGNAT is, why port forwarding can never work behind it, and your options.' { Show-CgnatExplain }
    $btnCgnat.Size = New-Object System.Drawing.Size(130, 32)
    $cgnatBar.Controls.Add($btnCgnat)
    Add-RowFull $card $cgnatBar
    $cards += $card

    & $script:MountCards $cards $stack.Content
    $script:Content.Controls.Add($p)
    Refresh-VpnRows
    Refresh-FrpFields
    # Double layout pass so the auto-size cards settle at their final height
    # (the VPN rows just changed the VPN card).
    try { $script:Form.PerformLayout(); $script:Form.PerformLayout() } catch { }
}

# Loads the FRP inputs from ServerConfig.toml (masked token).
function Refresh-FrpFields {
    if (-not $script:TxtFrpServer) { return }
    $script:SuppressSettingEvents = $true
    try {
        $script:ChkFrp.Checked = ((Get-ConfigValue 'FRPEnabled') -match 'true|1')
        $script:TxtFrpServer.Text = Get-ConfigValue 'FRPServerAddress'
        $frpPortVal = Get-ConfigValue 'FRPServerPort'
        $script:TxtFrpPort.Text = $(if ($frpPortVal -match '^\d+$') { $frpPortVal } else { '7000' })
        if (Get-ConfigValue 'FRPToken') { $script:TxtFrpToken.Text = Get-ConfigValue 'FRPToken' }
    } finally {
        $script:SuppressSettingEvents = $false
    }
}

# VPN row buttons. PowerShell scriptblocks do NOT close over function-local
# variables - a handler like { $App.Url } would see $null when clicked. Every
# value is therefore BAKED into the handler text at build time (same pattern
# as New-CopyButton).
function New-VpnDownloadButton($App) {
    $safeUrl = ($App.Url -replace "'", "''")
    $body = "try { Start-Process '$safeUrl' } catch { [System.Diagnostics.Process]::Start('explorer.exe', '$safeUrl') }"
    $sb = [scriptblock]::Create($body)
    return New-Btn 'Download (official page)' "Open the official download page for $($App.Name)." $sb
}

function New-VpnStartButton($App) {
    $key = $App.Key
    $body = "Start-CoreAction ""param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Start-OrDownload-Vpn (Get-InstalledVpns | Where-Object { `$_.Key -eq '$key' } | Select-Object -First 1))`n`$State.VpnRefresh = (Get-Date).ToString('o')"" 'vpn'"
    $sb = [scriptblock]::Create($body)
    return New-Btn 'Start' "Start $($App.Name) and wait for it to connect. Friends must be on the same VPN network as you." $sb
}

function New-VpnStopButton($App) {
    $key = $App.Key
    $body = "Start-CoreAction ""param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Stop-VpnApp '$key')`n`$State.VpnRefresh = (Get-Date).ToString('o')"" 'vpn'"
    $sb = [scriptblock]::Create($body)
    $b = New-Btn 'Stop' "Fully stop $($App.Name) with one press: closes it, disconnects, and stops its background service (one admin prompt). Friends will see it as offline." $sb
    $b.Size = New-Object System.Drawing.Size(84, 30)
    $b.BackColor = [System.Drawing.Color]::FromArgb(122, 26, 26)
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(158, 34, 34)
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(220, 60, 60)
    $b.ForeColor = [System.Drawing.Color]::White
    return $b
}

function Refresh-VpnRows {
    if (-not $script:VpnRowsWrap) { return }
    $script:VpnRowsWrap.Controls.Clear()
    $rows = @()
    $apps = @(Get-InstalledVpns)
    $running = @(Get-VpnIps)
    foreach ($app in $apps) {
        $run = @($running | Where-Object { $_.Key -eq $app.Key })
        $rowPanel = New-Object System.Windows.Forms.Panel
        $rowPanel.BackColor = $Theme.bg
        $rowPanel.Dock = 'Top'
        $rowPanel.Height = 40
        $rowPanel.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)

        $state = ''
        $color = $Theme.dim
        if (-not $app.Installed) {
            $state = 'NOT installed'
            $color = $Theme.yellow
        } elseif ($run.Count -and $run[0].Ip) {
            $state = "RUNNING - IP $($run[0].Ip)"
            $color = $Theme.green
        } elseif ($run.Count) {
            $state = 'RUNNING - connecting (no VPN IP yet)'
            $color = $Theme.yellow
        } else {
            $state = 'installed, not running'
            $color = $Theme.dim
        }

        $lbl = New-Lbl "$($app.Name)   -   $state" $color 10 32
        $lbl.Dock = 'Fill'
        $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $lbl.AutoEllipsis = $true
        $lbl.Padding = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
        $rowPanel.Controls.Add($lbl)

        $btnFlow = New-Object System.Windows.Forms.FlowLayoutPanel
        $btnFlow.Dock = 'Right'
        $btnFlow.AutoSize = $true
        $btnFlow.WrapContents = $false
        $btnFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
        $rowPanel.Controls.Add($btnFlow)

        if ($app.Installed -and $run.Count -and $run[0].Ip -and $app.Key -ne 'playit') {
            $btnCopy = New-CopyButton 'Copy IP' "Copy the VPN address (IP:port) of $($app.Name) to your clipboard - paste it to your friends so they can direct-connect." "$($run[0].Ip):$(Get-ServerPort)" "VPN address of $($app.Name): $($run[0].Ip):$(Get-ServerPort)"
            $btnCopy.Size = New-Object System.Drawing.Size(84, 30)
            $btnFlow.Controls.Add($btnCopy)
        }
        if ($app.Key -eq 'playit' -and $app.Installed) {
            $address = Get-PlayitAddress
            if ($address) {
                $btnCopy = New-CopyButton 'Copy Address' "Copy the Playit.gg tunnel address to your clipboard - paste it to your friends so they can direct-connect." "$address" "Playit.gg address: $address"
                $btnCopy.Size = New-Object System.Drawing.Size(110, 30)
                $btnFlow.Controls.Add($btnCopy)
            }
        }
        if ($app.Installed -and $run.Count) {
            $btnStop = New-VpnStopButton $app
            $btnFlow.Controls.Add($btnStop)
        }
        if (-not $app.Installed) {
            $btn = New-VpnDownloadButton $app
            $btn.Size = New-Object System.Drawing.Size(170, 30)
            $btnFlow.Controls.Add($btn)
        } elseif (-not ($run.Count -and $run[0].Ip)) {
            $btn = New-VpnStartButton $app
            $btn.Size = New-Object System.Drawing.Size(170, 30)
            $btnFlow.Controls.Add($btn)
        }
        $rows += $rowPanel
    }
    $btnAll = New-Btn 'Start all installed VPNs' 'Start every VPN that is installed on this PC.' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$started = 0`nforeach (`$app in Get-InstalledVpns | Where-Object { `$_.Installed -and `$_.Exe }) { `$r = Start-OrDownload-Vpn `$app 6; Say `$r; if (`$r -match 'connected') { `$started++ } }`nif (`$started -eq 0) { Say ""No VPN could be started. Install one first (see the rows below) and try again."" }`n`$State.VpnRefresh = (Get-Date).ToString('o')" 'vpns' }
    $btnAll.Size = New-Object System.Drawing.Size(170, 32)
    $btnAllRow = New-Object System.Windows.Forms.Panel
    $btnAllRow.Dock = 'Top'
    $btnAllRow.Height = 40
    $btnAllRow.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
    $btnAll.Dock = 'Left'
    $btnAllRow.Controls.Add($btnAll)
    $rows += $btnAllRow
    for ($i = $rows.Count - 1; $i -ge 0; $i--) { $script:VpnRowsWrap.Controls.Add($rows[$i]) }
    Add-Log "[INFO] VPN tools refreshed."
}

# ---------------------------------------------------------------------------------------
# FIX PAGE
# ---------------------------------------------------------------------------------------
function Show-FixPage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg

    $script:FixRowsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $script:FixRowsPanel.Dock = 'Fill'
    $script:FixRowsPanel.FlowDirection = 'TopDown'
    $script:FixRowsPanel.WrapContents = $false
    $script:FixRowsPanel.AutoScroll = $true
    $script:FixRowsPanel.BackColor = $Theme.bg

    $script:FixTop = New-Object System.Windows.Forms.Panel
    $script:FixTop.Dock = 'Top'
    $script:FixTop.Height = 96
    $script:FixTop.BackColor = $Theme.bg

    $head = New-Lbl 'Help / Fix Problems' $Theme.blue 14 26 $true
    $head.Location = New-Object System.Drawing.Point(4, 2)
    $script:FixTop.Controls.Add($head)
    $sub = New-Lbl 'Every check is run for you. [OK] = fine, [X] = fix it (use the button on that row), [?] = needs your attention. Start the server first if you want the internet test to run.' $Theme.dim 9 20  $false 900
    $sub.Location = New-Object System.Drawing.Point(4, 30)
    $script:FixTop.Controls.Add($sub)

    $btnScan = New-Btn 'Re-scan everything' 'Run every check again (key, launcher, port, firewall, CGNAT, internet reachability...).' { Run-FixScan }
    $btnScan.Size = New-Object System.Drawing.Size(160, 34)
    $btnScan.Location = New-Object System.Drawing.Point(4, 54)
    $btnScan.Tag = @{ X = 4; Y = 54; W = 160; H = 34 }
    $script:FixTop.Controls.Add($btnScan)

    $btnUpnp = New-Btn 'Open port on router via UPnP' 'Ask the router to forward the server port (TCP+UDP) automatically - no admin needed.' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$port = Get-ServerPort`nif (Add-UpnpPortForward `$port) { Say ""UPnP: port `$port (TCP+UDP) forwarded on the router. Friends can now connect!"" } else { Say ""UPnP failed. VPNs can block it - retry with Radmin/Tailscale closed, or forward port `$port (TCP+UDP) manually."" }" 'upnp' }
    $btnUpnp.Size = New-Object System.Drawing.Size(210, 34)
    $btnUpnp.Location = New-Object System.Drawing.Point(172, 54)
    $btnUpnp.Tag = @{ X = 172; Y = 54; W = 210; H = 34 }
    $script:FixTop.Controls.Add($btnUpnp)

    $script:BtnFixAll = New-Btn 'Fix all possible' 'One click: frees a busy port, adds the firewall rule, applies a valid map and forwards the port via UPnP. Anything that still needs you (like the server key) is listed in the log.' { Run-FixAll }
    $script:BtnFixAll.Size = New-Object System.Drawing.Size(150, 34)
    $script:BtnFixAll.Location = New-Object System.Drawing.Point(390, 54)
    $script:BtnFixAll.Tag = @{ X = 390; Y = 54; W = 150; H = 34 }
    $script:FixTop.Controls.Add($script:BtnFixAll)

    $p.Controls.Add($script:FixRowsPanel)
    $p.Controls.Add($script:FixTop)
    $script:Content.Controls.Add($p)
    $script:FixRowRefs = @()
    $script:PageLayout = { Layout-FixRows }
    & $script:PageLayout
    Show-FixIdle
}

function Show-FixIdle {
    if (-not $script:FixRowsPanel) { return }
    $script:FixRowsPanel.Controls.Clear()
    $script:FixRowRefs = @()
    $script:LblFixSummary = New-Lbl 'Nothing scanned yet. Press "Re-scan everything" (or "Fix all possible") to check your setup - nothing runs on its own.' $Theme.dim 10 22
    $script:LblFixSummary.Location = New-Object System.Drawing.Point(4, 4)
    $script:FixRowsPanel.Controls.Add($script:LblFixSummary)
}

function Run-FixScan {
    $script:FixRowsPanel.Controls.Clear()
    $script:FixRowRefs = @()
    $script:LblFixSummary = New-Lbl 'Scanning... (the first scan takes a few seconds, then it is fast)' $Theme.dim 10 22
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
        $script:LblFixSummary.ForeColor = $(if ($need -eq 0) { $Theme.green } elseif ($ok -gt 0) { $Theme.yellow } else { $Theme.red })
    }
    Layout-FixRows
}

function Add-FixRow($row) {
    $rowPanel = New-Object System.Windows.Forms.Panel
    $rowPanel.Width = $script:FixRowsPanel.ClientSize.Width - 22
    $rowPanel.Height = 44
    $rowPanel.BackColor = $Theme.panel
    $rowPanel.Padding = New-Object System.Windows.Forms.Padding(8, 5, 8, 5)

    $status = if ($row.Ok) { '[OK]' } elseif ($row.NeedsAction) { '[X]' } else { '[?]' }
    $color = if ($row.Ok) { $Theme.green } elseif ($row.NeedsAction) { $Theme.red } else { $Theme.yellow }
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
        $btn = New-Btn ("$prefix$($row.Action)") $row.Action { FixRowAction $row.Key }
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
            $btnY = SY(54)
            foreach ($c in $script:FixTop.Controls) {
                if ($c -is [System.Windows.Forms.Label] -and $c.Width -gt 400) {
                    $c.Width = $script:FixTop.ClientSize.Width - 8
                    $m = Measure-Text $c.Text $c.Font $c.Width
                    $c.Height = [int][math]::Max(20, $m.Lines * 20)
                    $btnY = $c.Top + $c.Height + 8
                    $maxBottom = [int][math]::Max($maxBottom, ($c.Top + $c.Height + 4))
                }
            }
            foreach ($c in $script:FixTop.Controls) {
                if ($c -is [System.Windows.Forms.Button] -and $c.Tag -is [hashtable] -and $c.Tag.ContainsKey('X')) {
                    $c.Size = New-Object System.Drawing.Size((SX $c.Tag.W), (SY $c.Tag.H))
                    $c.Location = New-Object System.Drawing.Point((SX $c.Tag.X), $btnY)
                    $maxBottom = [int][math]::Max($maxBottom, ($btnY + (SY $c.Tag.H) + 6))
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
        'PORT' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Set-FreePort -Port (Get-FreePort))`n`$State.FixReport = @(Get-FixReport)" 'fixport' }
        'FW' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$null = Add-FirewallRule`nif (Test-FirewallRule) { Say ""Firewall rules verified."" } else { Say ""Firewall rules still missing - try again or check your antivirus."" }`n`$State.FixReport = @(Get-FixReport)" 'fixfw' }
        'FWBEAMNG' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$r = Add-BeamNGFirewallRule`nSay `$r`nif (Test-BeamNGFirewallRule) { Say ""BeamNG.drive firewall rule verified."" } else { Say ""Still missing - if you cancelled the admin window, run it again."" }`n`$State.FixReport = @(Get-FixReport)" 'fixfwbng' }
        'TEREDO' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nEnable-Teredo`n`$State.FixReport = @(Get-FixReport)" 'fixter' }
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

function Show-FrpSetupGuide {
    $text = @"
HOW TO SET UP FRP TUNNELING (step by step)
===========================================

FRP has two parts:
  - frps = the FRP SERVER (runs on a computer/VPS with a public IP)
  - frpc = the FRP CLIENT (BUNDLED with this app - Server\bin\frpc.exe
           is extracted automatically, you never handle it)

To tunnel, you need an frps server. Three ways to get one:

1) RUN YOUR OWN (recommended, ~10 minutes)
   a. Download the FRP release zip from
      https://github.com/fatedier/frp/releases
      (the same zip this app bundles - pick the windows_amd64
      version and unzip it).
   b. On the server machine, create a file next to frps.exe
      called frps.toml with EXACTLY this content:

        bindPort = 7000

        [auth]
        method = "token"
        token = "make-up-a-long-secret-token"

      (replace the token with your own secret - the longer the better)
   c. Run frps.exe - it stays running in its console window.
   d. Open port 7000 (TCP) on that machine's firewall so clients
      from the internet can reach it.

2) ASK A FRIEND who has a public IP / VPS to run frps for you.
   They give you three values:  address, port (7000), token.

3) USE A PUBLIC FRP SERVICE
   Search for "free frp server" providers. They give you the same
   three values: address, port, token.

NOW, IN K BNG M HOSTER:
  a. Open the Network tab.
  b. Tick "Enable FRP tunnel".
  c. FRP server address:  the frps address (hostname or IP)
  d. FRP server port:     7000 (unless they said otherwise)
  e. FRP token:           the token from step 1b / friend / service
  f. Press Start Server. The tunnel comes up BEFORE the game server;
     if it fails, the server does NOT start and the log explains why.
  g. Friends join with BeamNG -> More... -> BeamMP -> Direct Connect
     using:  YOUR FRP ADDRESS : 30814
  h. When you stop the server, the tunnel stops too and the runtime
     config with your token is deleted.

PASSWORDS / SECURITY:
  - The token IS the password to your frps. Only share it with
    people you trust - anyone with it can tunnel through your server.
  - The token is never saved in plain text anywhere after the tunnel
    stops (the temporary config is deleted).

NOTE: by default the game port 30814 is used on both sides (local
and remote). If your frps forces different remote ports, that is
advanced setup - the provider will tell you.
"@
    [System.Windows.Forms.MessageBox]::Show($text, 'FRP setup guide', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Show-CgnatExplain {
    $text = @"
What is CGNAT and why can't I port-forward?

Your ISP does not give your router its own public internet address.
Instead you share ONE public IP with many customers.

Since the public IP is shared, your router's port-forward rules are
ignored by the ISP's big NAT device - it does NOT forward your port.
Nothing in the router or this tool can change that.

Your options (all on this Network tab):
 A) FRP tunnel - hosts through a remote frps server, no port
    forwarding needed at all. Press the "FRP setup guide" button in
    the FRP card to see how to get an frps server.
 B) Any VPN from the VPN tools list above - Radmin VPN, Hamachi,
    ZeroTier, Tailscale or Playit.gg. Friends install the SAME VPN,
    join your virtual network, then Direct Connect to the VPN IP
    shown in that row. Each row has Start / Download / Copy buttons.
 C) Contact your ISP and ask for a real public IP (often free or a
    small monthly fee) - then port forwarding will work.
 D) Rent a cheap VPS and run the BeamMP server there instead.
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

# ---------------------------------------------------------------------------------------
# MODS PAGE
# ---------------------------------------------------------------------------------------
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
    $p.BackColor = $Theme.bg

    $script:ModsListPanel = New-Object System.Windows.Forms.Panel
    $script:ModsListPanel.Dock = 'Fill'
    $script:ModsListPanel.BackColor = $Theme.bg
    $script:ModsListPanel.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)

    $lblOn = New-Lbl 'Enabled mods (click to select)' $Theme.green 9.5 18 $true
    $lblOn.Location = New-Object System.Drawing.Point(0, 2)
    $script:ModsListPanel.Controls.Add($lblOn)
    $script:ListEnabled = New-Object System.Windows.Forms.ListBox
    $script:ListEnabled.Location = New-Object System.Drawing.Point(0, 24)
    $script:ListEnabled.Size = New-Object System.Drawing.Size(470, 280)
    $script:ListEnabled.BackColor = $Theme.panel
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

    $lblOff = New-Lbl 'Disabled mods (click to select)' $Theme.yellow 9.5 18 $true
    $lblOff.Location = New-Object System.Drawing.Point(480, 2)
    $script:ModsListPanel.Controls.Add($lblOff)
    $script:ListDisabled = New-Object System.Windows.Forms.ListBox
    $script:ListDisabled.Location = New-Object System.Drawing.Point(480, 24)
    $script:ListDisabled.Size = New-Object System.Drawing.Size(470, 280)
    $script:ListDisabled.BackColor = $Theme.panel
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

    $script:ModsTip = New-Lbl 'Tip: Ctrl+click selects mods one by one, Shift+click selects a range, Ctrl+A selects all - like Windows Explorer. Disable / Enable acts on every selected mod.' $Theme.dim 8.5 18  $false 940
    $script:ModsTip.Dock = 'Bottom'
    $script:ModsTip.Height = 24
    $script:ModsListPanel.Controls.Add($script:ModsTip)

    $script:ModsTop = New-Object System.Windows.Forms.Panel
    $script:ModsTop.Dock = 'Top'
    $script:ModsTop.Height = 96
    $script:ModsTop.BackColor = $Theme.bg

    $head = New-Lbl 'Mod Manager' $Theme.blue 14 26 $true
    $head.Location = New-Object System.Drawing.Point(4, 2)
    $script:ModsTop.Controls.Add($head)
    $sub = New-Lbl 'Drop .zip mod files anywhere here to add them (they are scanned for executables first). Disabled mods are moved aside and are NOT loaded. .zip mods are synced to everyone who joins automatically.' $Theme.dim 9 20  $false 940
    $sub.Location = New-Object System.Drawing.Point(4, 30)
    $script:ModsTop.Controls.Add($sub)

    $btnDisable = New-Btn 'Disable selected' 'Move the selected enabled mod to Backups\mods (not loaded).' { ModAction 'disable' }
    $btnDisable.Size = New-Object System.Drawing.Size(130, 32)
    $btnDisable.Location = New-Object System.Drawing.Point(4, 54)
    $btnDisable.Tag = @{ X = 4; Y = 54; W = 130; H = 32 }
    $script:ModsTop.Controls.Add($btnDisable)

    $btnEnable = New-Btn 'Enable selected' 'Move the selected disabled mod back to the loaded folder.' { ModAction 'enable' }
    $btnEnable.Size = New-Object System.Drawing.Size(130, 32)
    $btnEnable.Location = New-Object System.Drawing.Point(140, 54)
    $btnEnable.Tag = @{ X = 140; Y = 54; W = 130; H = 32 }
    $script:ModsTop.Controls.Add($btnEnable)

    $btnScan = New-Btn 'Scan for suspicious files' 'Check all mods and zips for executables (.exe/.vbs/.cmd/...) and quarantine anything found.' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Scan-Mods)`n`$State.ModsRefresh = (Get-Date).ToString('o')" 'modscan' }
    $btnScan.Size = New-Object System.Drawing.Size(190, 32)
    $btnScan.Location = New-Object System.Drawing.Point(276, 54)
    $btnScan.Tag = @{ X = 276; Y = 54; W = 190; H = 32 }
    $script:ModsTop.Controls.Add($btnScan)

    $btnOpen = New-Btn 'Open Folder' 'Open the mods folder in Explorer.' { Start-Process explorer.exe -ArgumentList ('"' + ($script:RootDir + 'Resources\Client') + '"') }
    $btnOpen.Size = New-Object System.Drawing.Size(110, 32)
    $btnOpen.Location = New-Object System.Drawing.Point(472, 54)
    $btnOpen.Tag = @{ X = 472; Y = 54; W = 110; H = 32 }
    $script:ModsTop.Controls.Add($btnOpen)

    $btnRefresh = New-Btn 'Refresh list' 'Reload the mod list from disk.' { Refresh-ModListsAsync }
    $btnRefresh.Size = New-Object System.Drawing.Size(110, 32)
    $btnRefresh.Location = New-Object System.Drawing.Point(588, 54)
    $btnRefresh.Tag = @{ X = 588; Y = 54; W = 110; H = 32 }
    $script:ModsTop.Controls.Add($btnRefresh)

    $p.Controls.Add($script:ModsListPanel)
    $p.Controls.Add($script:ModsTop)
    $script:Content.Controls.Add($p)
    $script:PageLayout = { Layout-Mods }
    & $script:PageLayout
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
        $btnY = SY(54)
        foreach ($c in $script:ModsTop.Controls) {
            if ($c -is [System.Windows.Forms.Label] -and $c.Width -gt 400) {
                $c.Width = $script:ModsTop.ClientSize.Width - 8
                $m = Measure-Text $c.Text $c.Font $c.Width
                $c.Height = [int][math]::Max(20, $m.Lines * 20)
                $btnY = $c.Location.Y + $c.Height + 8
            }
        }
        $btnBottom = $btnY
        foreach ($c in $script:ModsTop.Controls) {
            if ($c -is [System.Windows.Forms.Button] -and $c.Tag -is [hashtable] -and $c.Tag.ContainsKey('X')) {
                $c.Size = New-Object System.Drawing.Size((SX $c.Tag.W), (SY $c.Tag.H))
                $c.Location = New-Object System.Drawing.Point((SX $c.Tag.X), $btnY)
                $btnBottom = [math]::Max($btnBottom, $btnY + (SY $c.Tag.H))
            }
        }
        $script:ModsTop.Height = [int][math]::Max($script:ModsTop.Height, $btnBottom + 6)
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

# ---------------------------------------------------------------------------------------
# TRANSFER PAGE (export/split server mods, install downloaded mods, selective delete)
# ---------------------------------------------------------------------------------------
function Show-TransferPage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg

    $top = New-PageTop $p 'Transfer' 'Copy your server mods to friends (split into cloud-sized parts), install downloaded mods and delete only the ones you pick.'
    $p.Controls.Add($top.Bar)

    $stack = New-CardStack $p
    $cards = @()

    $card = New-Card 'Host tools - export your server mods' 'Scans Resources\Client and COPIES every .zip into an Export folder inside the destination you pick, split into parts that fit free cloud accounts (Copy-Item only - zips are never unpacked).'
    $script:LblTransferScan = New-Lbl 'Press "Scan Server Mods" to see what is ready to export.' $Theme.dim 9.5 22
    $script:LblTransferScan.AutoSize = $true
    Add-RowFull $card $script:LblTransferScan

    $bar = New-ButtonBar
    $btnScan = New-Btn 'Scan Server Mods' 'Counts every .zip in Resources\Client and totals their size - nothing is copied or changed.' { Start-TransferScan }
    $btnScan.Size = New-Object System.Drawing.Size(150, 34)
    $bar.Controls.Add($btnScan)
    Add-RowFull $card $bar

    $bar0 = New-ButtonBar
    $btnDest = New-Btn 'Select Export Destination' 'Pick the folder that receives a new "Export" folder with the split parts inside.' { Select-TransferDest }
    $btnDest.Size = New-Object System.Drawing.Size(180, 34)
    $bar0.Controls.Add($btnDest)
    Add-RowFull $card $bar0
    $script:LblExportDest = New-Lbl ('Export Path: ' + $(if ($script:TransferDest) { $script:TransferDest } else { '(none selected yet)' })) $(if ($script:TransferDest) { $Theme.green } else { $Theme.yellow }) 9 22
    $script:LblExportDest.AutoSize = $true
    Add-RowFull $card $script:LblExportDest

    $script:CmbChunkSize = New-Object System.Windows.Forms.ComboBox
    $script:CmbChunkSize.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $script:CmbChunkSize.BackColor = $Theme.bg
    $script:CmbChunkSize.ForeColor = [System.Drawing.Color]::White
    $script:CmbChunkSize.FlatStyle = 'Flat'
    $script:CmbChunkSize.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    [void]$script:CmbChunkSize.Items.AddRange(@('5GB', '10GB', '15GB', '20GB', '25GB'))
    $script:CmbChunkSize.SelectedIndex = 2
    Add-Row $card 'Max folder size' $script:CmbChunkSize

    $barE = New-ButtonBar
    $btnExport = New-Btn 'Export Server Mods' 'Copies every .zip into Export\Part_1, Part_2... inside your selected destination so each folder stays under the chosen size. Uses Copy-Item only - your live mods stay untouched.' { Start-TransferExport }
    $btnExport.Size = New-Object System.Drawing.Size(170, 34)
    $barE.Controls.Add($btnExport)
    Add-RowFull $card $barE

    $bar2 = New-ButtonBar
    $btnDrive = New-Btn 'Upload to Google Drive (15GB)' 'Opens Google Drive in your browser - drag the Export parts that fit 15GB into it.' { Start-Process 'https://drive.google.com/drive/my-drive' }
    $btnDrive.Size = New-Object System.Drawing.Size(200, 34)
    $bar2.Controls.Add($btnDrive)
    $btnMega = New-Btn 'Upload to Mega.io (20GB Free)' 'Opens Mega.io in your browser - drag the Export parts that fit 20GB into it.' { Start-Process 'https://mega.io/' }
    $btnMega.Size = New-Object System.Drawing.Size(190, 34)
    $bar2.Controls.Add($btnMega)
    Add-RowFull $card $bar2

    Add-RowNote $card 'An "Export" folder with Part_1, Part_2, ... is created inside your selected destination. Mods are COPIED, never moved or unzipped.' $Theme.dim | Out-Null
    $cards += $card

    $card = New-Card 'Player tools - install downloaded mods' 'Moves every .zip from a folder you pick into the BeamMP client mods folder. All other file types are ignored.'
    $script:LblClientDir = New-Lbl 'Client mods folder: (scan to find it)' $Theme.dim 9 20
    Add-RowFull $card $script:LblClientDir
    $bar = New-ButtonBar
    $btnInstall = New-Btn 'Install Downloaded Mods' 'Pick a folder: every .zip inside it is MOVED into the client mods folder (BeamMP Launcher Resources, or BeamNG.drive multiplayer mods).' { Start-TransferInstall }
    $btnInstall.Size = New-Object System.Drawing.Size(180, 34)
    $bar.Controls.Add($btnInstall)
    Add-RowFull $card $bar
    $cards += $card

    $card = New-Card 'Player tools - selective mod deletion' 'Deletes ONLY the mods you tick. Unticked mods (for example other servers) are never touched.'
    $script:ClbClientMods = New-Object System.Windows.Forms.CheckedListBox
    $script:ClbClientMods.Height = 170
    $script:ClbClientMods.BackColor = $Theme.bg
    $script:ClbClientMods.ForeColor = [System.Drawing.Color]::White
    $script:ClbClientMods.BorderStyle = 'FixedSingle'
    $script:ClbClientMods.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $script:ClbClientMods.CheckOnClick = $true
    Add-RowFull $card $script:ClbClientMods
    $bar = New-ButtonBar
    $btnRefresh = New-Btn 'Refresh Installed Mods' 'Rescans the client mods folder and lists every installed .zip with its size.' { Start-TransferRefresh }
    $btnRefresh.Size = New-Object System.Drawing.Size(160, 34)
    $bar.Controls.Add($btnRefresh)
    $btnSelAll = New-Btn 'Select All' 'Ticks every mod in the list.' { Set-ClientModChecks $true }
    $btnSelAll.Size = New-Object System.Drawing.Size(100, 34)
    $bar.Controls.Add($btnSelAll)
    $btnSelNone = New-Btn 'Deselect All' 'Unticks every mod in the list.' { Set-ClientModChecks $false }
    $btnSelNone.Size = New-Object System.Drawing.Size(110, 34)
    $bar.Controls.Add($btnSelNone)
    $btnDelete = New-Btn 'Delete Selected Mods' 'Removes ONLY the ticked mods from this computer - after a confirmation. Unticked mods stay.' { Start-TransferDelete }
    $btnDelete.Size = New-Object System.Drawing.Size(170, 34)
    $btnDelete.BackColor = [System.Drawing.Color]::FromArgb(122, 26, 26)
    $btnDelete.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(220, 60, 60)
    $btnDelete.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(158, 34, 34)
    $btnDelete.ForeColor = [System.Drawing.Color]::White
    $bar.Controls.Add($btnDelete)
    Add-RowFull $card $bar
    Add-RowNote $card 'Refreshing the list never deletes anything - files are only removed when you tick them and press "Delete Selected Mods".' $Theme.dim | Out-Null
    $cards += $card

    & $script:MountCards $cards $stack.Content
    $script:Content.Controls.Add($p)
    $script:ClientModItems = @()
    Start-TransferRefresh
}

function Start-TransferScan {
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.TransferScan = Get-TransferScan" 'tscan'
}

function Update-TransferScanUi {
    if (-not $script:LblTransferScan -or -not $script:State.TransferScan) { return }
    $s = $script:State.TransferScan
    $gb = '{0:N1} GB' -f ($s.TotalBytes / 1GB)
    $script:LblTransferScan.Text = "Ready to Export: $($s.Count) mods | Total Size: $gb"
    $script:LblTransferScan.ForeColor = $(if ($s.Count) { $Theme.green } else { $Theme.yellow })
}

function Select-TransferDest {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Pick the folder that receives the Export folder (with the split parts)'
    if ($dlg.ShowDialog($script:Form) -ne 'OK') { return }
    $script:TransferDest = $dlg.SelectedPath
    if ($script:LblExportDest) {
        $script:LblExportDest.Text = "Export Path: $($script:TransferDest)"
        $script:LblExportDest.ForeColor = $Theme.green
    }
    Add-Log "[INFO] Export destination: $($script:TransferDest)"
}

function Start-TransferExport {
    if (-not $script:TransferDest) {
        [System.Windows.Forms.MessageBox]::Show('Select an Export Destination first.', 'Export', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $script:TransferDest)) {
        [System.Windows.Forms.MessageBox]::Show("The export destination no longer exists:`n$($script:TransferDest)", 'Export', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    $g = 15
    $sel = [string]$script:CmbChunkSize.SelectedItem
    if ($sel -match '^\s*(\d+)') { $g = [int]$Matches[1] }
    $destStr = QStr $script:TransferDest
    Add-Log "[INFO] Exporting server mods in $g GB parts to $($script:TransferDest)\Export..."
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.TransferExport = Export-ServerMods $destStr $g" 'texport'
}

function Update-TransferExportUi {
    if (-not $script:State.TransferExport) { return }
    $r = $script:State.TransferExport
    Add-Log "[INFO] $($r.Summary)"
    if (@($r.Locked).Count) {
        [System.Windows.Forms.MessageBox]::Show("$(@($r.Locked).Count) mod file(s) are locked or in use. Close BeamMP / BeamNG.drive, then press Export again.`nLocked: $(@($r.Locked) -join ', ')", 'Export', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
}

function Start-TransferInstall {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Pick the folder that contains the downloaded .zip mods (only .zip files are installed)'
    if ($dlg.ShowDialog($script:Form) -ne 'OK') { return }
    $fromStr = QStr $dlg.SelectedPath
    Add-Log "[INFO] Installing mods from $($dlg.SelectedPath)..."
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.TransferInstall = Install-ClientMods $fromStr" 'tinstall'
}

function Update-TransferInstallUi {
    if (-not $script:State.TransferInstall) { return }
    $r = $script:State.TransferInstall
    Add-Log "[INFO] $($r.Summary)"
    if (@($r.Locked).Count) {
        [System.Windows.Forms.MessageBox]::Show("$(@($r.Locked).Count) mod file(s) are locked or in use. Close BeamMP / BeamNG.drive, then try installing again.`nLocked: $(@($r.Locked) -join ', ')", 'Install mods', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
    Start-TransferRefresh
}

function Start-TransferRefresh {
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.TransferClient = Get-ClientModsList" 'trefresh'
}

function Populate-ClientModList {
    if (-not $script:ClbClientMods -or -not $script:State.TransferClient) { return }
    $info = $script:State.TransferClient
    $script:ClbClientMods.Items.Clear()
    $script:ClientModItems = @()
    if (-not $info -or -not $info.Path) {
        $script:LblClientDir.Text = 'Client mods folder: not found - install BeamMP (or BeamNG.drive) first.'
        $script:LblClientDir.ForeColor = $Theme.yellow
        return
    }
    $script:LblClientDir.Text = "Client mods folder: $($info.Path)"
    $script:LblClientDir.ForeColor = $Theme.dim
    if (-not @($info.Mods).Count) {
        [void]$script:ClbClientMods.Items.Add('(no .zip mods installed)')
        return
    }
    foreach ($m in @($info.Mods)) {
        $display = "{0}  ({1:N1} MB)" -f $m.Name, ($m.Length / 1MB)
        [void]$script:ClbClientMods.Items.Add($display)
        $script:ClientModItems += [pscustomobject]@{ Name = $m.Name; Path = $m.FullName }
    }
    Add-Log "[INFO] Client mods: $(@($info.Mods).Count) .zip file(s) installed."
}

function Set-ClientModChecks([bool]$On) {
    if (-not $script:ClbClientMods) { return }
    for ($i = 0; $i -lt $script:ClbClientMods.Items.Count; $i++) { $script:ClbClientMods.SetItemChecked($i, $On) }
}

function Start-TransferDelete {
    if (-not $script:ClbClientMods) { return }
    $names = @()
    for ($i = 0; $i -lt $script:ClbClientMods.Items.Count; $i++) {
        if ($script:ClbClientMods.GetItemChecked($i) -and $i -lt $script:ClientModItems.Count) { $names += $script:ClientModItems[$i].Name }
    }
    if (-not $names.Count) { Add-Log '[INFO] Tick at least one mod first (or press Select All).'; return }
    $shown = @($names | Select-Object -First 5) -join ', '
    if ($names.Count -gt 5) { $shown += ", ... (+$($names.Count - 5) more)" }
    $r = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to delete these $($names.Count) mod(s)?`n`n$shown", 'Delete mods', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($r -ne 'Yes') { return }
    $argStr = ($names | ForEach-Object { QStr $_ }) -join ', '
    Add-Log "[INFO] Deleting $($names.Count) selected mod(s)..."
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.TransferDelete = Remove-ClientMods @($argStr)" 'tdel'
}

function Update-TransferDeleteUi {
    if (-not $script:State.TransferDelete) { return }
    $r = $script:State.TransferDelete
    Add-Log "[INFO] $($r.Summary)"
    if (@($r.Locked).Count) {
        [System.Windows.Forms.MessageBox]::Show("$(@($r.Locked).Count) mod file(s) are locked or in use. Close BeamMP / BeamNG.drive, then delete again.`nLocked: $(@($r.Locked) -join ', ')", 'Delete mods', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
    Start-TransferRefresh
}

# ---------------------------------------------------------------------------------------
# GUIDE PAGE
# ---------------------------------------------------------------------------------------
function Add-GuideLine([string]$Text, [string]$Color = 'text', [bool]$Bold = $false, [float]$Size = 10, [int]$Indent = -1) {
    if (-not $script:GuideBox) { return }
    if (-not $script:GuideBox.IsHandleCreated) { [void]$script:GuideBox.Handle }
    if ($Indent -lt 0) { $Indent = if ($Bold -and $Size -ge 12) { 0 } else { 24 } }
    $script:GuideBox.SelectionStart = $script:GuideBox.TextLength
    $script:GuideBox.SelectionLength = 0
    $script:GuideBox.SelectionIndent = $Indent
    $script:GuideBox.SelectionRightIndent = 6
    $script:GuideBox.SelectionColor = $Theme[$Color]
    $script:GuideBox.SelectionFont = New-Object System.Drawing.Font('Segoe UI', $Size, $(if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }))
    $script:GuideBox.AppendText($Text + [Environment]::NewLine)
}

function Show-GuidePage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg

    $top = New-PageTop $p 'Guide' 'Everything you need to know - no files to open.'
    $p.Controls.Add($top.Bar)

    $script:GuideCard = New-Object System.Windows.Forms.Panel
    $script:GuideCard.Dock = 'Fill'
    $script:GuideCard.BackColor = $Theme.panel
    $script:GuideCard.Padding = New-Object System.Windows.Forms.Padding(22, 16, 22, 16)
    $script:GuideCard.Margin = New-Object System.Windows.Forms.Padding(10, 0, 10, 10)
    $p.Controls.Add($script:GuideCard)

    $script:GuideBox = New-Object System.Windows.Forms.RichTextBox
    $script:GuideBox.ReadOnly = $true
    $script:GuideBox.DetectUrls = $false
    $script:GuideBox.BackColor = $Theme.panel
    $script:GuideBox.ForeColor = $Theme.text
    $script:GuideBox.BorderStyle = 'None'
    $script:GuideBox.WordWrap = $true
    $script:GuideBox.ScrollBars = 'Vertical'
    $script:GuideBox.Dock = 'Fill'
    $script:GuideBox.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    [void]$script:GuideBox.Handle
    $script:GuideBox.ZoomFactor = 1.0
    $script:GuideCard.Controls.Add($script:GuideBox)

    Add-GuideLine 'STEP 1  -  START THE SERVER' 'yellow' $true 12
    Add-GuideLine '  Double-click Start_Here.bat - this window opens, on the HOME'
    Add-GuideLine '  page (Ctrl+H): server status and every address your friends'
    Add-GuideLine '  can use.'
    Add-GuideLine '  First time only: a small window asks for your server key.'
    Add-GuideLine '      1. Get your free key at https://keymaster.beammp.com'
    Add-GuideLine '      2. Paste it and click Save - it is stored privately on your PC'
    Add-GuideLine '  Click Start Server (or Ctrl+S). The BeamMP Launcher opens automatically.'
    Add-GuideLine '  In BeamNG: More... -> BeamMP -> Direct Connect, use the address'
    Add-GuideLine '  shown under "THIS PC (test it now)" to test on your own PC.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 2  -  HOW YOUR FRIENDS CONNECT' 'yellow' $true 12
    Add-GuideLine '  Send them ONE line from the Home page. In BeamNG they open'
    Add-GuideLine '  More... -> BeamMP -> Direct Connect and type the address you send.'
    Add-GuideLine '      - "THIS PC (test it now)"       just testing on your own machine'
    Add-GuideLine '      - "Friends (same WiFi)"         LAN - same network only'
    Add-GuideLine '      - "Friends (FRP tunnel)"        works anywhere, no port'
    Add-GuideLine '        forwarding needed (Network tab)'
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
    Add-GuideLine '  marks the internet line with "(PRIVATE server...)".'
    Add-GuideLine '  Private does NOT add a password - anyone with the address'
    Add-GuideLine '  (IP:port) can still join. It applies on the next server start.'
    Add-GuideLine '  Inviting friends to a private server is one press: on the Home'
    Add-GuideLine '  page click "Copy invite (private)" - it copies the full message'
    Add-GuideLine '  (address + connect steps) - paste it into chat. No typing.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 4  -  CANNOT CONNECT? RUN FIX' 'yellow' $true 12
    Add-GuideLine '  Click Fix (or Ctrl+F). It checks everything - key, port,'
    Add-GuideLine '  firewall, mods, disk space, VPNs, CGNAT, reachability - and'
    Add-GuideLine '  shows a summary of what is OK and what needs attention.'
    Add-GuideLine '  Press "Fix all possible" for one-click repairs (busy port,'
    Add-GuideLine '  firewall, broken map, UPnP). Anything left needs you -'
    Add-GuideLine '  follow the instructions on each row.'
    Add-GuideLine '  If your ISP uses CGNAT, port forwarding can NEVER work:'
    Add-GuideLine '  use the FRP tunnel or a VPN (Network tab) - both bypass CGNAT.'
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
    Add-GuideLine '  Click Settings (or press Ctrl+T): one scroll with everything -'
    Add-GuideLine '  server name, players, cars, description and tags (shown in the'
    Add-GuideLine '  BeamMP list), visibility, your server key, the map picker with'
    Add-GuideLine '  search, port + IP lock, optional behavior switches and presets.'
    Add-GuideLine '  Change anything and press "Save settings" (top right of the page)'
    Add-GuideLine '  - it applies on the next start. No config files needed.'
    Add-GuideLine '  The map box has a search field - type to filter long map lists.'
    Add-GuideLine '  Pick a map and press Apply map - vanilla maps work instantly,'
    Add-GuideLine '  and map MODS you have are sent to players automatically when'
    Add-GuideLine '  they join. NEVER change the map from inside the game - it'
    Add-GuideLine '  breaks the multiplayer screen. Always here.'
    Add-GuideLine '  PRESETS: save a whole setup (all settings + your enabled mods)'
    Add-GuideLine '  under a name - e.g. "Drift night" or "Crash event" - and load it'
    Add-GuideLine '  back in one press. Presets are stored privately in Server\Presets.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 7  -  NETWORK: FRP + VPNs' 'yellow' $true 12
    Add-GuideLine '  Click Network (or press Ctrl+V) for everything about how friends'
    Add-GuideLine '  reach you.'
    Add-GuideLine '  FRP TUNNEL - hosts through a remote frps server, no port'
    Add-GuideLine '  forwarding, works behind CGNAT. To set it up:'
    Add-GuideLine '      1. Press "FRP setup guide" in the FRP card - it explains'
    Add-GuideLine '         how to run your own frps (or use a friend''s / a public'
    Add-GuideLine '         one) and exactly what to type in each box.'
    Add-GuideLine '      2. You need three values: server address, port (usually'
    Add-GuideLine '         7000) and a token.'
    Add-GuideLine '      3. Tick "Enable FRP tunnel", fill the boxes, press Start.'
    Add-GuideLine '         Friends join via Direct Connect to your FRP address:30814.'
    Add-GuideLine '  VPN TOOLS - Radmin VPN / Hamachi / ZeroTier / Tailscale and'
    Add-GuideLine '  Playit.gg each have their own row with Start / Download / Stop'
    Add-GuideLine '  / Copy buttons. Friends must use the SAME VPN as the IP you'
    Add-GuideLine '  send them. VPNs are for trusted friends only (they join your'
    Add-GuideLine '  virtual LAN).'
    Add-GuideLine '  Port forwarding (Fix) is still the #1 way to host for strangers;'
    Add-GuideLine '  FRP and VPNs are the fallbacks when forwarding cannot work.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 8  -  BEFORE SHARING THE FOLDER' 'yellow' $true 12
    Add-GuideLine '  Click More -> Clean Info - it wipes your key, webhook, logs,'
    Add-GuideLine '  backups and IP files so the folder is safe to zip and share.'
    Add-GuideLine '  NEVER share your key or your webhook URL.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 9  -  KEEPING THE APP UPDATED' 'yellow' $true 12
    Add-GuideLine '  Every time this window opens, the tool checks GitHub for a new'
    Add-GuideLine '  version. If one exists it offers to download and install it'
    Add-GuideLine '  automatically - your key, mods and settings are kept, and old'
    Add-GuideLine '  downloaded versions are deleted.'
    Add-GuideLine ''
    Add-GuideLine 'STEP 10  -  LOST WINDOWS + REPORTING A PROBLEM' 'yellow' $true 12
    Add-GuideLine '  The server console opens minimized on purpose. If you ever'
    Add-GuideLine '  wonder where a window went, click More -> Extra (or Ctrl+E): it'
    Add-GuideLine '  lists every window the tool opened, with a "Show window" button'
    Add-GuideLine '  that restores it to the front.'
    Add-GuideLine '  Same page has "Submit issue": one press copies a ready-made'
    Add-GuideLine '  report (app version, system, recent log lines) and opens the'
    Add-GuideLine '  GitHub issues page - paste it there. Nothing is sent on its own.'
    Add-GuideLine ''

    $script:Content.Controls.Add($p)
}

# ---------------------------------------------------------------------------------------
# EXTRA PAGE (open windows + submit issue)
# ---------------------------------------------------------------------------------------
if (-not ('KBWin' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class KBWin {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
}
'@
}

# Every tool-related window still open, so none ever gets "lost".
function Get-ToolWindows {
    $out = @()
    $srv = Get-Process -Name 'BeamMP-Server' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($srv) { $out += [pscustomobject]@{ Name = 'Server console (BeamMP-Server)'; Proc = $srv; Hwnd = $srv.MainWindowHandle } }
    $ln = Get-Process -Name 'BeamMP-Launcher' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ln) { $out += [pscustomobject]@{ Name = 'BeamMP Launcher (friends list / join screen)'; Proc = $ln; Hwnd = $ln.MainWindowHandle } }
    $be = Get-Process -Name 'BeamNG.drive' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($be) { $out += [pscustomobject]@{ Name = 'BeamNG.drive (the game)'; Proc = $be; Hwnd = $be.MainWindowHandle } }
    return $out
}

function Show-ExtraPage {
    $script:Content.Controls.Clear()
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg

    $top = New-PageTop $p 'Extra' 'Open windows (restore them from here) and problem reporting.'
    $p.Controls.Add($top.Bar)

    $stack = New-CardStack $p
    $cards = @()

    $card = New-Card 'Windows opened by the tool' 'The server console opens minimized on purpose - restore it from this list anytime.'
    $script:WinRows = New-Object System.Windows.Forms.Panel
    $script:WinRows.AutoSize = $true
    $script:WinRows.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    Add-RowFull $card $script:WinRows
    $cards += $card

    $card = New-Card 'Report a problem' 'Copies a ready-made report to your clipboard and opens the GitHub issues page - you review and paste it yourself.'
    $btnIssue = New-Btn 'Submit issue (copies report, opens GitHub)' 'One press: copies the diagnostic report to your clipboard and opens the GitHub issues page - you just paste it there.' { Submit-Issue }
    $btnIssue.Size = New-Object System.Drawing.Size(330, 38)
    $btnIssue.BackColor = [System.Drawing.Color]::FromArgb(122, 26, 26)
    $btnIssue.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(158, 34, 34)
    $btnIssue.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(220, 60, 60)
    $btnIssue.ForeColor = [System.Drawing.Color]::White
    Add-RowFull $card $btnIssue
    $script:IssueLog = New-Lbl '(activity appears here)' $Theme.dim 8.5 30
    $script:IssueLog.Dock = 'Fill'
    $script:IssueLog.AutoSize = $true
    Add-RowFull $card $script:IssueLog
    $cards += $card

    & $script:MountCards $cards $stack.Content
    $script:Content.Controls.Add($p)
    Refresh-WinRows
}

# Rebuilds the window list rows inside the Extra page.
function Refresh-WinRows {
    try {
        $script:WinRows.Controls.Clear()
        $wins = Get-ToolWindows
        $rows = @()
        if (-not $wins.Count) {
            $lbl = New-Lbl 'No tool windows are open right now. (Start the server and the list appears here.)' $Theme.dim 9 20
            $lbl.AutoSize = $true
            $rows += $lbl
        } else {
            foreach ($w in $wins) {
                $row = New-Object System.Windows.Forms.Panel
                $row.Dock = 'Top'
                $row.Height = 42
                $row.BackColor = $Theme.bg
                $lbl = New-Lbl $w.Name $Theme.text 9 20
                $lbl.Dock = 'Fill'
                $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
                $row.Controls.Add($lbl)
                $show = New-Btn 'Show window' 'Restore this window so you can see it. The server console was opened minimized on purpose.' { }
                $show.Dock = 'Right'
                $show.Width = 110
                $show.Height = 30
                $show.Tag = $w.Hwnd
                $show.Add_Click({
                    try {
                        $hwnd = [IntPtr]$this.Tag
                        if ($hwnd -eq [IntPtr]::Zero) { Add-Log '[INFO] This window has no visible window - nothing to show.'; return }
                        [KBWin]::ShowWindow($hwnd, 9) | Out-Null
                        [KBWin]::SetForegroundWindow($hwnd) | Out-Null
                        Add-Log '[OK] Window brought to the front.'
                    } catch { Add-Log "[ERROR] Could not show window: $_" }
                })
                $row.Controls.Add($show)
                $rows += $row
            }
        }
        for ($i = $rows.Count - 1; $i -ge 0; $i--) { $script:WinRows.Controls.Add($rows[$i]) }
    } catch { Write-Log "[LAYOUT-ERROR] WINROWS $($_.Exception.Message)" }
}

# Builds the report text the user pastes into GitHub issues.
function Get-IssueText {
    $l = @()
    $l += 'K BNG M Hoster - problem report (v' + $script:AppVersion + ')'
    $l += 'Generated: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    $l += ''
    $l += '=== System ==='
    $l += 'OS: ' + [System.Environment]::OSVersion.VersionString
    $l += 'PowerShell: ' + $PSVersionTable.PSVersion.ToString()
    $l += 'App folder: ' + $script:AppDir
    $l += 'Server port: ' + (Get-ServerPort)
    $l += 'Server running: ' + $(if ($script:State.Running) { 'yes' } else { 'no' })
    $l += ''
    $l += '=== What were you doing when it happened? (write here) ==='
    $l += ''
    $l += '=== Recent tool activity (last 25 log lines) ==='
    $logF = Join-Path ($script:ServerDir + 'Logs') 'launcher.log'
    if (Test-Path -LiteralPath $logF) { $l += @(Get-Content -LiteralPath $logF -Tail 25) }
    else { $l += '(no tool log yet)' }
    $l += ''
    $l += '=== Server log (last 20 lines) ==='
    $srvLog = Join-Path $script:ServerDir 'Server.log'
    if (Test-Path -LiteralPath $srvLog) { $l += @(Get-Content -LiteralPath $srvLog -Tail 20) }
    else { $l += '(no server log yet - the server has not run yet)' }
    return ($l -join [Environment]::NewLine)
}

function Submit-Issue {
    try {
        $text = Get-IssueText
        [System.Windows.Forms.Clipboard]::SetText($text)
        if ($script:IssueLog) { $script:IssueLog.Text = '[OK] Report copied to your clipboard.' }
        Add-Log '[OK] Problem report copied to the clipboard.'
        Start-Process 'https://github.com/Kinan0713/K-BNG-M-Hoster/issues/new'
        if ($script:IssueLog) { $script:IssueLog.Text += "  GitHub opened - paste it there (Ctrl+V)." }
        Add-Log '[INFO] GitHub issues page opened - paste the report there.'
    } catch {
        Add-Log "[ERROR] Could not prepare the report: $_"
        if ($script:IssueLog) { $script:IssueLog.Text = '[ERROR] Could not copy - see the log.' }
    }
}

# ---------------------------------------------------------------------------------------
# DIALOGS
# ---------------------------------------------------------------------------------------
$LicenseFullText = @'
PROPRIETARY LICENSE AGREEMENT (EULA)
Product: K BNG M Hoster
Licensor / Copyright Holder: Kinan (@raed713)
Copyright (c) 2026 Kinan. All Rights Reserved.

IMPORTANT — READ CAREFULLY: BY DOWNLOADING, INSTALLING, ACCESSING, OR USING THE
SOFTWARE, YOU ACCEPT AND AGREE TO THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
DOWNLOAD, INSTALL, OR USE THE SOFTWARE.

1. DEFINITIONS
1.1 "Software" means the K BNG M Hoster product and all components including
    executables, packaged scripts, compiled files, configuration files, assets,
    documentation, and all materials distributed by the Licensor.
1.2 "Graphical User Interface (GUI)" means the complete, fully-automated
    user-facing application that launches when executing start_here.bat. The
    GUI is the sole and exclusive interface through which users interact with
    and access all features, settings, customization options, mods, and server
    management capabilities.
1.3 "Licensor" means Kinan (@raed713), the copyright holder and creator.
    "Licensee" means any person or entity that downloads, installs, accesses,
    or uses the Software.

2. LICENSE GRANT — LIMITED USE
2.1 Subject to strict compliance with this Agreement, the Licensor grants the
    Licensee a limited, revocable, non-exclusive, non-transferable,
    non-sublicensable license to:
    (a) execute start_here.bat to launch the Software; and
    (b) use the Software exclusively through the automatic Graphical User
        Interface (GUI) for personal, non-commercial use only.
2.2 All features, settings, customization options, mods, and server management
    are fully accessible and completely automated within the GUI. The Licensee
    may only interact with the Software through the GUI.
2.3 All other rights remain reserved to the Licensor. Any use not expressly
    permitted by Section 2.1 is strictly prohibited.

3. PROHIBITED CONDUCT
The Licensee shall not, directly or indirectly:
3.1 Modify, patch, adapt, translate, reverse-engineer, or create derivative
    works of the Software, including but not limited to the start_here.bat
    file, the GUI, configuration files, scripts, libraries, or any other
    components.
3.2 Access, view, edit, or manipulate any files or the file system in any way
    outside the GUI, including but not limited to configuration files, resource
    directories, database files, or any internal data.
3.3 Decompile, disassemble, obfuscate, or attempt to derive the source code,
    algorithms, internal logic, or proprietary methods of the Software or the
    GUI.
3.4 Redistribute, reupload, repost, mirror, fork, publish, share, sell,
    sublicense, lease, rent, lend, transfer, or otherwise make the Software or
    any portion of it available to any third party by any means, except by
    directing others to the official GitHub Releases page at
    https://github.com/Kinan0713/K-BNG-M-Hoster/releases
3.5 Use the Software as part of any paid hosting service, subscription service,
    commercial product, or business offering without the Licensor's prior
    written permission.
3.6 Remove, alter, obscure, or bypass any attribution notice, copyright notice,
    or license text that identifies the Licensor (including the name "Kinan"
    and the handle @raed713).
3.7 Attempt to circumvent, disable, or interfere with any security features,
    copy protection, or access controls built into the Software or GUI.

4. PERMITTED USER ACTIONS (CLARIFICATION)
4.1 The Licensee may ONLY:
    (a) execute start_here.bat to launch the Software; and
    (b) interact exclusively with the automatic Graphical User Interface (GUI)
        to access and use all available features.
4.2 The GUI provides complete automation and all necessary functionality. No
    manual configuration, file editing, or direct file system access is
    required or permitted. Users accomplish all tasks through the GUI.
4.3 Any interaction with the file system, configuration files, or components
    outside the GUI is strictly prohibited and constitutes a breach of this
    Agreement.

5. INTELLECTUAL PROPERTY RIGHTS
5.1 All intellectual property rights in the Software, including but not limited
    to copyrights, patents, trademarks, trade secrets, and proprietary know-how,
    belong exclusively to the Licensor.
5.2 The Licensee acquires no ownership rights to the Software, only a limited
    license to use it as expressly permitted by this Agreement.

6. TERMINATION
6.1 The Licensor may terminate this license immediately upon notice if the
    Licensee breaches any term of this Agreement.
6.2 Upon termination, the Licensee must immediately cease all use of the
    Software and delete all copies of the Software from all devices.
6.3 Sections 3, 5, 6.3, 7, 8, 9, and 10 survive termination of this Agreement.

7. DISCLAIMER OF WARRANTY
7.1 THE SOFTWARE IS PROVIDED "AS IS" AND "AS AVAILABLE", WITHOUT WARRANTY OF ANY
    KIND, EXPRESS OR IMPLIED. THE LICENSOR DISCLAIMS ALL WARRANTIES, INCLUDING
    BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
    PURPOSE, AND NON-INFRINGEMENT.
7.2 THE LICENSOR DOES NOT WARRANT THAT THE SOFTWARE WILL FUNCTION WITHOUT
    INTERRUPTION OR ERROR, OR THAT ALL DEFECTS WILL BE CORRECTED.
7.3 THE ENTIRE RISK ARISING OUT OF THE USE AND PERFORMANCE OF THE SOFTWARE
    REMAINS WITH THE LICENSEE.

8. LIMITATION OF LIABILITY
8.1 TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THE LICENSOR SHALL NOT
    BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, PUNITIVE,
    OR EXEMPLARY DAMAGES, OR FOR ANY LOSS OF PROFITS, REVENUE, DATA, OR
    GOODWILL, ARISING OUT OF OR RELATED TO THE USE OF OR INABILITY TO USE THE
    SOFTWARE, EVEN IF THE LICENSOR HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH
    DAMAGES.
8.2 THE LICENSOR'S TOTAL LIABILITY UNDER THIS AGREEMENT SHALL NOT EXCEED THE
    AMOUNT PAID BY THE LICENSEE FOR THE SOFTWARE, IF ANY.

9. ENFORCEMENT AND GOVERNING LAW
9.1 This Agreement is governed by and construed in accordance with the laws of
    Sweden, without regard to its conflict-of-law principles.
9.2 The Licensor may seek to enforce this Agreement, including through injunctive
    relief and damages, in any court of competent jurisdiction where the
    Licensee resides, where the Software is used, where a breach has occurred,
    or in any other jurisdiction where enforcement is possible.
9.3 If any provision of this Agreement is found to be unenforceable, such
    provision shall be modified to the minimum extent necessary to make it
    enforceable, and the remaining provisions shall remain in full force.

10. CONTACT AND DISPUTE RESOLUTION
10.1 For legal inquiries, permissions requests, licensing questions, and DMCA
     notices, please submit through the GitHub Issues page of the official
     repository: https://github.com/Kinan0713/K-BNG-M-Hoster/issues
10.2 The Licensor reserves the right to take legal action against any party
     that violates this Agreement, including seeking damages, injunctive relief,
     and recovery of attorney fees and costs.

11. GENERAL PROVISIONS
11.1 This Agreement constitutes the entire and exclusive agreement between the
     parties regarding the Software and supersedes all prior agreements,
     understandings, negotiations, and discussions, whether written or oral.
11.2 The Licensee may not assign or transfer this license to any third party
     without the Licensor's written consent.
11.3 The Licensor may modify this Agreement at any time. Continued use of the
     Software after modifications constitute acceptance of the modified terms.
11.4 The failure of the Licensor to enforce any provision of this Agreement does
     not constitute a waiver of that provision or any other provision.

END OF AGREEMENT

'@

function Show-EulaDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'K BNG M Hoster - Proprietary License Agreement'
    $dlg.Size = New-Object System.Drawing.Size(800, 700)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $Theme.bg
    $dlg.ForeColor = $Theme.text

    $title = New-Lbl 'K BNG M Hoster - Proprietary License Agreement (EULA)' ([System.Drawing.Color]::Yellow) 13 28 $true
    $title.Location = New-Object System.Drawing.Point(14, 10)
    $dlg.Controls.Add($title)

    $box = New-Object System.Windows.Forms.RichTextBox
    $box.Location = New-Object System.Drawing.Point(14, 44)
    $box.Size = New-Object System.Drawing.Size(756, 520)
    $box.ReadOnly = $true
    $box.BackColor = $Theme.log
    $box.ForeColor = [System.Drawing.Color]::FromArgb(212, 212, 212)
    $box.BorderStyle = 'FixedSingle'
    $box.Font = New-Object System.Drawing.Font('Consolas', 9.5)
    $box.Text = $LicenseFullText
    $dlg.Controls.Add($box)

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = 'I have read and agree to the K BNG M Hoster Proprietary License Agreement.'
    $chk.Location = New-Object System.Drawing.Point(14, 574)
    $chk.Size = New-Object System.Drawing.Size(756, 30)
    $chk.ForeColor = [System.Drawing.Color]::White
    $chk.BackColor = $Theme.bg
    $chk.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $chk.Checked = $false
    $dlg.Controls.Add($chk)

    $accept = New-Btn 'Accept & Continue' 'Accept the license and unlock K BNG M Hoster.' { $dlg.DialogResult = 'OK' }
    $accept.Size = New-Object System.Drawing.Size(150, 36)
    $accept.Location = New-Object System.Drawing.Point(14, 616)
    $accept.BackColor = [System.Drawing.Color]::FromArgb(35, 100, 60)
    $accept.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(63, 185, 80)
    $accept.Enabled = $false
    $dlg.Controls.Add($accept)

    $decline = New-Btn 'Decline / Exit' 'Decline the license and close K BNG M Hoster immediately.' { [System.Windows.Forms.Application]::Exit() }
    $decline.Size = New-Object System.Drawing.Size(150, 36)
    $decline.Location = New-Object System.Drawing.Point(170, 616)
    $decline.ForeColor = [System.Drawing.Color]::White
    $decline.BackColor = [System.Drawing.Color]::FromArgb(122, 26, 26)
    $decline.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(220, 60, 60)
    $dlg.Controls.Add($decline)

    $chk.Add_CheckedChanged({
        $accept.Enabled = $chk.Checked
    })
    $dlg.AcceptButton = $accept
    $dlg.CancelButton = $decline
    $null = $dlg.Handle
    Set-Round $dlg 10

    $r = $dlg.ShowDialog($script:Form)
    return ($r -eq 'OK')
}

# ---------------------------------------------------------------------------------------
# LICENSE GATE (mandatory EULA check against the official GitHub repository)
# ---------------------------------------------------------------------------------------
$script:LicenseLocked = $true
$script:LicenseSavedStates = @{}
$script:LicenseLocalVersion = ''
$script:LicenseRemoteVersion = $null
$script:LicenseCheckDone = $false
$script:LicensePs = $null
$script:LicenseHandle = $null

function Get-AllControls($root) {
    $out = @()
    foreach ($c in $root.Controls) {
        $out += $c
        $out += Get-AllControls $c
    }
    return $out
}

# Locks every button in the app (tabs, start/stop, dialogs) until the license is accepted.
function Set-LicenseLock([bool]$Lock) {
    $script:LicenseLocked = $Lock
    if ($Lock) {
        $script:LicenseSavedStates = @{}
        foreach ($c in @(Get-AllControls $script:Form)) {
            if ($c -is [System.Windows.Forms.Button]) {
                $script:LicenseSavedStates[$c] = $c.Enabled
                $c.Enabled = $false
            }
        }
    } else {
        foreach ($k in @($script:LicenseSavedStates.Keys)) {
            try { $k.Enabled = $script:LicenseSavedStates[$k] } catch { }
        }
        $script:LicenseSavedStates = @{}
        Update-BusyUi
    }
}

function Get-LicenseLocalPath { return Join-Path $env:APPDATA 'KBngMHoster\license_accepted.json' }

function Get-LocalLicenseVersion {
    $p = Get-LicenseLocalPath
    if (-not (Test-Path -LiteralPath $p)) { return '' }
    try {
        $d = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
        return [string]$d.Version
    } catch { return '' }
}

function Save-LocalLicenseVersion([string]$Version) {
    $p = Get-LicenseLocalPath
    $dir = Split-Path -Parent $p
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    @{ Product = 'K BNG M Hoster'; Version = $Version; Accepted = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $p -Encoding UTF8
    Write-Log "License accepted (version $Version) - saved to $p"
}

# Older builds recorded acceptance in Server\Logs\eula.accepted - migrate it once
# so offline users who already accepted are not locked out.
function Migrate-LegacyEulaMarker {
    if (Get-LocalLicenseVersion) { return }
    $marker = $script:ServerDir + 'Logs\eula.accepted'
    if (Test-Path -LiteralPath $marker) { Save-LocalLicenseVersion '0' }
}

# True when the user must accept (again): no local record, or the remote
# GitHub version is newer than the locally recorded one. Offline (empty
# remote) never forces acceptance.
function Test-LicenseNeedsAccept([string]$Local, [string]$Remote) {
    if (-not $Remote) { return $false }
    if (-not $Local) { return $true }
    $ln = 0; $rn = 0
    if ([int]::TryParse($Local, [ref]$ln) -and [int]::TryParse($Remote, [ref]$rn)) { return ($rn -gt $ln) }
    return ($Remote -ne $Local)
}

# Fetches license_version.txt from the official repository in a background
# runspace so the UI thread never blocks on the network.
function Start-LicenseRemoteCheck {
    $body = @'
try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/Kinan0713/K-BNG-M-Hoster/main/license_version.txt' -TimeoutSec 8 -ErrorAction Stop
    $v = ($r.Content -split "\r?\n" | Select-Object -First 1).Trim()
    if (-not $v) { return '' }
    return [string]$v
} catch { return '' }
'@
    $script:LicensePs = [powershell]::Create()
    $null = $script:LicensePs.AddScript($body)
    $script:LicenseHandle = $script:LicensePs.BeginInvoke()
    $script:LicenseCheckDone = $false
}

function Finish-LicenseGate {
    $script:LicenseCheckDone = $true
    $remote = [string]$script:LicenseRemoteVersion
    $local = [string]$script:LicenseLocalVersion
    if (-not $local -and -not $remote) {
        [System.Windows.Forms.MessageBox]::Show(
            'K BNG M Hoster could not reach the internet, and no accepted license was found on this computer.' + [Environment]::NewLine + [Environment]::NewLine +
            'An internet connection is required for first-time license verification. Connect to the internet and start the app again.',
            'K BNG M Hoster - License', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        [System.Windows.Forms.Application]::Exit()
        return
    }
    if (Test-LicenseNeedsAccept $local $remote) {
        Add-Log "[INFO] License version $remote required (accepted: $(if ($local) { $local } else { 'none' }))."
        if (Show-EulaDialog) {
            Save-LocalLicenseVersion $remote
            $script:LicenseLocalVersion = $remote
            Set-LicenseLock $false
            Add-Log '[INFO] License accepted - all controls unlocked.'
        } else {
            [System.Windows.Forms.Application]::Exit()
            return
        }
    } else {
        Set-LicenseLock $false
        Add-Log "[INFO] License check passed (version $local)."
    }
}

function Start-LicenseGate {
    Migrate-LegacyEulaMarker
    $script:LicenseLocalVersion = Get-LocalLicenseVersion
    Set-LicenseLock $true
    Start-LicenseRemoteCheck
}

function Show-KeySetupDialog($owner) {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'Server key - first-time setup'
    $dlg.Size = New-Object System.Drawing.Size(620, 430)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.BackColor = $Theme.bg
    $dlg.ForeColor = $Theme.text

    $intro = New-Lbl 'This key is how BeamMP knows you own your server. It is free and takes 1 minute. It is stored privately on your PC and never shown again.' $Theme.dim 9.5 40  $false 570
    $intro.Location = New-Object System.Drawing.Point(14, 12)
    $dlg.Controls.Add($intro)

    $link = New-Object System.Windows.Forms.LinkLabel
    $link.Text = 'Get your free key here: https://keymaster.beammp.com  (opens in your browser)'
    $link.LinkColor = $Theme.blue
    $link.ActiveLinkColor = [System.Drawing.Color]::White
    $link.Location = New-Object System.Drawing.Point(14, 60)
    $link.Size = New-Object System.Drawing.Size(570, 22)
    $link.Add_LinkClicked({ Start-Process 'https://keymaster.beammp.com' })
    $dlg.Controls.Add($link)

    $lbl = New-Lbl 'Paste your key here (right-click to paste):' $Theme.text 9.5 20
    $lbl.Location = New-Object System.Drawing.Point(14, 96)
    $dlg.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(14, 118)
    $txt.Size = New-Object System.Drawing.Size(570, 26)
    $txt.BackColor = $Theme.panel
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

    $lblResult = New-Lbl '' $Theme.yellow 9.5 40  $false 570
    $lblResult.Location = New-Object System.Drawing.Point(14, 194)
    $dlg.Controls.Add($lblResult)

    $save = New-Btn 'Save Key' 'Validate and save the key.' {
        $r = Save-AuthKey -Key $txt.Text
        if ($r.Ok) {
            if ($chk.Checked) {
                $port = New-SetupConfig
                $lblResult.Text = "$($r.Message)  Server settings applied (port $port)."
            } else {
                $lblResult.Text = $r.Message
            }
            $lblResult.ForeColor = $Theme.green
            $dlg.DialogResult = 'OK'
        } else {
            $lblResult.Text = $r.Message
            $lblResult.ForeColor = $Theme.red
        }
    }
    $save.Size = New-Object System.Drawing.Size(110, 36)
    $save.Location = New-Object System.Drawing.Point(14, 250)
    $save.BackColor = [System.Drawing.Color]::FromArgb(35, 100, 60)
    $save.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(63, 185, 80)
    $dlg.Controls.Add($save)

    $skip = New-Btn 'Skip for now' 'Continue without a key. You can set it up later in Settings.' { $dlg.DialogResult = 'Cancel' }
    $skip.Size = New-Object System.Drawing.Size(110, 36)
    $skip.Location = New-Object System.Drawing.Point(130, 250)
    $dlg.Controls.Add($skip)

    $note = New-Lbl 'A valid key contains only letters, numbers and dashes (8-64 characters).' $Theme.dim 8.5 20  $false 570
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
    $dlg.BackColor = $Theme.bg
    $dlg.ForeColor = $Theme.text

    $msg = New-Lbl "Your ISP uses CGNAT - port forwarding can never work on this connection.`nA FRP tunnel or VPN is how friends can reach you.`n`nSAFETY: a VPN puts friends on a virtual LAN with your PC (they can reach`nfile sharing / Remote Desktop etc.) - only invite people you TRUST.`nNever invite random players into your VPN network." $Theme.yellow 10 100  $false 620
    $msg.Location = New-Object System.Drawing.Point(18, 16)
    $dlg.Controls.Add($msg)

    $btnVpn = New-Btn 'Open Network tab' 'Go to the Network tab to set up the FRP tunnel or start/install a VPN.' { $dlg.DialogResult = 'Yes' }
    $btnVpn.Size = New-Object System.Drawing.Size(170, 38)
    $btnVpn.Location = New-Object System.Drawing.Point(18, 150)
    $dlg.Controls.Add($btnVpn)

    $btnAnyway = New-Btn 'Start anyway' 'Skip for now and start the server (friends will only reach you via the same WiFi, or after you set up FRP/VPN).' { $dlg.DialogResult = 'No' }
    $btnAnyway.Size = New-Object System.Drawing.Size(140, 38)
    $btnAnyway.Location = New-Object System.Drawing.Point(196, 150)
    $dlg.Controls.Add($btnAnyway)

    $btnCancel = New-Btn 'Cancel' 'Do not start the server.' { $dlg.DialogResult = 'Cancel' }
    $btnCancel.Size = New-Object System.Drawing.Size(100, 38)
    $btnCancel.Location = New-Object System.Drawing.Point(344, 150)
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
    if ($script:LicenseLocked) { Add-Log '[INFO] Accept the license agreement first (startup dialog).'; return }
    if ($script:State.Running) { Add-Log "[INFO] The server is already running."; return }
    if ($script:Starting) { Add-Log "[INFO] Already starting..."; return }
    if ($script:State.StopRequested) { $script:State.StopRequested = $false }

    if (-not (Test-AuthKeyConfigured)) {
        Add-Log "[INFO] No server key yet - setting it up first (you can skip)."
        $null = Show-KeySetupDialog $script:Form
        if (-not (Test-AuthKeyConfigured)) {
            Add-Log "[INFO] No server key - the server cannot start without it. Use Settings or Fix to set it up."
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
    $script:BtnStart.Text = 'Start Server'
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
            Show-NetworkPage
            Add-Log "[INFO] Server not started - set up FRP or a VPN first, then press Start again."
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
    Stop-FrpTunnel | Out-Null
    if (-not $script:State.Running) {
        Add-Log "[INFO] Server process stopped."
    }
}

function Copy-ConnectionLine {
    try { $conn = Get-ConnectionInfo -SkipRouterWan } catch { $conn = $script:State.Conn }
    if (-not $conn) { $conn = $script:State.Conn }
    $port = if ($conn) { $conn.Port } else { Get-ServerPort }
    $line = "127.0.0.1:$port"
    if ($conn -and $conn.LAN) { $line = "$($conn.LAN):$port" }
    $vpnLines = @()
    if ($conn) { $vpnLines = @($conn.Vpn | Where-Object { $_.Ip }) }
    if ($conn -and $vpnLines.Count -and -not $conn.LAN) { $line = "$($vpnLines[0].Ip):$port" }
    if ($conn -and $conn.Tailscale -and -not $conn.LAN -and -not $vpnLines.Count) { $line = "$($conn.Tailscale):$port" }
    if ($script:State.Running -and $script:State.Frp) { $line = $script:State.Frp }
    try {
        [System.Windows.Forms.Clipboard]::SetText($line)
        Add-Log "[OK] Copied to clipboard: $line  (send this to your friends)"
    } catch {
        Add-Log "[ERROR] Could not copy to clipboard: $_"
    }
}

# Copies a friendly full invite message (address + connect steps) - the easy way
# to invite friends to a PRIVATE server (or any server).
function Copy-Invite {
    try { $conn = Get-ConnectionInfo -SkipRouterWan } catch { $conn = $script:State.Conn }
    if (-not $conn) { $conn = $script:State.Conn }
    $port = if ($conn) { $conn.Port } else { Get-ServerPort }
    $addr = $null
    if ($conn) {
        $vpnLines = @($conn.Vpn | Where-Object { $_.Ip })
        if ($conn.LAN) { $addr = $conn.LAN }
        elseif ($vpnLines.Count) { $addr = $vpnLines[0].Ip }
        elseif ($conn.Tailscale) { $addr = $conn.Tailscale }
        elseif ($conn.Public) { $addr = $conn.Public }
    }
    if ($script:State.Running -and $script:State.Frp) { $addr = $script:State.Frp }
    if (-not $addr) { $addr = '127.0.0.1' }
    $priv = Get-ServerPrivate
    $text = if ($priv) {
        "Join my private BeamNG server!`n1) Open BeamNG -> More... -> BeamMP -> Direct Connect`n2) Address: $addr : $port`n3) Press Connect - done!"
    } else {
        "Join my BeamNG server! It is listed on BeamMP - search for it, or Direct Connect to: $addr : $port"
    }
    try {
        [System.Windows.Forms.Clipboard]::SetText($text)
        Add-Log "[OK] Invite copied - paste it to your friends."
    } catch {
        Add-Log "[ERROR] Could not copy the invite: $_"
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
if ($vpnOk.Count) { $lines += "VPN running: " + (($vpnOk | ForEach-Object { $_.Name + ' ' + $_.Ip }) -join ', ') } else { $lines += 'VPN running: none (start one from the Network tab if friends cannot join)' }
$lines += "LAN IP: " + $(if ($c.LAN) { $c.LAN } else { 'not detected' })
$lines += "Tailscale: " + $(if ($c.Tailscale) { $c.Tailscale } else { 'not running' })
$lines += "Public IP: " + $(if ($c.Public) { $c.Public } else { 'not detected' })
$lines += "CGNAT: " + $(if ($c.Cgnat) { 'YES - public hosting cannot work; use FRP or a VPN' } else { 'no' })
$lines += "Server listening: " + $(if (Test-Loopback $srvPort) { 'yes (127.0.0.1:' + $srvPort + ')' } else { 'NO - restart the server' })
$lines += "Firewall rules: " + $(if (Test-FirewallRule) { 'present' } else { 'MISSING - use Fix, Firewall row' })
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
        "Remove anything personal or temporary so the folder is safe to zip and share:`n  - .env (your secret server key)`n  - webhook.txt (Discord webhook)`n  - Logs\ and Server.log (IP caches, player names)`n  - CONNECTING.txt (contains your IP addresses)`n  - Backups\ , Quarantine\`n  - staticip.cfg (IP lock - restored to DHCP first)`n  - AuthKey and FRPToken inside ServerConfig.toml`n`nRun this BEFORE zipping the folder to give to someone else.",
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
            'fixfw' { Update-FixRows }
            'fixfwbng' { Update-FixRows }
            'fixport' { Update-FixRows }
            'fixter' { Update-FixRows }
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
            'tscan' { Update-TransferScanUi }
            'texport' { Update-TransferExportUi }
            'tinstall' { Update-TransferInstallUi }
            'trefresh' { Populate-ClientModList }
            'tdel' { Update-TransferDeleteUi }
            'settings' { $script:LblSettingsResult.Text = 'Settings saved.'; $script:LblSettingsResult.ForeColor = $Theme.green }
            'update' { $script:LblSettingsResult.Text = $(if ($script:State.UpdateMsg) { "Update available: $($script:State.UpdateMsg)" } else { 'Checked.' }); $script:LblSettingsResult.ForeColor = $Theme.green }
            'setmap' {
                if ($script:LblSettingsResult) { $script:LblSettingsResult.Text = 'Map applied.'; $script:LblSettingsResult.ForeColor = $Theme.green }
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
                if ($script:LblSettingsResult) { $script:LblSettingsResult.Text = 'Visibility saved.'; $script:LblSettingsResult.ForeColor = $Theme.green }
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
            'preset' {
                Refresh-SettingsFields
                Refresh-MapCombo
                Refresh-PresetCombo
                Refresh-ModListsAsync
                if ($script:LblSettingsResult) { $script:LblSettingsResult.Text = 'Preset applied - settings and mods now match it.'; $script:LblSettingsResult.ForeColor = $Theme.green }
                if ($script:State.Running) {
                    $r = [System.Windows.Forms.MessageBox]::Show(
                        'The preset changes the server on the next start. Restart the server now?',
                        'Preset loaded', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
                    if ($r -eq 'Yes') {
                        Add-Log "[INFO] Restarting the server to apply the preset..."
                        $script:RestartAfterStop = $true
                        Stop-ServerFlow
                    }
                } else {
                    Add-Log "[INFO] Preset applied - it will be used on the next server start."
                }
            }
            'live' { Refresh-Dashboard }
            'toolcheck' { if ($script:State.ToolUpdate) { Show-UpdateDialog } }
            'toolupdate' {
                if ($script:State.ToolUpdateReady) { Ask-ApplyUpdate }
                elseif ($script:State.ToolUpdateErr) {
                    [System.Windows.Forms.MessageBox]::Show("Update failed: $($script:State.ToolUpdateErr)", 'K BNG M Hoster - update failed', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
                    $script:State.ToolUpdateErr = ''
                }
            }
            'frptoggle' {
                if ($script:LblSettingsResult) { $script:LblSettingsResult.Text = 'FRP tunnel setting saved.'; $script:LblSettingsResult.ForeColor = $Theme.green }
                Refresh-Dashboard
            }
            'locktoggle' {
                if ($script:LblSettingsResult) { $script:LblSettingsResult.Text = 'IP lock setting saved.'; $script:LblSettingsResult.ForeColor = $Theme.green }
            }
        }
        if (-not $script:Starting -and $script:ActionQueue.Count) {
            $next = $script:ActionQueue.Dequeue()
            Start-CoreActionImpl -Script $next.Script -Tag $next.Tag
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
        $script:BtnStart.Text = 'Start Server'
        $script:LblPlayers.Text = ''
        Add-Log "[INFO] Session finished. You can press Start again."
        if ($script:State.FrpError) {
            [System.Windows.Forms.MessageBox]::Show($script:State.FrpError, 'FRP tunnel failed - server not started', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            $script:State.FrpError = ''
        }
        $script:State.Frp = ''
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
# KEYBOARD SHORTCUTS
# ---------------------------------------------------------------------------------------
$script:Fullscreen = $false
function Toggle-Fullscreen {
    if ($script:Fullscreen) {
        $script:Fullscreen = $false
        $script:Form.FormBorderStyle = $script:SavedBorder
        $script:Form.WindowState = 'Normal'
        if ($script:SavedWindowState -eq 'Maximized') {
            $script:Form.WindowState = 'Maximized'
        } else {
            $script:Form.Bounds = $script:SavedBounds
            $script:Form.StartPosition = 'CenterScreen'
        }
        $script:Form.Region = $null
        Add-Log "[INFO] Fullscreen off."
    } else {
        $script:Fullscreen = $true
        $script:SavedBorder = $script:Form.FormBorderStyle
        $script:SavedWindowState = $script:Form.WindowState
        $script:SavedBounds = $script:Form.Bounds
        $script:Form.Region = $null
        $script:Form.WindowState = 'Normal'
        $script:Form.FormBorderStyle = 'None'
        $script:Form.Bounds = [System.Windows.Forms.Screen]::FromControl($script:Form).Bounds
        Add-Log "[INFO] Fullscreen on (F11 to exit)."
    }
    try { $script:Form.PerformLayout() } catch { }
    if ($script:PageLayout) {
        $script:LayoutPending = $true
        [void]$script:Form.BeginInvoke([System.Windows.Forms.MethodInvoker]$script:DoRelayout)
    }
}

$script:Form.Add_KeyDown({
    param($s, $e)
    if ($script:LicenseLocked) { $e.SuppressKeyPress = $true; return }
    if ($e.KeyCode -eq 'F11') { Toggle-Fullscreen; $e.SuppressKeyPress = $true; return }
    if ($e.Alt -and $e.KeyCode -eq 'Return') { Toggle-Fullscreen; $e.SuppressKeyPress = $true; return }
    if ($script:Fullscreen -and $e.KeyCode -eq 'Escape') { Toggle-Fullscreen; $e.SuppressKeyPress = $true; return }
    if ($script:Form.ActiveControl -is [System.Windows.Forms.TextBox]) { return }
    if ($e.Control -and -not $e.Alt) {
        switch ($e.KeyCode) {
            'H' { Show-HomePage; $e.SuppressKeyPress = $true }
            'S' { Start-ServerFlow; $e.SuppressKeyPress = $true }
            'X' { Stop-ServerFlow; $e.SuppressKeyPress = $true }
            'F' { Show-FixPage; $e.SuppressKeyPress = $true }
            'V' { Show-NetworkPage; $e.SuppressKeyPress = $true }
            'M' { Show-ModsPage; $e.SuppressKeyPress = $true }
            'T' { Show-SettingsPage; $e.SuppressKeyPress = $true }
            'U' { Show-TransferPage; $e.SuppressKeyPress = $true }
            'E' { Show-ExtraPage; $e.SuppressKeyPress = $true }
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
        Stop-FrpTunnel | Out-Null
        $script:ClosingAfterStop = $true
        $e.Cancel = $true
        Add-Log "[INFO] Stopping the server, then closing..."
        $script:Form.Text = 'K BNG M Hoster - stopping the server...'
        return
    }
    if (Get-Process -Name 'BeamMP-Server' -ErrorAction SilentlyContinue) {
        Stop-Process -Name 'BeamMP-Server' -ErrorAction SilentlyContinue
    }
    Stop-FrpTunnel | Out-Null
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
    Set-Round $script:Form 12
    Start-ToolUpdateCheck
})

# ---------------------------------------------------------------------------------------
# STARTUP
# ---------------------------------------------------------------------------------------
$logDir = $script:ServerDir + 'Logs'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
Write-Log "===== Launcher started (GUI) ====="

# Polls the background license check and opens the EULA dialog when required.
$timerLicense = New-Object System.Windows.Forms.Timer
$timerLicense.Interval = 300
$timerLicense.Add_Tick({
    if ($script:LicenseCheckDone) { return }
    if ($script:LicenseHandle -and $script:LicenseHandle.IsCompleted) {
        try { $script:LicenseRemoteVersion = $script:LicensePs.EndInvoke($script:LicenseHandle) } catch { $script:LicenseRemoteVersion = '' }
        try { $script:LicensePs.Dispose() } catch { }
        $timerLicense.Stop()
        Finish-LicenseGate
    }
})

try {
    Start-LicenseGate
    $timerLicense.Start()

    [void][System.Windows.Forms.Application]::Run($script:Form)
} catch {
    Stop-FrpTunnel | Out-Null
    try {
        [System.Windows.Forms.MessageBox]::Show(
            "K BNG M Hoster hit an unexpected error:`n`n$($_.Exception.Message)",
            'K BNG M Hoster', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    } catch { }
}

if ($script:SessionPs) {
    try { $script:SessionPs.Dispose() } catch { }
}
Stop-FrpTunnel | Out-Null
exit 0