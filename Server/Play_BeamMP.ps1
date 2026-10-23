# ========================================================================================
# K BNG M Hoster v0.7.2.0 - Simplest Edition (GUI)
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
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName WindowsFormsIntegration
try {
    Add-Type -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing' @"
using System;
using System.Drawing;
using System.Windows.Forms;
using System.Runtime.InteropServices;
public class Win32R {
    [DllImport("user32.dll")] public static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);
}
public class Win32Chrome {
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool ShowScrollBar(IntPtr hWnd, int wBar, bool bShow);
    [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
    public static void ApplyModernWindow(IntPtr hWnd) {
        try {
            int dark = 1;
            DwmSetWindowAttribute(hWnd, 20, ref dark, 4);
            int round = 2;
            DwmSetWindowAttribute(hWnd, 33, ref round, 4);
            int borderCol = 0x00443530;
            DwmSetWindowAttribute(hWnd, 34, ref borderCol, 4);
        } catch { }
    }
}
public class WheelFilter : IMessageFilter {
    public static Control TargetViewport;
    public static Control ScopeControl;
    public static Action<int> ScrollCallback;

    public bool PreFilterMessage(ref Message m) {
        if (m.Msg == 0x020A) {
            if (TargetViewport != null && !TargetViewport.IsDisposed && TargetViewport.Visible && ScrollCallback != null) {
                Control check = (ScopeControl != null && !ScopeControl.IsDisposed && ScopeControl.Visible) ? ScopeControl : TargetViewport;
                
                Control target = Control.FromHandle(m.HWnd);
                if (target == null) {
                    try { target = Control.FromChildHandle(m.HWnd); } catch { }
                }

                if (target is ListBox || target is RichTextBox) {
                    if (target != TargetViewport && !TargetViewport.Contains(target)) {
                        return false;
                    }
                }

                bool isOver = false;
                if (target != null && (target == check || check.Contains(target) || TargetViewport.Contains(target))) {
                    isOver = true;
                } else {
                    try {
                        Point pt = Cursor.Position;
                        Rectangle rect = check.RectangleToScreen(check.ClientRectangle);
                        if (rect.Contains(pt)) isOver = true;
                    } catch { }
                }

                if (isOver) {
                    int delta = (short)((m.WParam.ToInt64() >> 16) & 0xFFFF);
                    ScrollCallback(delta);
                    return true;
                }
            }
        }
        return false;
    }
}
"@
} catch { }
try { [System.Windows.Forms.Application]::AddMessageFilter((New-Object WheelFilter)) } catch { }
[System.Windows.Forms.Application]::EnableVisualStyles()

$ErrorActionPreference = 'SilentlyContinue'

. (Join-Path $PSScriptRoot 'HosterCore.ps1')
# -SkipFrpInit: the one-time FRP zip extraction (and the "frpc.exe -v" probe)
# must NOT run on this thread before the window exists. It is deferred to a
# background runspace started in Form.Add_Shown, so the first paint is instant.
Initialize-HosterPaths -SkipFrpInit

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
$script:AppVersion = '0.7.2.3'
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
$script:isPrivate = $false

# ---------------------------------------------------------------------------------------
# COLORS / HELPERS (BeamNG Carbon & Racing Orange Design System)
# ---------------------------------------------------------------------------------------
$Theme = @{
    # 5-Tier Neutral Carbon-Graphite Surface Hierarchy (Zero Blue Cast)
    log              = [System.Drawing.Color]::FromArgb(9, 9, 11)      # Tier 0: Deepest OLED carbon void (#09090B)
    bg               = [System.Drawing.Color]::FromArgb(16, 16, 19)    # Tier 1: Matte carbon chassis canvas (#101013)
    panel            = [System.Drawing.Color]::FromArgb(23, 23, 27)    # Tier 2: Structural sidebar & endpoint rows (#17171B)
    card             = [System.Drawing.Color]::FromArgb(30, 30, 36)    # Tier 3: Elevated gunmetal cards (#1E1E24)
    surface          = [System.Drawing.Color]::FromArgb(40, 40, 48)    # Tier 4: Interactive controls (#282830)

    # Specular Gunmetal Borders
    border           = [System.Drawing.Color]::FromArgb(50, 50, 60)    # Crisp gunmetal border (#32323C)
    borderHi         = [System.Drawing.Color]::FromArgb(74, 74, 88)    # Top-edge specular catch-light (#4A4A58)

    # 4-Tier WCAG-Compliant Neutral Zinc Typographic Hierarchy
    text             = [System.Drawing.Color]::FromArgb(244, 244, 246) # Primary Zinc-100 (#F4F4F6)
    textSec          = [System.Drawing.Color]::FromArgb(212, 212, 218) # Secondary Zinc-300 (#D4D4DA)
    dim              = [System.Drawing.Color]::FromArgb(161, 161, 170) # Muted Zinc-400 (#A1A1AA)
    muted            = [System.Drawing.Color]::FromArgb(113, 113, 122) # Subtle Zinc-500 (#71717A)

    # BeamNG Signature Semantic Accents
    blue             = [System.Drawing.Color]::FromArgb(255, 115, 29)  # BeamNG Racing Tangerine-Orange (#FF731D)
    accent           = [System.Drawing.Color]::FromArgb(255, 115, 29)  # Primary focal accent (#FF731D)
    accentDim        = [System.Drawing.Color]::FromArgb(194, 65, 12)   # Burnt racing orange border (#C2410C)
    green            = [System.Drawing.Color]::FromArgb(52, 211, 153)  # Telemetry Emerald (#34D399)
    red              = [System.Drawing.Color]::FromArgb(251, 113, 133) # Brake-Light Crimson (#FB7185)
    yellow           = [System.Drawing.Color]::FromArgb(251, 191, 36)  # Warm Caution Amber (#FBBF24)

    # Interactive Button Tokens - Modernized Tactile Palette (#1c1c24 soft-elevated)
    btn              = [System.Drawing.Color]::FromArgb(28, 28, 36)    # Soft-elevated dark zinc (#1C1C24)
    btnHov           = [System.Drawing.Color]::FromArgb(38, 38, 48)    # Hover luminance elevation (#262630)
    btnBorder        = [System.Drawing.Color]::FromArgb(48, 48, 58)    # Translucent subtle border (rgba(255,255,255,0.08))
    btnBorderHov     = [System.Drawing.Color]::FromArgb(72, 72, 86)    # Hover specular edge (rgba(255,255,255,0.18))
    btnDown          = [System.Drawing.Color]::FromArgb(22, 22, 28)    # Pressed tactile inset (#16161C)
    btnAct           = [System.Drawing.Color]::FromArgb(62, 31, 16)    # Active racing-orange bronze surface (#3E1F10)
    btnSuccess       = [System.Drawing.Color]::FromArgb(16, 118, 84)   # Emerald action fill (#107654)
    btnSuccessHov    = [System.Drawing.Color]::FromArgb(21, 148, 105)  # Emerald action hover (#159469)
    btnDanger        = [System.Drawing.Color]::FromArgb(136, 24, 48)   # Crimson action fill (#881830)
    btnDangerHov     = [System.Drawing.Color]::FromArgb(172, 32, 62)   # Crimson action hover (#AC203E)
    btnDangerBorder  = [System.Drawing.Color]::FromArgb(244, 63, 94)   # Crimson border (#F43F5E)
}

$script:MonoFontName = try {
    $ff = New-Object System.Drawing.FontFamily('Cascadia Mono')
    $ff.Dispose()
    'Cascadia Mono'
} catch { 'Consolas' }

# ---------------- GDI+ Resource Caches & Double-Buffering (Zero-Allocation Rendering) ----------------
$script:FontCache  = @{}
$script:PenCache   = @{}
$script:BrushCache = @{}
$script:DblBufProp = [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')

function Enable-DoubleBuffer($Ctrl) {
    if ($Ctrl -and $script:DblBufProp) {
        try { $script:DblBufProp.SetValue($Ctrl, $true, $null) } catch { }
    }
}

function Get-CachedFont([string]$Family, [float]$Size, [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular) {
    $key = "$Family|$Size|$([int]$Style)"
    $f = $script:FontCache[$key]
    if (-not $f) {
        $f = New-Object System.Drawing.Font($Family, $Size, $Style)
        $script:FontCache[$key] = $f
    }
    return $f
}

function Get-CachedPen([System.Drawing.Color]$Color, [float]$Width = 1.0) {
    $key = "$($Color.ToArgb())|$Width"
    $p = $script:PenCache[$key]
    if (-not $p) {
        $p = New-Object System.Drawing.Pen($Color, $Width)
        $script:PenCache[$key] = $p
    }
    return $p
}

function Get-CachedBrush([System.Drawing.Color]$Color) {
    $key = $Color.ToArgb()
    $b = $script:BrushCache[$key]
    if (-not $b) {
        $b = New-Object System.Drawing.SolidBrush($Color)
        $script:BrushCache[$key] = $b
    }
    return $b
}

function Set-CtrlText($Ctrl, [string]$Text, $ForeColor = $null) {
    if (-not $Ctrl) { return $false }
    $changed = $false
    if ($Ctrl.Text -cne $Text) {
        $Ctrl.Text = $Text
        $changed = $true
    }
    if ($null -ne $ForeColor -and $Ctrl.ForeColor.ToArgb() -ne $ForeColor.ToArgb()) {
        $Ctrl.ForeColor = $ForeColor
        $changed = $true
    }
    if ($changed) {
        $Ctrl.Invalidate()
        if ($Ctrl.Parent) { $Ctrl.Parent.Invalidate() }
    }
    return $changed
}

function Get-RoundedRectPath([int]$X, [int]$Y, [int]$W, [int]$H, [int]$Radius) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [math]::Max(2, [math]::Min(($Radius * 2), [math]::Min($W, $H)))
    $p.AddArc($X, $Y, $d, $d, 180, 90)
    $p.AddArc(($X + $W - $d), $Y, $d, $d, 270, 90)
    $p.AddArc(($X + $W - $d), ($Y + $H - $d), $d, $d, 0, 90)
    $p.AddArc($X, ($Y + $H - $d), $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

$script:NavKeyFont = Get-CachedFont $script:MonoFontName 7
$script:DefaultBtnFont = Get-CachedFont 'Segoe UI Semibold' 9.25

function New-Btn([string]$Text, [string]$Tip, [scriptblock]$OnClick) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.UseMnemonic = $false
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.BorderColor = $Theme.btnBorder
    $b.FlatAppearance.MouseOverBackColor = $Theme.btnHov
    $b.FlatAppearance.MouseDownBackColor = $Theme.btnDown
    $b.BackColor = $Theme.btn
    $b.ForeColor = $Theme.text
    $b.Font = $script:DefaultBtnFont
    $b.AutoSize = $false
    $b.Width = [int][math]::Max(96, ([System.Windows.Forms.TextRenderer]::MeasureText($Text, $b.Font).Width + 24))
    $b.Height = 34
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Add_SizeChanged({
        if ($this.AccessibleRole -ne [System.Windows.Forms.AccessibleRole]::MenuItem -and $this.AccessibleRole -ne [System.Windows.Forms.AccessibleRole]::PushButton -and $this.Text) {
            $needW = [System.Windows.Forms.TextRenderer]::MeasureText($this.Text, $this.Font).Width + 22
            if ($needW -gt 420) { $needW = 420 }
            if ($this.Width -gt 48 -and $this.Width -lt $needW) {
                $this.Width = $needW
            }
        }
    })
    $b.Add_TextChanged({
        if ($this.AccessibleRole -ne [System.Windows.Forms.AccessibleRole]::MenuItem -and $this.AccessibleRole -ne [System.Windows.Forms.AccessibleRole]::PushButton -and $this.Text) {
            $needW = [System.Windows.Forms.TextRenderer]::MeasureText($this.Text, $this.Font).Width + 22
            if ($needW -gt 420) { $needW = 420 }
            if ($this.Width -gt 48 -and $this.Width -lt $needW) {
                $this.Width = $needW
            }
        }
    })
    $b.Add_MouseEnter({ if ($this.AccessibleDescription -ne 'hover') { $this.AccessibleDescription = 'hover'; $this.Invalidate() } })
    $b.Add_MouseLeave({ if ($this.AccessibleDescription -ne '') { $this.AccessibleDescription = ''; $this.Invalidate() } })
    $b.Add_MouseDown({ if ($this.AccessibleDescription -ne 'down') { $this.AccessibleDescription = 'down'; $this.Invalidate() } })
    $b.Add_MouseUp({ if ($this.AccessibleDescription -ne 'hover') { $this.AccessibleDescription = 'hover'; $this.Invalidate() } })
    $b.Add_EnabledChanged({ $this.Invalidate() })
    $b.Add_Paint({
        param($s, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
            $parentBg = $Theme.bg
            $anc = $s.Parent
            while ($anc) {
                if ($anc.BackColor.A -eq 255) { $parentBg = $anc.BackColor; break }
                $anc = $anc.Parent
            }
            $g.Clear($parentBg)

            $w = $s.Width - 3
            $h = $s.Height - 3
            if ($w -le 4 -or $h -le 4) { return }

            $isNav = ($s.AccessibleRole -eq [System.Windows.Forms.AccessibleRole]::MenuItem)
            $isActiveNav = ($s.AccessibleName -eq 'nav-active')
            $state = $s.AccessibleDescription
            $isStartBtn = ($script:BtnStart -and $s -eq $script:BtnStart)
            $isStopBtn = ($script:BtnStop -and $s -eq $script:BtnStop)

            if ($isNav) {
                # Sidebar Navigation: Defined interactive surfaces with subtle border, 6px corner radius, and glowing active selection
                if ($isActiveNav) {
                    # Active State Harmony: Warm accent fill with luminous accent border
                    $fillCol = [System.Drawing.Color]::FromArgb(34, 255, 115, 29)
                    $borderCol = [System.Drawing.Color]::FromArgb(96, 255, 115, 29)
                    $textCol = [System.Drawing.Color]::White
                } elseif ($state -eq 'hover') {
                    # Hover State: Subtle surface brightening with crisp translucent highlight border
                    $fillCol = [System.Drawing.Color]::FromArgb(24, 24, 32)
                    $borderCol = [System.Drawing.Color]::FromArgb(44, 255, 255, 255)
                    $textCol = [System.Drawing.Color]::White
                } elseif ($state -eq 'down') {
                    # Down State: Tactile depression
                    $fillCol = [System.Drawing.Color]::FromArgb(19, 19, 25)
                    $borderCol = [System.Drawing.Color]::FromArgb(34, 255, 255, 255)
                    $textCol = [System.Drawing.Color]::White
                } else {
                    # Inactive Idle State: Subtle #111115 surface lift with ultra-subtle border (rgba(255, 255, 255, 0.08))
                    $fillCol = [System.Drawing.Color]::FromArgb(17, 17, 21)
                    $borderCol = [System.Drawing.Color]::FromArgb(20, 255, 255, 255)
                    $textCol = $Theme.textSec
                }

                $navW = $s.Width - 3
                $navH = $s.Height - 3
                if ($navW -gt 4 -and $navH -gt 4) {
                    $navPath = Get-RoundedRectPath 1 1 $navW $navH 6
                    try {
                        $g.FillPath((Get-CachedBrush $fillCol), $navPath)
                        if ($borderCol.A -gt 0) {
                            $g.DrawPath((Get-CachedPen $borderCol 1), $navPath)
                        }
                    } finally {
                        $navPath.Dispose()
                    }
                }

                $flags = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::SingleLine -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix -bor [System.Windows.Forms.TextFormatFlags]::Left
                $rightReserve = if ($s.Name) { 48 } else { 16 }
                $rect = New-Object System.Drawing.Rectangle(14, 0, ($s.Width - $rightReserve), $s.Height)
                [System.Windows.Forms.TextRenderer]::DrawText($g, $s.Text, $s.Font, $rect, $textCol, $flags)

                # Keyboard shortcut text floating cleanly inside with zero border and zero background box
                if ($s.Name) {
                    $kw = 36
                    $kh = $s.Height
                    $kx = $s.Width - $kw - 14
                    $rKey = New-Object System.Drawing.Rectangle($kx, 0, $kw, $kh)
                    $kFg = if ($isActiveNav) { [System.Drawing.Color]::FromArgb(255, 180, 125) } elseif ($state -eq 'hover') { [System.Drawing.Color]::FromArgb(185, 185, 198) } else { [System.Drawing.Color]::FromArgb(100, 100, 115) }
                    $kFlags = [System.Windows.Forms.TextFormatFlags]::Right -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::SingleLine
                    [System.Windows.Forms.TextRenderer]::DrawText($g, $s.Name, $script:NavKeyFont, $rKey, $kFg, $kFlags)
                }
            } else {
                # Action Buttons & Primary Controls: Layered Material Elevation over #09090b canvas
                if (-not $s.Enabled) {
                    if ($isStopBtn) {
                        $fillCol = [System.Drawing.Color]::FromArgb(16, 16, 21)
                        $borderCol = [System.Drawing.Color]::FromArgb(28, 28, 36)
                        $textCol = [System.Drawing.Color]::FromArgb(90, 90, 104)
                    } elseif ($isStartBtn) {
                        $fillCol = [System.Drawing.Color]::FromArgb(20, 20, 26)
                        $borderCol = [System.Drawing.Color]::FromArgb(34, 34, 42)
                        $textCol = $Theme.muted
                    } else {
                        $fillCol = [System.Drawing.Color]::FromArgb(18, 18, 23)
                        $borderCol = [System.Drawing.Color]::FromArgb(28, 28, 36)
                        $textCol = $Theme.muted
                    }
                } else {
                    if ($isStartBtn) {
                        $fillCol = if ($state -eq 'down') { [System.Drawing.Color]::FromArgb(12, 100, 70) } elseif ($state -eq 'hover') { [System.Drawing.Color]::FromArgb(20, 150, 105) } else { [System.Drawing.Color]::FromArgb(16, 128, 90) }
                        $borderCol = if ($state -eq 'hover') { [System.Drawing.Color]::FromArgb(52, 211, 153) } else { [System.Drawing.Color]::FromArgb(40, 180, 125) }
                        $textCol = [System.Drawing.Color]::White
                    } elseif ($isStopBtn) {
                        $fillCol = if ($state -eq 'down') { [System.Drawing.Color]::FromArgb(115, 18, 40) } elseif ($state -eq 'hover') { [System.Drawing.Color]::FromArgb(180, 32, 65) } else { [System.Drawing.Color]::FromArgb(148, 24, 52) }
                        $borderCol = if ($state -eq 'hover') { [System.Drawing.Color]::FromArgb(251, 113, 133) } else { [System.Drawing.Color]::FromArgb(244, 63, 94) }
                        $textCol = [System.Drawing.Color]::White
                    } else {
                        # Elevated #1c1c24 material button
                        if ($state -eq 'down') {
                            $fillCol = [System.Drawing.Color]::FromArgb(20, 20, 26)
                            $borderCol = [System.Drawing.Color]::FromArgb(35, 255, 255, 255)
                            $textCol = [System.Drawing.Color]::White
                        } elseif ($state -eq 'hover') {
                            $fillCol = [System.Drawing.Color]::FromArgb(36, 36, 48)
                            $borderCol = [System.Drawing.Color]::FromArgb(48, 255, 255, 255)
                            $textCol = [System.Drawing.Color]::White
                        } else {
                            $fillCol = [System.Drawing.Color]::FromArgb(28, 28, 36)
                            $borderCol = [System.Drawing.Color]::FromArgb(26, 255, 255, 255)
                            $textCol = [System.Drawing.Color]::FromArgb(235, 235, 245)
                        }
                    }
                }

                $btnW = $s.Width - 3
                $btnH = $s.Height - 4
                if ($btnW -gt 4 -and $btnH -gt 4) {
                    if ($state -eq 'down' -or -not $s.Enabled) {
                        # Depressed / disabled: shadow collapses
                        $bodyY = if ($state -eq 'down') { 2 } else { 1 }
                        $bodyPath = Get-RoundedRectPath 1 $bodyY $btnW $btnH 6
                        try {
                            $g.FillPath((Get-CachedBrush $fillCol), $bodyPath)
                            if ($borderCol.A -gt 0) { $g.DrawPath((Get-CachedPen $borderCol 1), $bodyPath) }
                        } finally { $bodyPath.Dispose() }
                    } else {
                        # Layered Material Elevation: tight blur, low-opacity drop shadows lifting button off canvas
                        $ambAlpha = if ($state -eq 'hover') { 44 } else { 32 }
                        $conAlpha = if ($state -eq 'hover') { 82 } else { 58 }

                        $sh1 = Get-RoundedRectPath 1 3 $btnW $btnH 7
                        try { $g.FillPath((Get-CachedBrush ([System.Drawing.Color]::FromArgb($ambAlpha, 0, 0, 0))), $sh1) } finally { $sh1.Dispose() }

                        $sh2 = Get-RoundedRectPath 1 2 $btnW $btnH 6
                        try { $g.FillPath((Get-CachedBrush ([System.Drawing.Color]::FromArgb($conAlpha, 0, 0, 0))), $sh2) } finally { $sh2.Dispose() }

                        $bodyPath = Get-RoundedRectPath 1 1 $btnW $btnH 6
                        try {
                            $g.FillPath((Get-CachedBrush $fillCol), $bodyPath)
                            if ($borderCol.A -gt 0) { $g.DrawPath((Get-CachedPen $borderCol 1), $bodyPath) }
                        } finally { $bodyPath.Dispose() }

                        # Top specular catch-light line for physical surface sheen
                        $catchAlpha = if ($isStartBtn -or $isStopBtn) { 60 } elseif ($state -eq 'hover') { 45 } else { 30 }
                        $g.DrawLine((Get-CachedPen ([System.Drawing.Color]::FromArgb($catchAlpha, 255, 255, 255)) 1), 6, 2, ($s.Width - 7), 2)
                    }
                }

                $rectY = if ($state -eq 'down') { 1 } else { 0 }
                $flags = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::SingleLine -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix -bor [System.Windows.Forms.TextFormatFlags]::HorizontalCenter
                $rect = New-Object System.Drawing.Rectangle(4, $rectY, ($s.Width - 8), ($s.Height - 3))
                [System.Windows.Forms.TextRenderer]::DrawText($g, $s.Text, $s.Font, $rect, $textCol, $flags)
            }
        } catch { }
    })
    if ($Tip) { $script:Tip.SetToolTip($b, $Tip) }
    if ($OnClick) { $b.Add_Click($OnClick) }
    return $b
}

function Set-ActiveNav($ActiveBtn) {
    $navBtns = @($script:BtnHome, $script:BtnSettings, $script:BtnMods, $script:BtnFix, $script:BtnNetwork, $script:BtnTransfer, $script:BtnMore)
    foreach ($nb in $navBtns) {
        if (-not $nb) { continue }
        $wantName = if ($nb -eq $ActiveBtn) { 'nav-active' } else { '' }
        if ($nb.AccessibleName -ne $wantName) {
            $nb.AccessibleName = $wantName
            if ($nb -eq $ActiveBtn) {
                $nb.ForeColor = [System.Drawing.Color]::White
            } else {
                $nb.ForeColor = $Theme.textSec
            }
            $nb.Invalidate()
        }
    }
}

function Attach-ModernScrollBar($Parent, $Viewport, $ContentPanel, $GetContentHeight) {
    if ($Viewport) { $Viewport.AutoScroll = $false }

    $sb = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $sb
    $sb.Width = 12
    $sb.Dock = [System.Windows.Forms.DockStyle]::Right
    $sb.BackColor = $Theme.bg
    $sb.Cursor = [System.Windows.Forms.Cursors]::Hand

    $baseOffsetY = if ($ContentPanel) { $ContentPanel.Location.Y } else { 0 }
    $st = @{
        ScrollY = 0
        DeltaAccum = 0.0
        IsDragging = $false
        DragStartY = 0
        DragStartScrollY = 0
        IsHovered = $false
        BaseOffsetY = $baseOffsetY
        Viewport = $Viewport
        ContentPanel = $ContentPanel
        GetContentHeight = $GetContentHeight
        ThumbRect = [System.Drawing.Rectangle]::Empty
        SetScroll = $null
        Sync = $null
    }
    $sb.Tag = $st

    $sb.Add_MouseEnter({
        $this.Tag.IsHovered = $true
        $this.Invalidate()
    })
    $sb.Add_MouseLeave({
        $this.Tag.IsHovered = $false
        $this.Invalidate()
    })

    $setScroll = {
        param([int]$newY)
        try {
            if (-not $Viewport -or $Viewport.IsDisposed -or -not $ContentPanel -or $ContentPanel.IsDisposed) { return }
            $fnH = $st.GetContentHeight
            $totH = if ($fnH -is [scriptblock]) { & $fnH } else { 0 }
            if ($totH -le 0 -and $ContentPanel -and -not $ContentPanel.IsDisposed) { $totH = $ContentPanel.Height }
            $vH = $Viewport.ClientSize.Height
            $maxS = [math]::Max(0, ($totH - $vH))
            $clamped = [math]::Max(0, [math]::Min($maxS, $newY))
            $st.ScrollY = $clamped
            $ContentPanel.Location = New-Object System.Drawing.Point($ContentPanel.Location.X, ($st.BaseOffsetY - $clamped))
            $sb.Invalidate()
        } catch { }
    }.GetNewClosure()
    $st.SetScroll = $setScroll

    $onDelta = {
        param([int]$delta)
        $lines = 3
        try {
            $lines = [System.Windows.Forms.SystemInformation]::MouseWheelScrollLines
            if ($lines -le 0) { $lines = 3 }
        } catch { $lines = 3 }
        $pixelsPerDetent = [math]::Max(24, [math]::Min(120, ($lines * 16)))
        $st.DeltaAccum += (($delta / 120.0) * $pixelsPerDetent)
        $step = [int]$st.DeltaAccum
        if ($step -ne 0) {
            $st.DeltaAccum -= $step
            & $setScroll ($st.ScrollY - $step)
        }
    }.GetNewClosure()

    $calcThumb = {
        param($tag, [int]$sbHeight)
        $fnH = $tag.GetContentHeight
        $totH = if ($fnH -is [scriptblock]) { & $fnH } else { 0 }
        if ($totH -le 0 -and $tag.ContentPanel -and -not $tag.ContentPanel.IsDisposed) { $totH = $tag.ContentPanel.Height }
        $vH = if ($tag.Viewport) { $tag.Viewport.ClientSize.Height } else { 0 }
        if ($totH -le $vH -or $vH -le 0) { return [System.Drawing.Rectangle]::Empty }
        $thumbH = [int][math]::Max(32, [math]::Min($sbHeight, ($vH / $totH * $sbHeight)))
        $availH = $sbHeight - $thumbH
        $sRange = $totH - $vH
        $thumbY = if ($sRange -gt 0) { [int]($tag.ScrollY / $sRange * $availH) } else { 0 }
        $thumbY = [int][math]::Max(0, [math]::Min($availH, $thumbY))
        return (New-Object System.Drawing.Rectangle(2, $thumbY, 8, $thumbH))
    }.GetNewClosure()
    $st.CalcThumb = $calcThumb

    $sb.Add_Paint({
        param($s, $e)
        try {
            $tag = $s.Tag
            $tr = & $tag.CalcThumb $tag $s.Height
            if ($tr.IsEmpty -or $tr.Height -le 0) { return }

            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $col = if ($tag.IsDragging) {
                [System.Drawing.Color]::FromArgb(255, 145, 60)
            } elseif ($tag.IsHovered) {
                $Theme.blue
            } else {
                [System.Drawing.Color]::FromArgb(90, 90, 108)
            }
            $brush = Get-CachedBrush $col
            $path = Get-RoundedRectPath $tr.X $tr.Y $tr.Width $tr.Height 3
            try { $g.FillPath($brush, $path) } finally { $path.Dispose() }
        } catch { }
    }.GetNewClosure())

    $sb.Add_MouseDown({
        param($s, $e)
        try {
            $tag = $s.Tag
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                $tr = & $tag.CalcThumb $tag $s.Height
                if ($tr.Height -gt 0 -and $e.Y -ge ($tr.Top - 6) -and $e.Y -le ($tr.Bottom + 6)) {
                    $tag.IsDragging = $true
                    $tag.DragStartY = $e.Y
                    $tag.DragStartScrollY = $tag.ScrollY
                    $s.Capture = $true
                    $s.Invalidate()
                } else {
                    $vH = if ($tag.Viewport) { $tag.Viewport.ClientSize.Height } else { 0 }
                    $targetY = if ($tr.Height -gt 0 -and $e.Y -lt $tr.Top) { [math]::Max(0, ($tag.ScrollY - $vH)) } else { ($tag.ScrollY + $vH) }
                    if ($tag.SetScroll -is [scriptblock]) {
                        & $tag.SetScroll $targetY
                    }
                }
            }
        } catch { }
    }.GetNewClosure())

    $sb.Add_MouseMove({
        param($s, $e)
        try {
            $tag = $s.Tag
            if ($tag.IsDragging) {
                if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) {
                    $tag.IsDragging = $false
                    $s.Capture = $false
                    $s.Invalidate()
                    return
                }
                $fnH = $tag.GetContentHeight
                $totH = if ($fnH -is [scriptblock]) { & $fnH } else { 0 }
                if ($totH -le 0 -and $tag.ContentPanel -and -not $tag.ContentPanel.IsDisposed) { $totH = $tag.ContentPanel.Height }
                $vH = if ($tag.Viewport) { $tag.Viewport.ClientSize.Height } else { 0 }
                $tH = $s.Height
                $thumbH = [int][math]::Max(32, [math]::Min($tH, ($vH / $totH * $tH)))
                $availH = $tH - $thumbH
                $sRange = $totH - $vH
                if ($availH -gt 0 -and $sRange -gt 0) {
                    $dY = $e.Y - $tag.DragStartY
                    $dScroll = ($dY / $availH) * $sRange
                    $newScroll = [int]($tag.DragStartScrollY + $dScroll)
                    if ($tag.SetScroll -is [scriptblock]) {
                        & $tag.SetScroll $newScroll
                    }
                }
            }
        } catch { }
    }.GetNewClosure())

    $sb.Add_MouseUp({
        param($s, $e)
        $s.Tag.IsDragging = $false
        $s.Capture = $false
        $s.Invalidate()
    }.GetNewClosure())

    $sb.Add_MouseWheel({
        param($s, $e)
        & $onDelta $e.Delta
    })

    $sync = {
        try {
            $fnH = $GetContentHeight
            $totH = if ($fnH -is [scriptblock]) { & $fnH } else { 0 }
            if ($totH -le 0 -and $ContentPanel -and -not $ContentPanel.IsDisposed) { $totH = $ContentPanel.Height }
            $vH = $Viewport.ClientSize.Height
            $needScroll = ($totH -gt $vH)
            if ($sb.Visible -ne $needScroll) { $sb.Visible = $needScroll }
            if ($sb.Visible) {
                $maxS = [math]::Max(0, ($totH - $vH))
                if ($st.ScrollY -gt $maxS) {
                    & $setScroll $maxS
                }
                $sb.Invalidate()
            } else {
                if ($st.ScrollY -ne 0) {
                    & $setScroll 0
                }
            }
            [WheelFilter]::TargetViewport = $Viewport
            [WheelFilter]::ScopeControl = if ($Parent -and $Parent.Parent) { $Parent.Parent } else { $Parent }
            [WheelFilter]::ScrollCallback = $onDelta
        } catch { }
    }.GetNewClosure()

    $st.Sync = $sync

    $Viewport.Add_Resize({
        try {
            if ($sb -and $sb.Tag -and $sb.Tag.Sync) { & $sb.Tag.Sync }
        } catch { }
    }.GetNewClosure())

    # Touch and mouse drag panning for touchscreens & trackpads
    $panState = @{
        IsPanning = $false
        StartY = 0
        StartScrollY = 0
    }
    $onPanDown = {
        param($s, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $panState.IsPanning = $true
            $panState.StartY = [System.Windows.Forms.Cursor]::Position.Y
            $panState.StartScrollY = $st.ScrollY
        }
    }.GetNewClosure()
    $onPanMove = {
        param($s, $e)
        if ($panState.IsPanning -and ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left)) {
            $curY = [System.Windows.Forms.Cursor]::Position.Y
            $diff = $curY - $panState.StartY
            if ([math]::Abs($diff) -ge 4) {
                & $setScroll ($panState.StartScrollY - $diff)
            }
        }
    }.GetNewClosure()
    $onPanUp = {
        param($s, $e)
        $panState.IsPanning = $false
    }.GetNewClosure()

    if ($Viewport) {
        $Viewport.Add_MouseDown($onPanDown)
        $Viewport.Add_MouseMove($onPanMove)
        $Viewport.Add_MouseUp($onPanUp)
    }
    if ($ContentPanel) {
        $ContentPanel.Add_MouseDown($onPanDown)
        $ContentPanel.Add_MouseMove($onPanMove)
        $ContentPanel.Add_MouseUp($onPanUp)
    }

    $Parent.Controls.Add($sb)
    $Viewport.BringToFront()

    return @{ Bar = $sb; Sync = $sync; SetScroll = $setScroll; GetScrollY = { $st.ScrollY }; OnDelta = $onDelta }
}

function New-Lbl([string]$Text, [System.Drawing.Color]$Color, [float]$Size = 9.5, [int]$Height = 20, [bool]$Bold = $false, [int]$Width = 0) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.UseMnemonic = $false
    $l.ForeColor = $Color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $l.Font = Get-CachedFont 'Segoe UI' $Size $style
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
    $b.Font = Get-CachedFont 'Segoe UI Semibold' 8.75
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
        $p.AddArc(($Ctrl.Width - $d), 0, $d, $d, 270, 90)
        $p.AddArc(($Ctrl.Width - $d), ($Ctrl.Height - $d), $d, $d, 0, 90)
        $p.AddArc(0, ($Ctrl.Height - $d), $d, $d, 90, 90)
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

function Add-CardBorderPaint($Panel, [System.Drawing.Color]$AccentColor) {
    $Panel.Tag = @{ Accent = $AccentColor; Inner = $Panel.Tag }
    $Panel.Add_Paint({
        param($s, $e)
        try {
            $e.Graphics.DrawRectangle((Get-CachedPen $Theme.border 1), 0, 0, ($s.Width - 1), ($s.Height - 1))
            $e.Graphics.DrawLine((Get-CachedPen $Theme.borderHi 1), 1, 0, ($s.Width - 2), 0)
            $acc = if ($s.Tag -is [hashtable] -and $s.Tag.ContainsKey('Accent')) { $s.Tag.Accent } else { $Theme.blue }
            $e.Graphics.FillRectangle((Get-CachedBrush $acc), 0, 12, 3, 20)
        } catch { }
    })
}

function Add-LogBatch([string[]]$Lines) {
    if (-not $Lines -or -not $Lines.Count -or -not $script:LogBox) { return }
    $script:LogBox.SuspendLayout()
    try {
        $ts = (Get-Date -Format 'HH:mm:ss') + '  '
        foreach ($Line in $Lines) {
            if (-not $Line) { continue }
            $cleanLine = $Line
            if ($script:StreamerMode -and (Get-Command 'Protect-StreamerText' -ErrorAction SilentlyContinue)) {
                $pubIp = if ($script:State -and $script:State.Conn) { $script:State.Conn.Public } else { '' }
                $authKey = Get-ConfigValue 'AuthKey'
                $extraIps = @()
                if ($script:State -and $script:State.Conn) {
                    if ($script:State.Conn.Vpn) { $extraIps += @($script:State.Conn.Vpn | Where-Object { $_.Ip } | ForEach-Object { $_.Ip }) }
                    if ($script:State.Conn.Tailscale) { $extraIps += $script:State.Conn.Tailscale }
                }
                $cleanLine = Protect-StreamerText $Line $true $pubIp $authKey $extraIps
            }
            $script:LogBox.SelectionStart = $script:LogBox.TextLength
            $script:LogBox.SelectionLength = 0
            $script:LogBox.SelectionColor = $Theme.muted
            $script:LogBox.AppendText($ts)

            $lineCol = $Theme.textSec
            if ($Line -match '^\[OK\]|^\[READY\]|forwarded|verified|saved|accepted') {
                $lineCol = $Theme.green
            } elseif ($Line -match '^\[ERROR\]|FAILED|failed') {
                $lineCol = $Theme.red
            } elseif ($Line -match '^\[WARN\]|^\[NOTE\]|CGNAT|MISSING') {
                $lineCol = $Theme.yellow
            } elseif ($Line -match '^=====') {
                $lineCol = $Theme.blue
            }
            $script:LogBox.SelectionStart = $script:LogBox.TextLength
            $script:LogBox.SelectionLength = 0
            $script:LogBox.SelectionColor = $lineCol
            $script:LogBox.AppendText($cleanLine + [Environment]::NewLine)
        }
        if ($script:LogBox.Lines.Count -gt 520) {
            $script:LogBox.Select(0, $script:LogBox.GetFirstCharIndexFromLine(40))
            $script:LogBox.ReadOnly = $false
            $script:LogBox.SelectedText = ''
            $script:LogBox.ReadOnly = $true
        }
        $script:LogBox.SelectionStart = $script:LogBox.TextLength
        $script:LogBox.ScrollToCaret()
        if ($script:SyncLogScroll) { & $script:SyncLogScroll }
    } finally {
        $script:LogBox.ResumeLayout()
    }
}

function Add-Log([string]$Line) {
    if ($Line) { Add-LogBatch @($Line) }
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
# The start flow's own 'precheck' ALWAYS runs immediately (v0.6.9 behavior):
# Start-ServerFlow sets $script:Starting before asking for it, so the generic
# queue gate would latch the startup forever after "===== Starting the server =====".
function Start-CoreAction {
    param([string]$Script, [string]$Tag = 'action')
    if ($script:Busy -or ($script:Starting -and $Tag -ne 'precheck')) {
        $script:ActionQueue.Enqueue(@{ Script = $Script; Tag = $Tag })
        return
    }
    Start-CoreActionImpl -Script $Script -Tag $Tag
}

function QStr([string]$Value) {
    return "'" + ($Value -replace "'", "''") + "'"
}

function Update-BusyUi {
    # Navigation tabs remain enabled at all times so switching tabs is never delayed or blocked.
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
    if (-not $Text) { return [pscustomobject]@{ Lines = 1; Height = 18 } }
    $w = [int][math]::Max(60, $MaxWidth)
    $sz = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $Font, (New-Object System.Drawing.Size($w, 0)), [System.Windows.Forms.TextFormatFlags]::WordBreak)
    $lineH = [math]::Max(14, $Font.Height)
    return [pscustomobject]@{
        Lines  = [int][math]::Max(1, [math]::Ceiling([double]$sz.Height / [double]$lineH))
        Height = [int]$sz.Height
    }
}

# ---------------------------------------------------------------------------------------
# RESPONSIVE LAYOUT HELPERS
# Every page = docked chrome + scrollable stack of rounded cards. Cards are
# TableLayoutPanels (fixed label column + stretching content column) measured
# deterministically at the exact viewport width so wrapped text and buttons
# never clip at any window size.
# ---------------------------------------------------------------------------------------

# A rounded section card. Returns the card (its .Tag holds the inner TLP).
function New-Card([string]$Title, [string]$Subtitle = '') {
    $card = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $card
    $card.BackColor = $Theme.card
    $card.AutoSize = $false
    $card.Padding = New-Object System.Windows.Forms.Padding(20, 14, 20, 16)
    $card.Add_SizeChanged({ $this.Invalidate() })
    $card.Add_Paint({
        param($s, $e)
        try {
            $e.Graphics.DrawRectangle((Get-CachedPen $Theme.border 1), 0, 0, ($s.Width - 1), ($s.Height - 1))
            $e.Graphics.DrawLine((Get-CachedPen $Theme.borderHi 1), 1, 0, ($s.Width - 2), 0)
            $e.Graphics.FillRectangle((Get-CachedBrush $Theme.blue), 0, 14, 3, 20)
        } catch { }
    })
    $t = New-Object System.Windows.Forms.TableLayoutPanel
    Enable-DoubleBuffer $t
    $t.Location = New-Object System.Drawing.Point(20, 14)
    $t.AutoSize = $true
    $t.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $t.ColumnCount = 2
    $null = $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 220)))
    $null = $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $card.Controls.Add($t)
    $lblT = New-Object System.Windows.Forms.Label
    $lblT.Text = $Title
    $lblT.AutoSize = $true
    $lblT.Anchor = 'Left'
    $lblT.Font = Get-CachedFont 'Segoe UI Semibold' 10.75 ([System.Drawing.FontStyle]::Bold)
    $lblT.ForeColor = [System.Drawing.Color]::White
    $lblT.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 2)
    $r = $t.RowCount; $t.RowCount = $r + 1
    $null = $t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $t.Controls.Add($lblT, 0, $r); $t.SetColumnSpan($lblT, 2)
    if ($Subtitle) {
        $lblS = New-Object System.Windows.Forms.Label
        $lblS.Text = $Subtitle
        $lblS.AutoSize = $true
        $lblS.Anchor = 'Left'
        $lblS.ForeColor = $Theme.dim
        $lblS.Font = Get-CachedFont 'Segoe UI' 8.75
        $lblS.Margin = New-Object System.Windows.Forms.Padding(0, 1, 0, 8)
        $r = $t.RowCount; $t.RowCount = $r + 1
        $null = $t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
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
    $lbl.AutoSize = $true
    $lbl.Anchor = 'Left'
    $lbl.ForeColor = $Theme.dim
    $lbl.Font = Get-CachedFont 'Segoe UI' 9.25
    $lbl.Margin = New-Object System.Windows.Forms.Padding(0, 6, 8, 4)
    $Control.Anchor = 'Left,Right'
    $Control.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 3)
    $r = $t.RowCount; $t.RowCount = $r + 1
    $null = $t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $t.Controls.Add($lbl, 0, $r)
    $t.Controls.Add($Control, 1, $r)
}

# Full-width row (checkbox / wrapped note / button bar). IMPORTANT: the control
# is placed directly with a column span - adding a label next to it corrupts
# the stretch of every following content column.
function Add-RowFull($Card, $Control) {
    $t = $Card.Tag
    if ($Control -is [System.Windows.Forms.Button]) {
        $Control.Anchor = 'Left'
    } else {
        $Control.Anchor = 'Left,Right'
    }
    $Control.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 3)
    $r = $t.RowCount; $t.RowCount = $r + 1
    $null = $t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $t.Controls.Add($Control, 0, $r)
    $t.SetColumnSpan($Control, 2)
}

# Wrapped, multi-line note text.
function Add-RowNote($Card, [string]$Text, [System.Drawing.Color]$Color) {
    $w = New-Object System.Windows.Forms.Label
    $w.Text = $Text
    $w.AutoSize = $true
    $w.Anchor = 'Left'
    $w.ForeColor = $Color
    $w.Font = Get-CachedFont 'Segoe UI' 8.75
    $w.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 4)
    $t = $Card.Tag
    $r = $t.RowCount; $t.RowCount = $r + 1
    $null = $t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $t.Controls.Add($w, 0, $r)
    $t.SetColumnSpan($w, 2)
    return $w
}

# Horizontal bar of buttons (or any small controls). Wraps cleanly if window is narrow.
function New-ButtonBar {
    $fl = New-Object System.Windows.Forms.FlowLayoutPanel
    Enable-DoubleBuffer $fl
    $fl.AutoSize = $true
    $fl.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $fl.MinimumSize = New-Object System.Drawing.Size(0, 38)
    $fl.WrapContents = $true
    $fl.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $fl.Padding = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)
    return $fl
}

# Modernized Material Input Styling via Native WPF XAML Injection
$script:WpfInputXaml = @"
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <SolidColorBrush x:Key="InputBg" Color="#050508"/>
    <SolidColorBrush x:Key="InputBorder" Color="#27272A"/>
    <SolidColorBrush x:Key="InputBorderHover" Color="#3F3F46"/>
    <SolidColorBrush x:Key="InputBorderFocus" Color="#3B82F6"/>
    <SolidColorBrush x:Key="InputFg" Color="#F4F4F8"/>
    <SolidColorBrush x:Key="ScrollThumb" Color="#27272A"/>
    <SolidColorBrush x:Key="ScrollThumbHover" Color="#3F3F46"/>
    <SolidColorBrush x:Key="CaretColor" Color="#F4F4F8"/>

    <Style x:Key="DarkScrollThumb" TargetType="{x:Type Thumb}">
        <Setter Property="OverridesDefaultStyle" Value="true"/>
        <Setter Property="IsTabStop" Value="false"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type Thumb}">
                    <Border Background="{StaticResource ScrollThumb}" CornerRadius="3"/>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="true">
                            <Setter Property="Background" Value="{StaticResource ScrollThumbHover}"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style x:Key="DarkScrollBar" TargetType="{x:Type ScrollBar}">
        <Setter Property="OverridesDefaultStyle" Value="true"/>
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="Width" Value="8"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type ScrollBar}">
                    <Grid Background="Transparent">
                        <Track x:Name="PART_Track" IsDirectionReversed="true">
                            <Track.Thumb>
                                <Thumb Style="{StaticResource DarkScrollThumb}" Width="6" Margin="1,2,1,2"/>
                            </Track.Thumb>
                        </Track>
                    </Grid>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style x:Key="ModernTextBox" TargetType="{x:Type TextBox}">
        <Setter Property="Background" Value="{StaticResource InputBg}"/>
        <Setter Property="Foreground" Value="{StaticResource InputFg}"/>
        <Setter Property="BorderBrush" Value="{StaticResource InputBorder}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="CaretBrush" Value="{StaticResource CaretColor}"/>
        <Setter Property="Padding" Value="8,5,8,5"/>
        <Setter Property="VerticalContentAlignment" Value="Center"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type TextBox}">
                    <Border x:Name="border"
                            Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="{TemplateBinding BorderThickness}"
                            CornerRadius="6"
                            SnapsToDevicePixels="True">
                        <ScrollViewer x:Name="PART_ContentHost"
                                      Focusable="false"
                                      HorizontalScrollBarVisibility="{TemplateBinding HorizontalScrollBarVisibility}"
                                      VerticalScrollBarVisibility="{TemplateBinding VerticalScrollBarVisibility}"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="true">
                            <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource InputBorderHover}"/>
                        </Trigger>
                        <Trigger Property="IsFocused" Value="true">
                            <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource InputBorderFocus}"/>
                            <Setter TargetName="border" Property="Background" Value="#090910"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
        <Style.Resources>
            <Style TargetType="{x:Type ScrollBar}" BasedOn="{StaticResource DarkScrollBar}"/>
        </Style.Resources>
    </Style>

    <Style x:Key="ModernPasswordBox" TargetType="{x:Type PasswordBox}">
        <Setter Property="Background" Value="{StaticResource InputBg}"/>
        <Setter Property="Foreground" Value="{StaticResource InputFg}"/>
        <Setter Property="BorderBrush" Value="{StaticResource InputBorder}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="CaretBrush" Value="{StaticResource CaretColor}"/>
        <Setter Property="Padding" Value="8,5,8,5"/>
        <Setter Property="VerticalContentAlignment" Value="Center"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="{x:Type PasswordBox}">
                    <Border x:Name="border"
                            Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="{TemplateBinding BorderThickness}"
                            CornerRadius="6"
                            SnapsToDevicePixels="True">
                        <ScrollViewer x:Name="PART_ContentHost"
                                      Focusable="false"
                                      HorizontalScrollBarVisibility="Hidden"
                                      VerticalScrollBarVisibility="Hidden"/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="true">
                            <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource InputBorderHover}"/>
                        </Trigger>
                        <Trigger Property="IsFocused" Value="true">
                            <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource InputBorderFocus}"/>
                            <Setter TargetName="border" Property="Background" Value="#090910"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
</ResourceDictionary>
"@
try {
    $script:WpfInputResources = [System.Windows.Markup.XamlReader]::Parse($script:WpfInputXaml)
} catch {
    $script:WpfInputResources = $null
}

# Modernized Material Input Field Generator
function New-SettingsInput {
    if ($script:WpfInputResources) {
        $hostCtrl = New-Object System.Windows.Forms.Integration.ElementHost
        $hostCtrl.BackColor = $Theme.card
        $hostCtrl.Height = 32

        $tb = New-Object System.Windows.Controls.TextBox
        $tb.Style = $script:WpfInputResources["ModernTextBox"]
        $tb.FontSize = 12.5
        $tb.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
        $hostCtrl.Child = $tb

        $hostCtrl | Add-Member -MemberType NoteProperty -Name 'InnerBox' -Value $tb -Force
        $hostCtrl | Add-Member -MemberType NoteProperty -Name 'IsPassword' -Value $false -Force

        $hostCtrl | Add-Member -MemberType ScriptProperty -Name 'Text' -Value {
            if ($this.IsPassword) { $this.Child.Password } else { $this.Child.Text }
        } -SecondValue {
            param($val)
            if ($this.IsPassword) {
                $this.Child.Password = [string]$val
            } else {
                $this.Child.Text = [string]$val
            }
        } -Force

        $hostCtrl | Add-Member -MemberType ScriptProperty -Name 'Multiline' -Value {
            if (-not $this.IsPassword) { $this.Child.AcceptsReturn } else { $false }
        } -SecondValue {
            param($val)
            if (-not $this.IsPassword) {
                $this.Child.AcceptsReturn = [bool]$val
                $this.Child.TextWrapping = if ($val) { [System.Windows.TextWrapping]::Wrap } else { [System.Windows.TextWrapping]::NoWrap }
                if ($val) {
                    $this.Child.VerticalContentAlignment = [System.Windows.VerticalAlignment]::Top
                    $this.Child.Padding = New-Object System.Windows.Thickness(8, 6, 8, 6)
                }
            }
        } -Force

        $hostCtrl | Add-Member -MemberType ScriptProperty -Name 'ScrollBars' -Value {
            if (-not $this.IsPassword) { $this.Child.VerticalScrollBarVisibility.ToString() } else { 'None' }
        } -SecondValue {
            param($val)
            if (-not $this.IsPassword -and ($val -eq 'Vertical' -or $val -eq 2)) {
                $this.Child.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
            }
        } -Force

        $hostCtrl | Add-Member -MemberType ScriptProperty -Name 'UseSystemPasswordChar' -Value {
            $this.IsPassword
        } -SecondValue {
            param($val)
            if ($val -and -not $this.IsPassword) {
                $curVal = $this.Child.Text
                $pb = New-Object System.Windows.Controls.PasswordBox
                $pb.Style = $script:WpfInputResources["ModernPasswordBox"]
                $pb.FontSize = 12.5
                $pb.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
                $pb.Password = $curVal
                $this.Child = $pb
                $this.IsPassword = $true
            }
        } -Force

        $hostCtrl | Add-Member -MemberType ScriptMethod -Name 'Add_TextChanged' -Value {
            param($handler)
            if (-not $this.IsPassword) {
                $this.Child.Add_TextChanged($handler)
            }
        } -Force

        return $hostCtrl
    } else {
        # Fallback for environments where WPF XAML is unavailable
        $t = New-Object System.Windows.Forms.TextBox
        $t.BackColor = [System.Drawing.Color]::FromArgb(5, 5, 8)
        $t.ForeColor = $Theme.text
        $t.BorderStyle = 'FixedSingle'
        $t.Font = Get-CachedFont 'Segoe UI' 9.5
        $t.Add_GotFocus({ $this.BackColor = [System.Drawing.Color]::FromArgb(9, 9, 16) })
        $t.Add_LostFocus({ $this.BackColor = [System.Drawing.Color]::FromArgb(5, 5, 8) })
        return $t
    }
}

# Deterministically measures and positions every card in the active card stack
# so wrapped labels, checkboxes, and button bars never clip at any window size.
function Update-CardStackLayout {
    if (-not $script:StackRefs -or -not $script:StackRefs.Body -or $script:StackRefs.Body.IsDisposed) { return }
    $body = $script:StackRefs.Body
    $content = $script:StackRefs.Content
    if (-not $content -or $content.IsDisposed) { return }
    $cards = $content.Tag
    if (-not $cards -or -not $cards.Count) { return }
    if ($body.ClientSize.Width -le 50) { return }

    $stackW = [int][math]::Max(340, ($body.ClientSize.Width - 34))
    $content.SuspendLayout()
    try {
        $curY = 0
        foreach ($card in $cards) {
            if (-not $card -or $card.IsDisposed -or -not $card.Visible) { continue }
            $t = $card.Tag
            if (-not ($t -is [System.Windows.Forms.TableLayoutPanel])) { continue }
            $t.SuspendLayout()
            try {
                $padH = $card.Padding.Left + $card.Padding.Right
                $padV = $card.Padding.Top + $card.Padding.Bottom
                $innerW = [int][math]::Max(240, ($stackW - $padH))
                $col0W = [int][math]::Min(220, [math]::Max(140, [int]($innerW * 0.34)))
                $col1W = [int][math]::Max(100, ($innerW - $col0W))
                if ($t.ColumnStyles.Count -ge 1) { $t.ColumnStyles[0].Width = $col0W }

                foreach ($c in $t.Controls) {
                    $span = $t.GetColumnSpan($c)
                    $col = $t.GetColumn($c)
                    $cellW = if ($span -ge 2) { $innerW } elseif ($col -eq 0) { $col0W } else { $col1W }
                    $availW = [int][math]::Max(80, ($cellW - $c.Margin.Left - $c.Margin.Right - 2))

                    if ($c -is [System.Windows.Forms.Label]) {
                        $c.AutoSize = $true
                        $c.MaximumSize = New-Object System.Drawing.Size($availW, 0)
                    } elseif ($c -is [System.Windows.Forms.CheckBox] -or $c -is [System.Windows.Forms.RadioButton]) {
                        $c.AutoSize = $true
                        $c.MaximumSize = New-Object System.Drawing.Size($availW, 0)
                    } elseif ($c -is [System.Windows.Forms.FlowLayoutPanel]) {
                        $c.AutoSize = $true
                        $c.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
                        $c.WrapContents = $true
                        $c.MaximumSize = New-Object System.Drawing.Size($availW, 0)
                        $c.MinimumSize = New-Object System.Drawing.Size($availW, 36)
                        foreach ($sub in $c.Controls) {
                            if ($sub -is [System.Windows.Forms.Label] -and $sub.AutoSize) {
                                $sub.MaximumSize = New-Object System.Drawing.Size([int][math]::Max(60, ($availW - 12)), 0)
                            }
                        }
                    } elseif ($c -is [System.Windows.Forms.Panel]) {
                        $c.Width = $availW
                        $pH = 0
                        foreach ($sub in $c.Controls) {
                            if ($sub.Dock -eq 'Top') { $pH += $sub.Height }
                            else { $b = $sub.Bottom + 4; if ($b -gt $pH) { $pH = $b } }
                        }
                        if ($pH -gt 0) {
                            $c.Height = $pH
                            $c.MinimumSize = New-Object System.Drawing.Size($availW, $pH)
                        }
                    } elseif ($c -is [System.Windows.Forms.Button]) {
                        $needW = [System.Windows.Forms.TextRenderer]::MeasureText($c.Text, $c.Font).Width + 24
                        $btnW = [int][math]::Min($availW, [math]::Max($c.Width, $needW))
                        if ($c.Width -ne $btnW) { $c.Width = $btnW }
                    } else {
                        $c.Width = $availW
                    }
                }
                $t.Location = New-Object System.Drawing.Point($card.Padding.Left, $card.Padding.Top)
                $t.MinimumSize = New-Object System.Drawing.Size($innerW, 0)
                $t.MaximumSize = New-Object System.Drawing.Size($innerW, 0)
                $t.Width = $innerW
            } finally {
                $t.ResumeLayout($true)
            }
            $t.PerformLayout()
            $maxBot = $t.PreferredSize.Height
            foreach ($c in $t.Controls) {
                if ($c.Visible) {
                    $b = $c.Bottom + $c.Margin.Bottom
                    if ($b -gt $maxBot) { $maxBot = $b }
                }
            }
            if ($maxBot -gt 0) { $t.Height = $maxBot }
            $neededH = [int]($t.Location.Y + $maxBot + $card.Padding.Bottom + 6)
            $cardH = [int][math]::Max(($maxBot + $padV + 4), $neededH)
            $card.Bounds = New-Object System.Drawing.Rectangle(0, $curY, $stackW, $cardH)
            $curY += $cardH + 12
        }
        $curScrollY = if ($script:StackRefs -and $script:StackRefs.ScrollBar) { & $script:StackRefs.ScrollBar.GetScrollY } else { 0 }
        $content.Location = New-Object System.Drawing.Point(16, (10 - $curScrollY))
        $content.Size = New-Object System.Drawing.Size($stackW, [int][math]::Max(10, ($curY + 64)))
        if ($script:StackRefs -and $script:StackRefs.ScrollBar) {
            & $script:StackRefs.ScrollBar.Sync
        }
    } finally {
        $content.ResumeLayout($true)
    }
}

function New-CardStack($Page) {
    $wrap = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $wrap
    $wrap.Dock = 'Fill'
    $wrap.BackColor = $Theme.bg

    $body = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $body
    $body.Dock = 'Fill'
    $body.BackColor = $Theme.bg
    $body.AutoScroll = $false
    $content = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $content
    $content.Location = New-Object System.Drawing.Point(16, 10)
    $content.AutoSize = $false
    $content.BackColor = $Theme.bg
    $body.Controls.Add($content)
    $body.Tag = $content

    $sbObj = Attach-ModernScrollBar $wrap $body $content { if ($content -and -not $content.IsDisposed) { $content.Height } else { 0 } }.GetNewClosure()
    $wrap.Controls.Add($body)
    $body.BringToFront()

    $script:StackRefs = @{ Wrap = $wrap; Body = $body; Content = $content; ScrollBar = $sbObj }
    $script:PageLayout = { Update-CardStackLayout }
    $body.Add_Resize({ Update-CardStackLayout })
    $Page.Controls.Add($wrap)
    $wrap.BringToFront()
    $script:MountCards = {
        param($CardList, $Content)
        $Content.Tag = @($CardList)
        $Content.SuspendLayout()
        try {
            $Content.Controls.Clear()
            foreach ($card in $CardList) {
                $Content.Controls.Add($card)
            }
        } finally {
            $Content.ResumeLayout($false)
        }
        Update-CardStackLayout
    }
    return $script:StackRefs
}

# Page header bar: title on the left, actions on the right (right-aligned flow).
function New-PageTop($Page, [string]$Title, [string]$Hint = '') {
    $top = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $top
    $top.Dock = 'Top'
    $top.Height = 58
    $top.BackColor = $Theme.panel
    $top.Padding = New-Object System.Windows.Forms.Padding(20, 10, 16, 8)
    $top.Add_Paint({
        param($s, $e)
        try {
            $e.Graphics.DrawLine((Get-CachedPen $Theme.border 1), 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
        } catch { }
    })
    $lbl = New-Lbl $Title ([System.Drawing.Color]::White) 14.5 34 $true
    $lbl.Font = Get-CachedFont 'Segoe UI Semibold' 14.5 ([System.Drawing.FontStyle]::Bold)
    $lbl.Dock = 'Left'
    $lbl.AutoSize = $true
    $lbl.Padding = New-Object System.Windows.Forms.Padding(0, 6, 16, 0)
    $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    if ($Hint) { $script:Tip.SetToolTip($lbl, $Hint) }
    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    Enable-DoubleBuffer $flow
    $flow.Dock = 'Fill'
    $flow.BackColor = [System.Drawing.Color]::Transparent
    $flow.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $flow.WrapContents = $false
    $flow.Padding = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)
    $top.Controls.Add($flow)
    $top.Controls.Add($lbl)
    return @{ Bar = $top; Flow = $flow; Title = $lbl }
}

# ---------------------------------------------------------------------------------------
# MAIN FORM (Frameless Custom Dark Title Bar + Left Sidebar + Command Center Workspace)
# ---------------------------------------------------------------------------------------
$script:Form = New-Object System.Windows.Forms.Form
Enable-DoubleBuffer $script:Form
$script:Form.Text = 'K BNG M Hoster v0.7.2.0 - by Kinan (@kinan_sx240) & @bomberrie'
$script:Form.FormBorderStyle = 'None'
$script:Form.MinimumSize = New-Object System.Drawing.Size(900, 540)
$workArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$initW = [int][math]::Min(1100, [math]::Max(900, ($workArea.Width - 32)))
$initH = [int][math]::Min(760, [math]::Max(540, ($workArea.Height - 32)))
$script:Form.Size = New-Object System.Drawing.Size($initW, $initH)
$script:Form.StartPosition = 'CenterScreen'
$script:Form.BackColor = $Theme.bg
$script:Form.ForeColor = $Theme.text
$script:Form.Font = Get-CachedFont 'Segoe UI' 9.5
$script:Form.KeyPreview = $true
$script:Tip = New-Object System.Windows.Forms.ToolTip
$script:Tip.InitialDelay = 350
$script:Tip.ReshowDelay = 80
$script:Tip.AutoPopDelay = 12000

$dot      = [char]0x00B7
$em       = [char]0x2014
$dn       = [char]0x25BE
$playIcon = [char]0x25B6
$stopIcon = [char]0x25A0

$script:IsMaximized = $false
$script:RestoreBounds = $script:Form.Bounds
$script:StreamerMode = (Test-Path -LiteralPath ($script:ServerDir + '.streamer'))
$script:AdvancedExpanded = $false

$script:DragWindowHandler = {
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and -not $script:IsMaximized -and -not $script:Fullscreen) {
        try {
            [Win32Chrome]::ReleaseCapture() | Out-Null
            [Win32Chrome]::SendMessage($script:Form.Handle, 0x00A1, [IntPtr]2, [IntPtr]0) | Out-Null
        } catch { }
    }
}


# ---------------------------------------------------------------------------------------
# STREAMER PRIVACY MODE DISPATCHER
# ---------------------------------------------------------------------------------------
function Set-StreamerMode([bool]$Enabled) {
    $script:StreamerMode = $Enabled
    $streamerFile = $script:ServerDir + '.streamer'
    if ($Enabled) {
        Set-Content -LiteralPath $streamerFile -Value '1' -ErrorAction SilentlyContinue
    } else {
        Remove-Item -LiteralPath $streamerFile -Force -ErrorAction SilentlyContinue
    }

    if ($script:BtnHeaderStreamer) {
        $script:BtnHeaderStreamer.Invalidate()
    }

    if ($script:ChkStreamerMode -and $script:ChkStreamerMode.Checked -ne $Enabled) {
        $script:SuppressSettingEvents = $true
        $script:ChkStreamerMode.Checked = $Enabled
        $script:SuppressSettingEvents = $false
    }

    if ($Enabled -and $script:LogBox -and $script:LogBox.Text) {
        try {
            $pub = if ($script:State -and $script:State.Conn) { $script:State.Conn.Public } else { '' }
            $key = Get-ConfigValue 'AuthKey'
            $extraIps = @()
            if ($script:State -and $script:State.Conn) {
                if ($script:State.Conn.Vpn) { $extraIps += @($script:State.Conn.Vpn | Where-Object { $_.Ip } | ForEach-Object { $_.Ip }) }
                if ($script:State.Conn.Tailscale) { $extraIps += $script:State.Conn.Tailscale }
            }
            $clean = Protect-StreamerText $script:LogBox.Text $true $pub $key $extraIps
            if ($clean -ne $script:LogBox.Text) {
                $script:LogBox.SuspendLayout()
                $script:LogBox.Text = $clean
                $script:LogBox.SelectionStart = $script:LogBox.TextLength
                $script:LogBox.ScrollToCaret()
                if ($script:SyncLogScroll) { & $script:SyncLogScroll }
                $script:LogBox.ResumeLayout($true)
            }
        } catch { }
    }

    Refresh-Dashboard
    if ($script:VpnRowsWrap) {
        Refresh-VpnRows
    }

    Add-Log "[INFO] Streamer Privacy Mode $(if ($Enabled) { 'ENABLED (WAN IP, AuthKey & user paths masked)' } else { 'DISABLED (Standard display)' })"
}

function Toggle-StreamerMode {
    Set-StreamerMode (-not [bool]$script:StreamerMode)
}

function Toggle-MaximizeWindow {
    if ($script:Fullscreen) { Toggle-Fullscreen; return }
    if ($script:IsMaximized) {
        $script:IsMaximized = $false
        $script:Form.WindowState = 'Normal'
        if ($script:RestoreBounds -and $script:RestoreBounds.Width -gt 200) {
            $script:Form.Bounds = $script:RestoreBounds
        }
    } else {
        $script:RestoreBounds = $script:Form.Bounds
        $script:IsMaximized = $true
        $script:Form.WindowState = 'Normal'
        $script:Form.Bounds = [System.Windows.Forms.Screen]::FromControl($script:Form).WorkingArea
    }
    try { $script:Form.PerformLayout() } catch { }
    if ($script:BtnWinMax) { $script:BtnWinMax.Invalidate() }
}

# ---------------- Custom Dark Title Bar ----------------
$titleBar = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $titleBar
$titleBar.Dock = 'Top'
$titleBar.Height = 38
$titleBar.BackColor = $Theme.log
$titleBar.Add_MouseDown($script:DragWindowHandler)
$titleBar.Add_DoubleClick({ Toggle-MaximizeWindow })
$titleBar.Add_Paint({
    param($s, $e)
    try {
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        # Top 2px accent bar
        $g.FillRectangle((Get-CachedBrush $Theme.blue), 0, 0, $s.Width, 2)
        # Glowing K emblem badge on the left
        $badgePath = Get-RoundedRectPath 14 9 20 20 5
        try {
            $g.FillPath((Get-CachedBrush $Theme.btnAct), $badgePath)
            $g.DrawPath((Get-CachedPen $Theme.blue 1), $badgePath)
        } finally { $badgePath.Dispose() }
        $fBadge = Get-CachedFont 'Segoe UI Semibold' 9 ([System.Drawing.FontStyle]::Bold)
        $rBadge = New-Object System.Drawing.Rectangle(14, 9, 20, 20)
        [System.Windows.Forms.TextRenderer]::DrawText($g, 'K', $fBadge, $rBadge, [System.Drawing.Color]::White, ([System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter))
        # Bottom 1px separator
        $g.DrawLine((Get-CachedPen $Theme.border 1), 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
    } catch { }
})

$titleBrand = New-Lbl 'K BNG M HOSTER' ([System.Drawing.Color]::White) 9.5 22 $true
$titleBrand.Font = Get-CachedFont 'Segoe UI Semibold' 9.5 ([System.Drawing.FontStyle]::Bold)
$titleBrand.Location = New-Object System.Drawing.Point(42, 10)
$titleBrand.Add_MouseDown($script:DragWindowHandler)
$titleBrand.Add_DoubleClick({ Toggle-MaximizeWindow })

$script:LblVersionChip = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $script:LblVersionChip
$script:LblVersionChip.BackColor = $Theme.btnAct
$script:LblVersionChip.Size = New-Object System.Drawing.Size(48, 20)
$script:LblVersionChip.Location = New-Object System.Drawing.Point(162, 10)
$script:LblVersionChip.Add_Paint({
    param($s, $e)
    try {
        $e.Graphics.DrawRectangle((Get-CachedPen $Theme.accentDim 1), 0, 0, ($s.Width - 1), ($s.Height - 1))
    } catch { }
})
$chipText = New-Lbl 'v0.7.2' $Theme.blue 8 18 $true
$chipText.AutoSize = $false
$chipText.Size = New-Object System.Drawing.Size(48, 18)
$chipText.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$chipText.Location = New-Object System.Drawing.Point(0, 1)
$chipText.Add_MouseDown($script:DragWindowHandler)
$script:LblVersionChip.Controls.Add($chipText)

$script:LblSubtitle = New-Lbl "BeamMP Server Command Center  $dot  FRP Tunnel + Playit.gg  $dot  by Kinan (@kinan_sx240)  $dot  UI by @bomberrie" $Theme.dim 8.5 20
$script:LblSubtitle.AutoSize = $false
$script:LblSubtitle.AutoEllipsis = $true
$script:LblSubtitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:LblSubtitle.Location = New-Object System.Drawing.Point(220, 9)
$script:LblSubtitle.Size = New-Object System.Drawing.Size(460, 20)
$script:LblSubtitle.Add_MouseDown($script:DragWindowHandler)
$script:LblSubtitle.Add_DoubleClick({ Toggle-MaximizeWindow })
$titleBar.Add_Resize({
    if ($script:LblSubtitle) {
        $reserved = (46 * 3) + 142 + 24
        $script:LblSubtitle.Width = [int][math]::Max(60, ($this.ClientSize.Width - 220 - $reserved))
    }
})

# Custom Window Control Buttons (Panel-based so Set-LicenseLock never disables them)
function New-WindowCtrlBtn([string]$Kind, [string]$TipText, [scriptblock]$OnClick) {
    $p = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $p
    $p.Dock = 'Right'
    $p.Width = 46
    $p.BackColor = [System.Drawing.Color]::Transparent
    $p.Cursor = [System.Windows.Forms.Cursors]::Hand
    $p.Tag = $Kind
    if ($TipText) { $script:Tip.SetToolTip($p, $TipText) }
    $p.Add_MouseEnter({ if ($this.AccessibleDescription -ne 'hover') { $this.AccessibleDescription = 'hover'; $this.Invalidate() } })
    $p.Add_MouseLeave({ if ($this.AccessibleDescription -ne '') { $this.AccessibleDescription = ''; $this.Invalidate() } })
    $p.Add_Click($OnClick)
    $p.Add_Paint({
        param($s, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $hov = ($s.AccessibleDescription -eq 'hover')
            $kind = [string]$s.Tag
            if ($hov) {
                $bgCol = if ($kind -eq 'close') { $Theme.btnDangerBorder } else { $Theme.surface }
                $g.FillRectangle((Get-CachedBrush $bgCol), 0, 2, $s.Width, ($s.Height - 3))
            }
            $fgCol = if ($hov) { [System.Drawing.Color]::White } else { $Theme.dim }
            $pen = Get-CachedPen $fgCol 1.5
            $cx = [int]($s.Width / 2)
            $cy = [int]($s.Height / 2) + 1
            if ($kind -eq 'min') {
                $g.DrawLine($pen, ($cx - 5), $cy, ($cx + 5), $cy)
            } elseif ($kind -eq 'max') {
                if ($script:IsMaximized -or $script:Fullscreen) {
                    $g.DrawRectangle($pen, ($cx - 3), ($cy - 5), 8, 8)
                    $g.DrawRectangle($pen, ($cx - 5), ($cy - 3), 8, 8)
                } else {
                    $g.DrawRectangle($pen, ($cx - 5), ($cy - 5), 10, 10)
                }
            } elseif ($kind -eq 'close') {
                $g.DrawLine($pen, ($cx - 5), ($cy - 5), ($cx + 5), ($cy + 5))
                $g.DrawLine($pen, ($cx + 5), ($cy - 5), ($cx - 5), ($cy + 5))
            }
        } catch { }
    })
    return $p
}

$script:BtnHeaderStreamer = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $script:BtnHeaderStreamer
$script:BtnHeaderStreamer.Dock = 'Right'
$script:BtnHeaderStreamer.Width = 142
$script:BtnHeaderStreamer.Height = 26
$script:BtnHeaderStreamer.BackColor = [System.Drawing.Color]::Transparent
$script:BtnHeaderStreamer.Cursor = [System.Windows.Forms.Cursors]::Hand
$script:Tip.SetToolTip($script:BtnHeaderStreamer, 'Streamer Privacy Mode: Click to toggle real-time masking of WAN IP, AuthKey, and personal file paths.')
$script:BtnHeaderStreamer.Add_Click({ Toggle-StreamerMode })
$script:BtnHeaderStreamer.Add_MouseEnter({ $this.AccessibleDescription = 'hover'; $this.Invalidate() })
$script:BtnHeaderStreamer.Add_MouseLeave({ $this.AccessibleDescription = ''; $this.Invalidate() })
$script:BtnHeaderStreamer.Add_MouseDown({ $this.AccessibleDescription = 'down'; $this.Invalidate() })
$script:BtnHeaderStreamer.Add_MouseUp({ $this.AccessibleDescription = 'hover'; $this.Invalidate() })
$script:BtnHeaderStreamer.Add_Paint({
    param($s, $e)
    try {
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $active = [bool]$script:StreamerMode
        $hov = ($s.AccessibleDescription -eq 'hover')
        $down = ($s.AccessibleDescription -eq 'down')

        $pillW = $s.Width - 12
        $pillH = 24
        $pillX = 6
        $pillY = [int](($s.Height - $pillH) / 2)

        if ($active) {
            # Modern Emerald Shield Activation with distinct color-shift surface
            $bgCol = if ($down) { [System.Drawing.Color]::FromArgb(45, 12, 100, 70) } elseif ($hov) { [System.Drawing.Color]::FromArgb(50, 16, 140, 95) } else { [System.Drawing.Color]::FromArgb(35, 16, 128, 88) }
            $borderCol = if ($hov) { [System.Drawing.Color]::FromArgb(100, 52, 211, 153) } else { [System.Drawing.Color]::FromArgb(65, 52, 211, 153) }
            $thumbCol = [System.Drawing.Color]::FromArgb(52, 211, 153)
            $textCol = [System.Drawing.Color]::FromArgb(52, 211, 153)
            $statusText = 'STREAMER: ON'
        } else {
            # Soft-elevated #1c1c24 dark zinc surface with subtle translucent border
            $bgCol = if ($down) { [System.Drawing.Color]::FromArgb(18, 18, 24) } elseif ($hov) { [System.Drawing.Color]::FromArgb(32, 32, 42) } else { [System.Drawing.Color]::FromArgb(24, 24, 32) }
            $borderCol = if ($hov) { [System.Drawing.Color]::FromArgb(45, 255, 255, 255) } else { [System.Drawing.Color]::FromArgb(20, 255, 255, 255) }
            $thumbCol = if ($hov) { [System.Drawing.Color]::FromArgb(150, 150, 165) } else { [System.Drawing.Color]::FromArgb(100, 100, 115) }
            $textCol = if ($hov) { [System.Drawing.Color]::FromArgb(225, 225, 235) } else { [System.Drawing.Color]::FromArgb(150, 150, 165) }
            $statusText = 'STREAMER: OFF'
        }

        $path = Get-RoundedRectPath $pillX $pillY $pillW $pillH 12
        try {
            $g.FillPath((Get-CachedBrush $bgCol), $path)
            $g.DrawPath((Get-CachedPen $borderCol 1), $path)
        } finally { $path.Dispose() }

        # Tactile switch indicator dot
        $dotSz = 8
        $dotX = $pillX + 8
        $dotY = $pillY + [int](($pillH - $dotSz) / 2)
        $g.FillEllipse((Get-CachedBrush $thumbCol), $dotX, $dotY, $dotSz, $dotSz)
        if ($active) {
            $g.FillEllipse((Get-CachedBrush [System.Drawing.Color]::White), ($dotX + 2), ($dotY + 2), 4, 4)
        }

        $fBtn = Get-CachedFont 'Segoe UI Semibold' 8 ([System.Drawing.FontStyle]::Bold)
        $rText = New-Object System.Drawing.Rectangle(($dotX + $dotSz + 7), $pillY, ($pillW - $dotSz - 16), $pillH)
        [System.Windows.Forms.TextRenderer]::DrawText($g, $statusText, $fBtn, $rText, $textCol, ([System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix))
    } catch { }
})

$script:BtnWinMin   = New-WindowCtrlBtn 'min'   'Minimize window'          { $script:Form.WindowState = 'Minimized' }
$script:BtnWinMax   = New-WindowCtrlBtn 'max'   'Maximize / Restore (F11 for Fullscreen)' { Toggle-MaximizeWindow }
$script:BtnWinClose = New-WindowCtrlBtn 'close' 'Close K BNG M Hoster'     { $script:Form.Close() }

$titleBar.Controls.Add($titleBrand)
$titleBar.Controls.Add($script:LblVersionChip)
$titleBar.Controls.Add($script:LblSubtitle)
$titleBar.Controls.Add($script:BtnHeaderStreamer)
$titleBar.Controls.Add($script:BtnWinMin)
$titleBar.Controls.Add($script:BtnWinMax)
$titleBar.Controls.Add($script:BtnWinClose)

# ---------------- Left Sidebar (Server Control Pod + Navigation) ----------------
$sidebar = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $sidebar
$sidebar.Dock = 'Left'
$sidebar.Width = 224
$sidebar.BackColor = $Theme.panel
$sidebar.Add_MouseDown($script:DragWindowHandler)
$sidebar.Add_Paint({
    param($s, $e)
    try {
        $e.Graphics.DrawLine((Get-CachedPen $Theme.border 1), ($s.Width - 1), 0, ($s.Width - 1), $s.Height)
    } catch { }
})

# Server Control Pod inside sidebar (Tactile elevated pod container)
$ctrlPod = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $ctrlPod
$ctrlPod.BackColor = $Theme.card
$ctrlPod.Location = New-Object System.Drawing.Point(12, 14)
$ctrlPod.Size = New-Object System.Drawing.Size(200, 96)
$ctrlPod.Add_Paint({
    param($s, $e)
    try {
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $w = $s.Width - 1
        $h = $s.Height - 1
        if ($w -le 2 -or $h -le 2) { return }
        $path = Get-RoundedRectPath 0 0 $w $h 8
        try {
            $g.FillPath((Get-CachedBrush ([System.Drawing.Color]::FromArgb(18, 18, 23))), $path)
            $g.DrawPath((Get-CachedPen ([System.Drawing.Color]::FromArgb(38, 38, 48)) 1), $path)
        } finally { $path.Dispose() }
        $g.DrawLine((Get-CachedPen ([System.Drawing.Color]::FromArgb(55, 55, 68)) 1), 8, 0, ($w - 8), 0)
    } catch { }
})

$script:BtnStart = New-Btn "$playIcon  Start Server" 'Start the BeamMP server and open the launcher. Friends join via the addresses shown on the Home page. (Ctrl+S)' { Start-ServerFlow }
$script:BtnStart.Location = New-Object System.Drawing.Point(10, 10)
$script:BtnStart.Size = New-Object System.Drawing.Size(180, 38)
$script:BtnStart.BackColor = $Theme.btnSuccess
$script:BtnStart.FlatAppearance.MouseOverBackColor = $Theme.btnSuccessHov
$script:BtnStart.FlatAppearance.BorderColor = $Theme.green
$script:BtnStart.ForeColor = [System.Drawing.Color]::White
$script:BtnStart.Font = Get-CachedFont 'Segoe UI Semibold' 10 ([System.Drawing.FontStyle]::Bold)

$script:BtnStop = New-Btn "$stopIcon  Stop Server" 'Stop the running server. Closing the launcher window also stops it. (Ctrl+X)' { Stop-ServerFlow }
$script:BtnStop.Location = New-Object System.Drawing.Point(10, 54)
$script:BtnStop.Size = New-Object System.Drawing.Size(180, 32)
$script:BtnStop.BackColor = $Theme.btnDanger
$script:BtnStop.FlatAppearance.MouseOverBackColor = $Theme.btnDangerHov
$script:BtnStop.FlatAppearance.BorderColor = $Theme.btnDangerBorder
$script:BtnStop.ForeColor = [System.Drawing.Color]::White
$script:BtnStop.Font = Get-CachedFont 'Segoe UI Semibold' 9 ([System.Drawing.FontStyle]::Regular)
$script:BtnStop.Enabled = $false

$ctrlPod.Controls.Add($script:BtnStart)
$ctrlPod.Controls.Add($script:BtnStop)
$sidebar.Controls.Add($ctrlPod)

function New-SidebarSection([string]$Text, [int]$Y) {
    $l = New-Lbl $Text $Theme.muted 7.75 16 $true 190
    $l.Location = New-Object System.Drawing.Point(16, $Y)
    $sidebar.Controls.Add($l)
}

function New-SidebarNavBtn([string]$Text, [string]$Tip, [scriptblock]$OnClick, [int]$Y, [string]$Shortcut = '') {
    $b = New-Btn $Text $Tip $OnClick
    $b.AccessibleRole = [System.Windows.Forms.AccessibleRole]::MenuItem
    if ($Shortcut) { $b.Name = $Shortcut }
    $b.Location = New-Object System.Drawing.Point(10, $Y)
    $b.Size = New-Object System.Drawing.Size(204, 34)
    $sidebar.Controls.Add($b)
    return $b
}

New-SidebarSection 'OVERVIEW' 122
$script:BtnHome     = New-SidebarNavBtn 'Dashboard'          'Server status and the addresses your friends use to join. (Ctrl+H)' { Show-HomePage } 140 '^H'

New-SidebarSection 'CONFIGURATION' 186
$script:BtnSettings = New-SidebarNavBtn 'Server Settings'    'Server name, players, map, visibility, port and your server key - everything in one scroll. (Ctrl+T)' { Show-SettingsPage } 204 '^T'
$script:BtnMods     = New-SidebarNavBtn 'Mod Manager'        'Manage your mods: enable, disable, scan for suspicious files. (Ctrl+M)' { Show-ModsPage } 242 '^M'
$script:BtnNetwork  = New-SidebarNavBtn 'Network & Tunnels'  'FRP tunnel, VPN tools (Radmin / Hamachi / ZeroTier / Tailscale / Playit.gg) and CGNAT help. (Ctrl+V)' { Show-NetworkPage } 280 '^V'
$script:BtnTransfer = New-SidebarNavBtn 'Cloud Transfer'     'Export + split your server mods for cloud upload, install downloaded mods and delete only the ones you pick. (Ctrl+U)' { Show-TransferPage } 318 '^U'

New-SidebarSection 'DIAGNOSTICS & TOOLS' 364
$script:BtnFix      = New-SidebarNavBtn 'Scan & Fix'         'Scan your setup and repair common issues (key, port, firewall, CGNAT). (Ctrl+F)' { Show-FixPage } 382 '^F'
$script:BtnMore     = New-SidebarNavBtn "More Tools  $dn"    'Guide, Extra, Support, Open Folder, Clean Info. (menu)' { Show-MoreMenu } 420 ''

# Sidebar Bottom Telemetry & Quick-Access Pod
$sideFooter = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $sideFooter
$sideFooter.Dock = 'Bottom'
$sideFooter.Height = 84
$sideFooter.BackColor = $Theme.panel
$sideFooter.Add_Paint({
    param($s, $e)
    try {
        $e.Graphics.DrawLine((Get-CachedPen $Theme.border 1), 12, 0, ($s.Width - 13), 0)
    } catch { }
})
$sideStatusPill = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $sideStatusPill
$sideStatusPill.BackColor = $Theme.card
$sideStatusPill.Location = New-Object System.Drawing.Point(12, 10)
$sideStatusPill.Size = New-Object System.Drawing.Size(200, 24)
$sideStatusPill.Add_Paint({
    param($s, $e)
    try {
        $e.Graphics.DrawRectangle((Get-CachedPen $Theme.border 1), 0, 0, ($s.Width - 1), ($s.Height - 1))
    } catch { }
})
$script:LblSideFooterStatus = New-Lbl "$([char]0x25CF) STANDBY  $dot  Port 30814" $Theme.dim 7.75 22 $true 192
$script:LblSideFooterStatus.Location = New-Object System.Drawing.Point(4, 1)
$script:LblSideFooterStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$sideStatusPill.Controls.Add($script:LblSideFooterStatus)
$sideFooter.Controls.Add($sideStatusPill)

$btnQuickFolder = New-Btn 'Open Folder' 'Open the K BNG M Hoster folder in Windows Explorer.' { Start-Process explorer.exe -ArgumentList ('"' + $script:AppDir + '"') }
$btnQuickFolder.Font = Get-CachedFont 'Segoe UI Semibold' 8.25 ([System.Drawing.FontStyle]::Regular)
$btnQuickFolder.Location = New-Object System.Drawing.Point(12, 42)
$btnQuickFolder.Size = New-Object System.Drawing.Size(96, 30)
$sideFooter.Controls.Add($btnQuickFolder)

$btnQuickGuide = New-Btn 'Guide (^G)' 'Open the built-in Guide & Walkthrough page. (Ctrl+G)' { Show-GuidePage }
$btnQuickGuide.Font = Get-CachedFont 'Segoe UI Semibold' 8.25 ([System.Drawing.FontStyle]::Regular)
$btnQuickGuide.Location = New-Object System.Drawing.Point(116, 42)
$btnQuickGuide.Size = New-Object System.Drawing.Size(96, 30)
$sideFooter.Controls.Add($btnQuickGuide)
$sidebar.Controls.Add($sideFooter)

$script:MoreMenu = New-Object System.Windows.Forms.ContextMenuStrip
$script:MoreMenu.BackColor = $Theme.card
$script:MoreMenu.ForeColor = $Theme.text
$script:MoreMenu.ShowImageMargin = $false
function Add-MenuItem([string]$Text, [string]$Tip, [scriptblock]$OnClick) {
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem
    $mi.Text = $Text
    $mi.ForeColor = $Theme.text
    $mi.BackColor = $Theme.card
    if ($Tip) { $mi.ToolTipText = $Tip }
    if ($OnClick) { $mi.Add_Click($OnClick) }
    $script:MoreMenu.Items.Add($mi)
    return $mi
}
Add-MenuItem 'Guide & Walkthrough (Ctrl+G)' 'How everything works, step by step - the whole README inside the app.' { Show-GuidePage } | Out-Null
Add-MenuItem 'Extra & Windows (Ctrl+E)' 'Open windows (restore them from here), and the one-click "Submit issue" button.' { Show-ExtraPage } | Out-Null
Add-MenuItem 'Support (Discord)' 'Get help with K BNG M Hoster on Discord.' {
    try { Start-Process "https://discord.gg/2Ckw5SgJvw" } catch { Add-Log '[INFO] Could not open Discord link. Please visit: https://discord.gg/2Ckw5SgJvw' }
} | Out-Null
Add-MenuItem 'Open Hoster Folder' 'Open the K BNG M Hoster folder in Explorer.' { Start-Process explorer.exe -ArgumentList ('"' + $script:AppDir + '"') } | Out-Null
$miClean = Add-MenuItem 'Clean Personal Info' 'Remove personal/runtime files (key, logs, webhook, IP files) so the folder is safe to zip and share.' { Run-CleanFlow }
$miClean.ForeColor = $Theme.red

function Show-MoreMenu {
    $script:MoreMenu.Show($script:BtnMore, (New-Object System.Drawing.Point(0, ($script:BtnMore.Height + 2))))
}

# ---------------- Status bar (3-Zone Telemetry Footer + Resize Grip) ----------------
$statusBar = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $statusBar
$statusBar.Dock = 'Bottom'
$statusBar.Height = 26
$statusBar.BackColor = $Theme.log
$statusBar.Add_Paint({
    param($s, $e)
    try {
        $e.Graphics.DrawLine((Get-CachedPen $Theme.border 1), 0, 0, $s.Width, 0)
    } catch { }
})
$resizeGrip = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $resizeGrip
$resizeGrip.Dock = 'Right'
$resizeGrip.Width = 18
$resizeGrip.BackColor = [System.Drawing.Color]::Transparent
$resizeGrip.Cursor = [System.Windows.Forms.Cursors]::SizeNWSE
$resizeGrip.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $script:Form.WindowState -eq 'Normal') {
        try {
            [Win32Chrome]::ReleaseCapture() | Out-Null
            [Win32Chrome]::SendMessage($script:Form.Handle, 0x00A1, [IntPtr]17, [IntPtr]0) | Out-Null
        } catch { }
    }
})
$resizeGrip.Add_Paint({
    param($s, $e)
    try {
        $pen = Get-CachedPen $Theme.dim 1
        $e.Graphics.DrawLine($pen, 6, 20, 14, 12)
        $e.Graphics.DrawLine($pen, 10, 20, 14, 16)
    } catch { }
})
$script:LblFooterState = New-Lbl "$([char]0x25CF) ENGINE STANDBY  $dot  Ready on Port 30814" $Theme.yellow 8 24 $true 310
$script:LblFooterState.Dock = 'Left'
$script:LblFooterState.AutoEllipsis = $true
$script:LblFooterState.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:LblFooterState.Padding = New-Object System.Windows.Forms.Padding(16, 0, 4, 0)

$script:LblPlayers = New-Lbl '' $Theme.green 8 24 $true
$script:LblPlayers.AutoSize = $true
$script:LblPlayers.Dock = 'Left'
$script:LblPlayers.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$script:LblPlayers.Padding = New-Object System.Windows.Forms.Padding(6, 5, 6, 0)

$script:LblShortcuts = New-Lbl "Ctrl+S Start  $dot  Ctrl+X Stop  $dot  Ctrl+C Copy IP  $dot  Ctrl+D Diagnose  $dot  F11 Fullscreen" $Theme.muted 8 24
$script:LblShortcuts.AutoSize = $false
$script:LblShortcuts.Dock = 'Fill'
$script:LblShortcuts.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$script:LblShortcuts.AutoEllipsis = $true
$script:LblShortcuts.Padding = New-Object System.Windows.Forms.Padding(4, 0, 10, 0)

$statusBar.Controls.Add($script:LblShortcuts)
$statusBar.Controls.Add($script:LblPlayers)
$statusBar.Controls.Add($script:LblFooterState)
$statusBar.Controls.Add($resizeGrip)

# ---------------- Log panel (console drawer above status bar) ----------------
$logPanel = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $logPanel
$logPanel.Dock = 'Bottom'
$logPanel.Height = 166
$logPanel.BackColor = $Theme.bg
$logHead = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $logHead
$logHead.Dock = 'Top'
$logHead.Height = 30
$logHead.BackColor = $Theme.bg
$logHead.Padding = New-Object System.Windows.Forms.Padding(16, 4, 16, 2)
$logHead.Add_Paint({
    param($s, $e)
    try {
        $e.Graphics.DrawLine((Get-CachedPen $Theme.border 1), 16, 0, ($s.Width - 16), 0)
    } catch { }
})
$logTitle = New-Lbl "ACTIVITY CONSOLE  $dot  Live session & diagnostic output" $Theme.dim 8.25 22 $true
$logTitle.AutoSize = $false
$logTitle.AutoEllipsis = $true
$logTitle.Dock = 'Fill'
$logTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$btnClearLog = New-Btn 'Clear' 'Clear the activity log (does not affect the server).' { $script:LogBox.Clear() }
$btnClearLog.Dock = 'Right'
$btnClearLog.Font = Get-CachedFont 'Segoe UI Semibold' 8 ([System.Drawing.FontStyle]::Regular)
$btnClearLog.Size = New-Object System.Drawing.Size(56, 22)
$logBtnSpacer = New-Object System.Windows.Forms.Panel
$logBtnSpacer.Dock = 'Right'
$logBtnSpacer.Width = 6
$btnCopyLog = New-Btn 'Copy Log' 'Copy the entire activity console output to clipboard.' {
    if ($script:LogBox.Text) {
        [System.Windows.Forms.Clipboard]::SetText($script:LogBox.Text)
        Add-Log '[OK] Activity console log copied to clipboard.'
    }
}
$btnCopyLog.Dock = 'Right'
$btnCopyLog.Font = Get-CachedFont 'Segoe UI Semibold' 8 ([System.Drawing.FontStyle]::Regular)
$btnCopyLog.Size = New-Object System.Drawing.Size(68, 22)
$logHead.Controls.Add($logTitle)
$logHead.Controls.Add($btnCopyLog)
$logHead.Controls.Add($logBtnSpacer)
$logHead.Controls.Add($btnClearLog)
$logInner = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $logInner
$logInner.Dock = 'Fill'
$logInner.Padding = New-Object System.Windows.Forms.Padding(16, 2, 16, 8)
$logFrame = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $logFrame
$logFrame.Dock = 'Fill'
$logFrame.BackColor = $Theme.log
$logFrame.Padding = New-Object System.Windows.Forms.Padding(14, 8, 4, 8)
$logFrame.Add_SizeChanged({ $this.Invalidate() })
$logFrame.Add_Paint({
    param($s, $e)
    try {
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $w = $s.Width - 1
        $h = $s.Height - 1
        if ($w -le 2 -or $h -le 2) { return }
        $path = Get-RoundedRectPath 0 0 $w $h 6
        try {
            $g.DrawPath((Get-CachedPen ([System.Drawing.Color]::FromArgb(38, 38, 48)) 1), $path)
        } finally { $path.Dispose() }
        $g.DrawLine((Get-CachedPen ([System.Drawing.Color]::FromArgb(55, 55, 68)) 1), 6, 0, ($w - 6), 0)
    } catch { }
})

# Slim Modern Dark Scrollbar (Eliminates stark-white Win32 scrollbar)
$logSb = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $logSb
$logSb.Width = 10
$logSb.Dock = [System.Windows.Forms.DockStyle]::Right
$logSb.BackColor = $Theme.log
$logSb.Cursor = [System.Windows.Forms.Cursors]::Hand

$logSbState = @{
    IsDragging = $false
    IsHovered = $false
    DragStartY = 0
    DragStartLine = 0
}
$logSb.Tag = $logSbState

$syncLogScroll = {
    if (-not $script:LogBox -or $script:LogBox.IsDisposed -or -not $logSb -or $logSb.IsDisposed) { return }
    $logSb.Invalidate()
}.GetNewClosure()
$script:SyncLogScroll = $syncLogScroll

$calcLogThumb = {
    param($sbW, $sbH)
    if (-not $script:LogBox -or $script:LogBox.IsDisposed -or $sbH -le 10) { return [System.Drawing.Rectangle]::Empty }
    $tot = [Win32Chrome]::SendMessage($script:LogBox.Handle, 0x00BA, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
    $lineH = [math]::Max(12, $script:LogBox.Font.Height)
    $vis = [int][math]::Max(1, ($script:LogBox.ClientSize.Height / $lineH))
    if ($tot -le $vis -or $tot -le 0) { return [System.Drawing.Rectangle]::Empty }
    $thumbH = [int][math]::Max(24, [math]::Min($sbH, ($vis / $tot * $sbH)))
    $availH = $sbH - $thumbH
    $first = [Win32Chrome]::SendMessage($script:LogBox.Handle, 0x00CE, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
    $maxS = [math]::Max(1, ($tot - $vis))
    $thumbY = if ($maxS -gt 0) { [int]([math]::Min(1.0, ($first / $maxS)) * $availH) } else { 0 }
    $thumbY = [int][math]::Max(0, [math]::Min($availH, $thumbY))
    return (New-Object System.Drawing.Rectangle(3, $thumbY, 4, $thumbH))
}.GetNewClosure()

$logSb.Add_Paint({
    param($s, $e)
    try {
        $tr = & $calcLogThumb $s.Width $s.Height
        if ($tr.IsEmpty -or $tr.Height -le 0) { return }
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $col = if ($s.Tag.IsDragging) {
            [System.Drawing.Color]::FromArgb(255, 115, 29)
        } elseif ($s.Tag.IsHovered) {
            [System.Drawing.Color]::FromArgb(113, 113, 122)
        } else {
            [System.Drawing.Color]::FromArgb(60, 60, 72)
        }
        $brush = Get-CachedBrush $col
        $path = Get-RoundedRectPath $tr.X $tr.Y $tr.Width $tr.Height 2
        try { $g.FillPath($brush, $path) } finally { $path.Dispose() }
    } catch { }
})

$logSb.Add_MouseEnter({ $this.Tag.IsHovered = $true; $this.Invalidate() })
$logSb.Add_MouseLeave({ $this.Tag.IsHovered = $false; $this.Invalidate() })
$logSb.Add_MouseDown({
    param($s, $e)
    try {
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $tr = & $calcLogThumb $s.Width $s.Height
            $tot = [Win32Chrome]::SendMessage($script:LogBox.Handle, 0x00BA, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
            $lineH = [math]::Max(12, $script:LogBox.Font.Height)
            $vis = [int][math]::Max(1, ($script:LogBox.ClientSize.Height / $lineH))
            if ($tr.Height -gt 0 -and $e.Y -ge ($tr.Top - 4) -and $e.Y -le ($tr.Bottom + 4)) {
                $s.Tag.IsDragging = $true
                $s.Tag.DragStartY = $e.Y
                $s.Tag.DragStartLine = [Win32Chrome]::SendMessage($script:LogBox.Handle, 0x00CE, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
                $s.Capture = $true
            } else {
                $cur = [Win32Chrome]::SendMessage($script:LogBox.Handle, 0x00CE, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
                $step = if ($tr.Height -gt 0 -and $e.Y -lt $tr.Top) { -$vis } else { $vis }
                [Win32Chrome]::SendMessage($script:LogBox.Handle, 0x00B6, [IntPtr]::Zero, [IntPtr]$step) | Out-Null
                $s.Invalidate()
            }
        }
    } catch { }
})
$logSb.Add_MouseMove({
    param($s, $e)
    try {
        if ($s.Tag.IsDragging -and $e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $tot = [Win32Chrome]::SendMessage($script:LogBox.Handle, 0x00BA, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
            $lineH = [math]::Max(12, $script:LogBox.Font.Height)
            $vis = [int][math]::Max(1, ($script:LogBox.ClientSize.Height / $lineH))
            $maxS = [math]::Max(1, ($tot - $vis))
            $availH = [math]::Max(1, ($s.Height - 24))
            $dY = $e.Y - $s.Tag.DragStartY
            $dLine = [int](($dY / $availH) * $maxS)
            $targetLine = [int][math]::Max(0, [math]::Min($maxS, ($s.Tag.DragStartLine + $dLine)))
            $cur = [Win32Chrome]::SendMessage($script:LogBox.Handle, 0x00CE, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
            $diff = $targetLine - $cur
            if ($diff -ne 0) {
                [Win32Chrome]::SendMessage($script:LogBox.Handle, 0x00B6, [IntPtr]::Zero, [IntPtr]$diff) | Out-Null
                $s.Invalidate()
            }
        }
    } catch { }
})
$logSb.Add_MouseUp({
    param($s, $e)
    $s.Tag.IsDragging = $false
    $s.Capture = $false
    $s.Invalidate()
})

$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.ReadOnly = $true
$script:LogBox.BackColor = $Theme.log
$script:LogBox.ForeColor = $Theme.textSec
$script:LogBox.BorderStyle = 'None'
$script:LogBox.Font = Get-CachedFont $script:MonoFontName 9 ([System.Drawing.FontStyle]::Regular)
$script:LogBox.WordWrap = $false
$script:LogBox.ScrollBars = 'None'
$script:LogBox.Dock = 'Fill'
$script:LogBox.Add_MouseWheel({
    param($s, $e)
    try {
        $lines = if ($e.Delta -gt 0) { -3 } else { 3 }
        [Win32Chrome]::SendMessage($s.Handle, 0x00B6, [IntPtr]::Zero, [IntPtr]$lines) | Out-Null
        if ($script:SyncLogScroll) { & $script:SyncLogScroll }
    } catch { }
})
$logFrame.Controls.Add($script:LogBox)
$logFrame.Controls.Add($logSb)
$logInner.Controls.Add($logFrame)
$logPanel.Controls.Add($logInner)
$logPanel.Controls.Add($logHead)

# ---------------- Content area (docking order: Content -> logPanel -> statusBar -> sidebar -> titleBar) --------
$script:Content = New-Object System.Windows.Forms.Panel
Enable-DoubleBuffer $script:Content
$script:Content.Dock = 'Fill'
$script:Content.BackColor = $Theme.bg

# Fast page transition helper: suspends layout on $script:Content and caches
# created page panels so switching between tabs is instantaneous without HWND churn.
$script:HomePagePanel = $null
$script:SettingsPagePanel = $null
$script:ModsPagePanel = $null
$script:NetworkPagePanel = $null
$script:TransferPagePanel = $null
$script:FixPagePanel = $null
$script:GuidePagePanel = $null
$script:ExtraPagePanel = $null

$script:SettingsStackRefs = $null
$script:NetworkStackRefs = $null
$script:TransferStackRefs = $null
$script:ExtraStackRefs = $null

function Switch-ContentPage($NewPage) {
    if (-not $NewPage) { return }
    $script:Content.SuspendLayout()
    try {
        foreach ($c in @($script:Content.Controls)) {
            if ($c -ne $NewPage -and $c.Visible) {
                $c.Visible = $false
            }
        }
        if (-not $script:Content.Controls.Contains($NewPage)) {
            $script:Content.Controls.Add($NewPage)
        }
        $NewPage.Visible = $true
        $NewPage.BringToFront()
    } finally {
        $script:Content.ResumeLayout($true)
    }
    if ($script:PageLayout) {
        try { & $script:PageLayout } catch { }
    }
}

$script:Form.Controls.Add($script:Content)
$script:Form.Controls.Add($logPanel)
$script:Form.Controls.Add($statusBar)
$script:Form.Controls.Add($sidebar)
$script:Form.Controls.Add($titleBar)

$script:LayoutPending = $false
$script:DoRelayout = {
    $script:LayoutPending = $false
    if ($script:PageLayout) { & $script:PageLayout }
}
$script:Form.Add_Resize({
    try {
        if ($script:BtnWinMax) { $script:BtnWinMax.Invalidate() }
        if (-not $script:LayoutPending) {
            $script:LayoutPending = $true
            [void]$script:Form.BeginInvoke([System.Windows.Forms.MethodInvoker]$script:DoRelayout)
        }
    } catch { Write-Log "[LAYOUT-ERROR] $($_.Exception.Message)" }
})

# ---------------------------------------------------------------------------------------
# HOME PAGE (Command Center Dashboard: Hero Status Card + KPI Chips + Endpoint Rows)
# ---------------------------------------------------------------------------------------
function Layout-HomePage {
    if (-not $script:HomePagePanel -or $script:HomePagePanel.IsDisposed) { return }
    try {
        $hpPadH = if ($script:HomePagePanel -and $script:HomePagePanel.Padding) {
            ($script:HomePagePanel.Padding.Left + $script:HomePagePanel.Padding.Right)
        } else { 32 }
        $cardW = if ($script:HomePagePanel -and $script:HomePagePanel.ClientSize.Width -gt 200) {
            ($script:HomePagePanel.ClientSize.Width - $hpPadH)
        } elseif ($script:Content -and $script:Content.ClientSize.Width -gt 200) {
            ($script:Content.ClientSize.Width - 32)
        } elseif ($script:Form -and $script:Form.ClientSize.Width -gt 200) {
            ($script:Form.ClientSize.Width - 224 - 32)
        } else {
            844
        }
        $cardW = [int][math]::Max(320, $cardW)

        if ($script:StatusCard -and $script:StatusTlp) {
            $stPadH = $script:StatusCard.Padding.Left + $script:StatusCard.Padding.Right
            $stPadV = $script:StatusCard.Padding.Top + $script:StatusCard.Padding.Bottom
            $stInnerW = [int][math]::Max(260, ($cardW - $stPadH))
            if ($script:LblStatusHint) { $script:LblStatusHint.MaximumSize = New-Object System.Drawing.Size($stInnerW, 0) }
            if ($script:LblCgnatBadge) { $script:LblCgnatBadge.MaximumSize = New-Object System.Drawing.Size($stInnerW, 0) }
            $script:StatusTlp.Location = New-Object System.Drawing.Point($script:StatusCard.Padding.Left, $script:StatusCard.Padding.Top)
            $script:StatusTlp.Width = $stInnerW
            $script:StatusTlp.PerformLayout()
            $stPrefH = $script:StatusTlp.GetPreferredSize((New-Object System.Drawing.Size($stInnerW, 0))).Height
            $wantStH = [int]($stPrefH + $stPadV + 2)
            if ($script:StatusCard.Height -ne $wantStH) { $script:StatusCard.Height = $wantStH }
        }
        if ($script:ConnCard -and $script:ConnContent -and $script:ConnTlp) {
            $vBarW = [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth
            if ($vBarW -lt 16) { $vBarW = 18 }
            $availW = if ($script:ConnCard.ClientSize.Width -gt 50) {
                $script:ConnCard.ClientSize.Width
            } else {
                $cardW
            }
            # Initial probe for width:
            $connW = [int][math]::Max(280, ($availW - 1))
            $connPadH = $script:ConnContent.Padding.Left + $script:ConnContent.Padding.Right
            $connPadV = $script:ConnContent.Padding.Top + $script:ConnContent.Padding.Bottom
            $connInnerW = [int][math]::Max(240, ($connW - $connPadH))
            if ($script:LblConnNote -and $script:ConnNoteBox) {
                $noteInnerW = [int][math]::Max(180, ($connInnerW - 54))
                $script:LblConnNote.MaximumSize = New-Object System.Drawing.Size($noteInnerW, 0)
                $script:ConnNoteBox.Width = $connInnerW
                $script:ConnNoteBox.Height = [int][math]::Max(38, ($script:LblConnNote.PreferredSize.Height + 18))
            }
            if ($script:ConnVpnFlow) {
                $script:ConnVpnFlow.MaximumSize = New-Object System.Drawing.Size($connInnerW, 0)
                $script:ConnVpnFlow.MinimumSize = New-Object System.Drawing.Size($connInnerW, 36)
            }
            $script:ConnTlp.Location = New-Object System.Drawing.Point($script:ConnContent.Padding.Left, $script:ConnContent.Padding.Top)
            $script:ConnTlp.Width = $connInnerW
            $script:ConnTlp.PerformLayout()
            $connPrefH = $script:ConnTlp.GetPreferredSize((New-Object System.Drawing.Size($connInnerW, 0))).Height
            $connH = [int]($connPrefH + $connPadV + 4)

            $curScrollY = if ($script:HomeScrollBar) { & $script:HomeScrollBar.GetScrollY } else { 0 }
            $script:ConnContent.Size = New-Object System.Drawing.Size($connW, $connH)
            $script:ConnContent.Location = New-Object System.Drawing.Point(0, -$curScrollY)
            if ($script:HomeScrollBar) { & $script:HomeScrollBar.Sync }
        }
    } catch { Write-Log "[LAYOUT-ERROR] HOME $($_.Exception.Message)" }
}

function Show-HomePage {
    Set-ActiveNav $script:BtnHome
    $script:PageLayout = { Layout-HomePage }
    if ($script:HomePagePanel -and -not $script:HomePagePanel.IsDisposed) {
        Switch-ContentPage $script:HomePagePanel
        Refresh-Dashboard
        Layout-HomePage
        return
    }
    $p = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $p
    $p.SuspendLayout()
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg
    $p.Padding = New-Object System.Windows.Forms.Padding(16, 12, 16, 6)    # Hero Status Header (top) with Quick Action Bar + Full-Width KPI Metric Grid (Edgeless - Zero Outer Border)
    $script:StatusCard = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $script:StatusCard
    $script:StatusCard.Dock = 'Top'
    $script:StatusCard.AutoSize = $false
    $script:StatusCard.Height = 138
    $script:StatusCard.BackColor = $Theme.bg
    $script:StatusCard.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 8)
    $script:StatusCard.Add_SizeChanged({ $this.Invalidate() })
    $stTlp = New-Object System.Windows.Forms.TableLayoutPanel
    Enable-DoubleBuffer $stTlp
    $stTlp.SuspendLayout()
    $stTlp.Location = New-Object System.Drawing.Point(0, 4)
    $stTlp.AutoSize = $true
    $stTlp.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $stTlp.ColumnCount = 2
    $null = $stTlp.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $null = $stTlp.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $script:StatusTlp = $stTlp
    $script:StatusCard.Controls.Add($stTlp)

    $script:LblStatusBig = New-Lbl "$([char]0x25CF)  SERVER STANDBY" $Theme.yellow 13 28 $true
    $script:LblStatusBig.AutoSize = $true
    $script:LblStatusBig.Anchor = 'Left'
    $script:LblStatusBig.Margin = New-Object System.Windows.Forms.Padding(0, 0, 14, 0)
    $script:LblStatusBig.Font = Get-CachedFont 'Segoe UI Semibold' 13 ([System.Drawing.FontStyle]::Bold)
    $r = $stTlp.RowCount; $stTlp.RowCount = $r + 1
    $null = $stTlp.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $stTlp.Controls.Add($script:LblStatusBig, 0, $r)

    $btnBar = New-Object System.Windows.Forms.FlowLayoutPanel
    Enable-DoubleBuffer $btnBar
    $btnBar.AutoSize = $true
    $btnBar.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $btnBar.WrapContents = $false
    $btnBar.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
    $btnBar.Anchor = 'Right'
    $btnBar.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)
    $btnBar.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)
    $script:BtnCopy = New-Btn 'Copy Best IP' 'Copy the best address for your friends to the clipboard (FRP > LAN > VPN > Tailscale > internet). (Ctrl+C)' { Copy-ConnectionLine }
    $script:BtnCopy.Size = New-Object System.Drawing.Size(110, 30)
    $script:BtnCopy.Margin = New-Object System.Windows.Forms.Padding(5, 0, 0, 0)
    $script:BtnInvite = New-Btn 'Copy Invite' 'Copy a ready-made invite message (address + how to connect) to paste to your friends. Perfect for a private server.' { Copy-Invite }
    $script:BtnInvite.Size = New-Object System.Drawing.Size(106, 30)
    $script:BtnInvite.Margin = New-Object System.Windows.Forms.Padding(5, 0, 0, 0)
    $script:BtnDiag = New-Btn 'Diagnose' 'Run a full live diagnosis and show a plain-language report of any problem. (Ctrl+D)' { Run-Diagnose }
    $script:BtnDiag.Size = New-Object System.Drawing.Size(86, 30)
    $script:BtnDiag.Margin = New-Object System.Windows.Forms.Padding(5, 0, 0, 0)
    $script:BtnRefreshHome = New-Btn 'Refresh' 'Re-check every address and the server status right now. (The page also refreshes by itself every few seconds while the server runs.)' { Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.Conn = Get-ConnectionInfo`nSay ""Addresses refreshed."" " 'live' }
    $script:BtnRefreshHome.Size = New-Object System.Drawing.Size(80, 30)
    $script:BtnRefreshHome.Margin = New-Object System.Windows.Forms.Padding(5, 0, 0, 0)
    $btnBar.Controls.Add($script:BtnCopy)
    $btnBar.Controls.Add($script:BtnInvite)
    $btnBar.Controls.Add($script:BtnDiag)
    $btnBar.Controls.Add($script:BtnRefreshHome)
    $stTlp.Controls.Add($btnBar, 1, $r)

    # Full-Width 4-Column KPI Metric Grid (SERVER | PORT | VISIBILITY | GATEWAY) - Pure Space & Typography (No Boxes)
    $kpiGrid = New-Object System.Windows.Forms.TableLayoutPanel
    Enable-DoubleBuffer $kpiGrid
    $kpiGrid.SuspendLayout()
    $kpiGrid.Anchor = 'Left,Right'
    $kpiGrid.Height = 50
    $kpiGrid.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 4)
    $kpiGrid.ColumnCount = 4
    $kpiGrid.RowCount = 1
    $null = $kpiGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 23)))
    $null = $kpiGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 20)))
    $null = $kpiGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 26)))
    $null = $kpiGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 31)))
    $null = $kpiGrid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

    function New-KpiChip([int]$ColIdx, [string]$Caption, [string]$VarName, [bool]$IsLast = $false) {
        $chip = New-Object System.Windows.Forms.Panel
        Enable-DoubleBuffer $chip
        $chip.Size = New-Object System.Drawing.Size(200, 50)
        $chip.Dock = 'Fill'
        $chip.BackColor = [System.Drawing.Color]::Transparent
        $rightPad = if ($IsLast) { 0 } else { 12 }
        $chip.Margin = New-Object System.Windows.Forms.Padding(0, 0, $rightPad, 0)
        $chip.Padding = New-Object System.Windows.Forms.Padding(0, 2, 4, 2)
        $chip.Add_SizeChanged({ $this.Invalidate() })
        # Edgeless design: zero borders, pure margin/padding and high-contrast typography
        $lCap = New-Lbl $Caption ([System.Drawing.Color]::FromArgb(140, 140, 154)) 7.5 14 $true
        $lCap.AutoSize = $false
        $lCap.Location = New-Object System.Drawing.Point(0, 4)
        $lCap.Size = New-Object System.Drawing.Size(190, 14)
        $lCap.Anchor = 'Top,Left,Right'
        $lCap.AutoEllipsis = $true
        $lVal = New-Lbl '-' ([System.Drawing.Color]::FromArgb(244, 244, 248)) 10 22 $true
        $lVal.AutoSize = $false
        $lVal.Location = New-Object System.Drawing.Point(0, 20)
        $lVal.Size = New-Object System.Drawing.Size(190, 22)
        $lVal.Anchor = 'Top,Left,Right'
        $lVal.AutoEllipsis = $true
        $chip.Controls.Add($lCap)
        $chip.Controls.Add($lVal)
        $kpiGrid.Controls.Add($chip, $ColIdx, 0)
        Set-Variable -Name $VarName -Value $lVal -Scope Script
    }
    New-KpiChip 0 'SERVER NAME'    'LblKpiServer' $false
    New-KpiChip 1 'PORT (UDP/TCP)' 'LblKpiPort'   $false
    New-KpiChip 2 'VISIBILITY'     'LblKpiVis'    $false
    New-KpiChip 3 'GATEWAY STATUS' 'LblKpiGate'   $true
    $kpiGrid.ResumeLayout($false)
    $script:LblServerMeta = New-Lbl '' ([System.Drawing.Color]::White) 1 1 $false
    $script:LblServerMeta.Visible = $false

    $r = $stTlp.RowCount; $stTlp.RowCount = $r + 1
    $null = $stTlp.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $stTlp.Controls.Add($kpiGrid, 0, $r); $stTlp.SetColumnSpan($kpiGrid, 2)

    $script:LblStatusHint = New-Lbl 'Press Start Server (or Ctrl+S). Everything is automatic: key check, safety scan, firewall, port, then it opens the BeamMP Launcher.' $Theme.dim 8.75 18
    $script:LblStatusHint.Anchor = 'Left'
    $script:LblStatusHint.AutoSize = $true
    $script:LblStatusHint.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
    $r = $stTlp.RowCount; $stTlp.RowCount = $r + 1
    $null = $stTlp.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $stTlp.Controls.Add($script:LblStatusHint, 0, $r); $stTlp.SetColumnSpan($script:LblStatusHint, 2)

    $script:LblCgnatBadge = New-Lbl '' $Theme.yellow 8.75 18
    $script:LblCgnatBadge.Anchor = 'Left'
    $script:LblCgnatBadge.AutoSize = $true
    $script:LblCgnatBadge.Visible = $false
    $script:LblCgnatBadge.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    $r = $stTlp.RowCount; $stTlp.RowCount = $r + 1
    $null = $stTlp.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $stTlp.Controls.Add($script:LblCgnatBadge, 0, $r); $stTlp.SetColumnSpan($script:LblCgnatBadge, 2)
    $stTlp.ResumeLayout($false)

    $homeSpacer = New-Object System.Windows.Forms.Panel
    $homeSpacer.Dock = 'Top'
    $homeSpacer.Height = 10
    $homeSpacer.BackColor = $Theme.bg

    # Connect info card wrapper
    $connWrap = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $connWrap
    $connWrap.Dock = 'Fill'
    $connWrap.BackColor = $Theme.bg

    # Connect info card (fills the rest, scrolls cleanly if needed)
    $script:ConnCard = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $script:ConnCard
    $script:ConnCard.Dock = 'Fill'
    $script:ConnCard.BackColor = $Theme.bg
    $script:ConnCard.AutoScroll = $false
    $script:ConnContent = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $script:ConnContent
    $script:ConnContent.Location = New-Object System.Drawing.Point(0, 0)
    $script:ConnContent.AutoSize = $false
    $script:ConnContent.BackColor = $Theme.bg
    $script:ConnContent.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 10)
    $script:ConnContent.Add_SizeChanged({ $this.Invalidate() })
    # Outer bounding box completely destroyed! Edgeless layout relying purely on space!
    $script:ConnCard.Controls.Add($script:ConnContent)
    $script:ConnCard.Add_Resize({ Layout-HomePage })

    $script:HomeScrollBar = Attach-ModernScrollBar $connWrap $script:ConnCard $script:ConnContent { if ($script:ConnContent) { $script:ConnContent.Height } else { 0 } }
    $connWrap.Controls.Add($script:ConnCard)
    $script:ConnCard.BringToFront()

    $connTlp = New-Object System.Windows.Forms.TableLayoutPanel
    Enable-DoubleBuffer $connTlp
    $connTlp.SuspendLayout()
    $connTlp.Location = New-Object System.Drawing.Point(0, 6)
    $connTlp.AutoSize = $true
    $connTlp.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $connTlp.ColumnCount = 1
    $null = $connTlp.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $script:ConnTlp = $connTlp
    $script:ConnContent.Controls.Add($connTlp)

    $connTitle = New-Lbl "Direct Connect Endpoints   $dot   BeamNG $([char]0x2192) Multiplayer $([char]0x2192) Direct Connect" $Theme.text 10.5 22 $true
    $connTitle.Font = Get-CachedFont 'Segoe UI Semibold' 10.5 ([System.Drawing.FontStyle]::Bold)
    $connTitle.AutoSize = $true
    $connTitle.Anchor = 'Left'
    $connTitle.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $r = $connTlp.RowCount; $connTlp.RowCount = $r + 1
    $null = $connTlp.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $connTlp.Controls.Add($connTitle, 0, $r)

    function Add-EndpointRow([string]$TitleText, [string]$TipText, [string]$VarName, [string]$RowVarName, [string]$BtnVarName, [System.Drawing.Color]$Color, [bool]$Bold = $false) {
        $rowP = New-Object System.Windows.Forms.TableLayoutPanel
        Enable-DoubleBuffer $rowP
        $rowP.SuspendLayout()
        $rowP.Anchor = 'Left,Right'
        $rowP.Height = 36
        $rowP.BackColor = [System.Drawing.Color]::Transparent
        $rowP.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)
        $rowP.Padding = New-Object System.Windows.Forms.Padding(6, 2, 4, 2)
        $rowP.ColumnCount = 3
        $null = $rowP.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 184)))
        $null = $rowP.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $null = $rowP.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 98)))
        $rowP.RowCount = 1
        $null = $rowP.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
        $rowP.Add_MouseEnter({ $this.BackColor = [System.Drawing.Color]::FromArgb(18, 255, 255, 255); $this.Invalidate() })
        $rowP.Add_MouseLeave({ $this.BackColor = [System.Drawing.Color]::Transparent; $this.Invalidate() })
        $rowP.Add_Paint({
            param($s, $e)
            try {
                $g = $e.Graphics
                # Ultra-thin, low-opacity internal divider (rgba(255, 255, 255, 0.05)) - the only lines allowed
                $divPen = Get-CachedPen ([System.Drawing.Color]::FromArgb(13, 255, 255, 255)) 1
                $g.DrawLine($divPen, 6, ($s.Height - 1), ($s.Width - 6), ($s.Height - 1))
            } catch { }
        })

        $lTitle = New-Lbl $TitleText ([System.Drawing.Color]::FromArgb(168, 168, 180)) 8.25 28 $true
        $lTitle.AutoSize = $false
        $lTitle.AutoEllipsis = $true
        $lTitle.Dock = 'Fill'
        $lTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        if ($TipText) { $script:Tip.SetToolTip($lTitle, $TipText) }
        $rowP.Controls.Add($lTitle, 0, 0)

        $lbl = New-Lbl '' $Color 9 28 $Bold
        $lbl.AutoSize = $false
        $lbl.Dock = 'Fill'
        $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $lbl.AutoEllipsis = $true
        if ($Bold) {
            $lbl.Font = Get-CachedFont $script:MonoFontName 9.25 ([System.Drawing.FontStyle]::Bold)
        } else {
            $lbl.Font = Get-CachedFont $script:MonoFontName 9 ([System.Drawing.FontStyle]::Regular)
        }
        if ($TipText) { $script:Tip.SetToolTip($lbl, $TipText) }
        $rowP.Controls.Add($lbl, 1, 0)

        $actBtn = New-Btn 'Copy IP' 'Copy this endpoint address or open its setup tool.' {
            param($s, $e)
            $val = [string]$s.Tag
            if ($val -eq '__NETWORK__') {
                Show-NetworkPage
            } elseif ($val -eq '__FIX__') {
                Show-FixPage
            } elseif ($val -eq '__REFRESH__') {
                Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.Conn = Get-ConnectionInfo`nSay ""Addresses refreshed."" " 'live'
            } elseif ($val -eq '__STREAMER_BLOCKED__') {
                Add-Log "[NOTE] Clipboard copy blocked: Sensitive endpoint is masked while Streamer Privacy Mode is active."
            } elseif ($val) {
                [System.Windows.Forms.Clipboard]::SetText($val)
                Add-Log "[OK] Copied endpoint to clipboard: $val"
            }
        }
        $actBtn.Font = Get-CachedFont 'Segoe UI Semibold' 8 ([System.Drawing.FontStyle]::Regular)
        $actBtn.Size = New-Object System.Drawing.Size(90, 28)
        $actBtn.Anchor = 'Right'
        $rowP.Controls.Add($actBtn, 2, 0)
        $rowP.ResumeLayout($false)

        $r = $connTlp.RowCount; $connTlp.RowCount = $r + 1
        $null = $connTlp.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
        $connTlp.Controls.Add($rowP, 0, $r)
        Set-Variable -Name $VarName -Value $lbl -Scope Script
        Set-Variable -Name $RowVarName -Value $rowP -Scope Script
        Set-Variable -Name $BtnVarName -Value $actBtn -Scope Script
    }

    Add-EndpointRow "YOU  $dot  HOST PC"        'Use this loopback address in BeamNG on THIS computer to join your own server.'            'LblConnThis'   'RowConnThis'   'BtnConnThis'   $Theme.text  $false
    Add-EndpointRow 'HOME WIFI / LAN'          'Share this address with players connected to the same home WiFi or router.'              'LblConnLan'    'RowConnLan'    'BtnConnLan'    $Theme.text  $false
    Add-EndpointRow 'PUBLIC TUNNEL'            'Shareable tunnel address (FRP or Playit.gg) - friends can join without port forwarding.' 'LblConnTunnel' 'RowConnTunnel' 'BtnConnTunnel' $Theme.blue  $true
    Add-EndpointRow 'VIRTUAL LAN (VPN)'        'For friends connected to the same Radmin VPN, ZeroTier, or Hamachi network.'             'LblConnVpn'    'RowConnVpn'    'BtnConnVpn'    $Theme.green $false
    Add-EndpointRow 'TAILSCALE MESH'           'For friends connected to your Tailscale mesh network.'                                   'LblConnTail'   'RowConnTail'   'BtnConnTail'   $Theme.blue  $false
    Add-EndpointRow 'INTERNET (PUBLIC WAN)'    'Your direct public internet IP (requires router UPnP or manual port forwarding).'        'LblConnPub'    'RowConnPub'    'BtnConnPub'    $Theme.dim   $false
    Add-EndpointRow 'ROUTER PORT (UPNP)'       'Automatic router port forwarding status for direct internet connections.'                'LblConnRouter' 'RowConnRouter' 'BtnConnRouter' $Theme.dim   $false

    # Styled Modern Semantic Callout Banner (Solid #291f00 dark amber fill, 10px rounded corners, ZERO border)
    $noteBox = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $noteBox
    $noteBox.Anchor = 'Left,Right'
    $noteBox.AutoSize = $false
    $noteBox.Height = 38
    $noteBox.BackColor = [System.Drawing.Color]::Transparent
    $noteBox.Padding = New-Object System.Windows.Forms.Padding(14, 8, 14, 8)
    $noteBox.Margin = New-Object System.Windows.Forms.Padding(0, 10, 0, 6)
    $noteBox.Add_SizeChanged({ $this.Invalidate() })
    $noteBox.Add_Paint({
        param($s, $e)
        try {
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $w = $s.Width - 1
            $h = $s.Height - 1
            if ($w -le 4 -or $h -le 4) { return }
            # Corner radius 10px, solid #291f00 dark amber background fill, ZERO border!
            $path = Get-RoundedRectPath 0 0 $w $h 10
            try {
                $fillBrush = Get-CachedBrush ([System.Drawing.Color]::FromArgb(41, 31, 0))
                $g.FillPath($fillBrush, $path)
                # ZERO BORDER! Do NOT call DrawPath!
            } finally { $path.Dispose() }

            # Subtle inline info indicator glyph (borderless soft amber circle)
            $badgeX = 12
            $badgeY = [int](($s.Height - 18) / 2)
            $badgePath = Get-RoundedRectPath $badgeX $badgeY 18 18 9
            try {
                $g.FillPath((Get-CachedBrush ([System.Drawing.Color]::FromArgb(68, 52, 6))), $badgePath)
            } finally { $badgePath.Dispose() }
            $fBadge = Get-CachedFont 'Segoe UI' 7.5 ([System.Drawing.FontStyle]::Bold)
            $rBadge = New-Object System.Drawing.Rectangle($badgeX, $badgeY, 18, 18)
            [System.Windows.Forms.TextRenderer]::DrawText($g, 'i', $fBadge, $rBadge, [System.Drawing.Color]::FromArgb(251, 191, 36), ([System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter))
        } catch { }
    })
    $script:ConnNoteBox = $noteBox
    $script:LblConnNote = New-Lbl '' ([System.Drawing.Color]::FromArgb(254, 215, 170)) 8.5 18 $false
    $script:LblConnNote.Location = New-Object System.Drawing.Point(40, 9)
    $script:LblConnNote.AutoSize = $true
    $noteBox.Controls.Add($script:LblConnNote)
    $r = $connTlp.RowCount; $connTlp.RowCount = $r + 1
    $null = $connTlp.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $connTlp.Controls.Add($noteBox, 0, $r)

    $script:ConnVpnFlow = New-ButtonBar
    $script:ConnVpnFlow.AutoSize = $true
    $script:ConnVpnFlow.WrapContents = $true
    $r = $connTlp.RowCount; $connTlp.RowCount = $r + 1
    $null = $connTlp.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $connTlp.Controls.Add($script:ConnVpnFlow, 0, $r)
    $connTlp.ResumeLayout($false)

    $p.Controls.Add($connWrap)
    $p.Controls.Add($homeSpacer)
    $p.Controls.Add($script:StatusCard)
    $p.ResumeLayout($true)
    $script:HomePagePanel = $p
    $p.Add_Resize({ Layout-HomePage })
    Switch-ContentPage $p
    Refresh-Dashboard
    Layout-HomePage
}

function Set-RowBtn($Btn, [string]$Text, [string]$TagVal) {
    if (-not $Btn) { return }
    $Btn.Tag = $TagVal
    if ($Btn.Text -ne $Text) {
        $Btn.Text = $Text
    }
    if ($TagVal -eq '__STREAMER_BLOCKED__') {
        $Btn.ForeColor = $Theme.dim
        $Btn.FlatAppearance.BorderColor = $Theme.border
    } else {
        $Btn.ForeColor = $Theme.text
        $Btn.FlatAppearance.BorderColor = $Theme.btnBorder
    }
    $Btn.Invalidate()
    if (-not $Btn.Visible) { $Btn.Visible = $true }
}

function Refresh-Dashboard {
    if (-not $script:LblStatusBig) { return }
    $conn = $script:State.Conn
    $running = [bool]$script:State.Running
    $port = if ($script:State -and $script:State.Port -and $script:State.Port -gt 0) {
        $script:State.Port
    } elseif ($conn -and $conn.Port -and $conn.Port -gt 0) {
        $conn.Port
    } else {
        $curPort = (Get-ServerPort)
        if ($script:State) { $script:State.Port = $curPort }
        $curPort
    }
    if ($script:State -and $script:State.Conn -and $port) {
        $script:State.Conn.Port = $port
    }
    $name = if ($script:State.ServerName) { $script:State.ServerName } else { 'K BNG M Server' }
    $isPrivate = Get-ServerPrivate
    $layoutChanged = $false

    $bul = [char]0x25CF
    $hol = [char]0x25CB
    $dot = [char]0x00B7
    $em  = [char]0x2014
    $arr = [char]0x2192

    if ($running) {
        $changed = Set-CtrlText $script:LblStatusBig "$bul  SERVER ONLINE" $Theme.green
    } elseif ($script:Starting) {
        $changed = Set-CtrlText $script:LblStatusBig "$bul  STARTING SERVER..." $Theme.blue
    } elseif ($script:State.FrpError) {
        $changed = Set-CtrlText $script:LblStatusBig "$bul  SERVER STOPPED" $Theme.red
    } else {
        $changed = Set-CtrlText $script:LblStatusBig "$bul  SERVER STANDBY" $Theme.yellow
    }
    if ($changed -and $script:StatusCard) { $script:StatusCard.Invalidate() }
    [void](Set-CtrlText $script:LblServerMeta "Server: $name   $dot   Port: $port")

    # Context-aware primary CTA styling on Copy Best IP
    if ($script:BtnCopy) {
        $wantBg = if ($running) { [System.Drawing.Color]::FromArgb(48, 26, 14) } else { $Theme.btn }
        $wantBorder = if ($running) { [System.Drawing.Color]::FromArgb(140, 255, 115, 29) } else { $Theme.btnBorder }
        if ($script:BtnCopy.BackColor.ToArgb() -ne $wantBg.ToArgb() -or $script:BtnCopy.FlatAppearance.BorderColor.ToArgb() -ne $wantBorder.ToArgb()) {
            $script:BtnCopy.BackColor = $wantBg
            $script:BtnCopy.FlatAppearance.BorderColor = $wantBorder
            $script:BtnCopy.ForeColor = if ($running) { [System.Drawing.Color]::White } else { $Theme.text }
            $script:BtnCopy.Invalidate()
        }
    }

    # Update KPI Chips
    if ($script:LblKpiServer) { [void](Set-CtrlText $script:LblKpiServer $name) }
    if ($script:LblKpiPort)   { [void](Set-CtrlText $script:LblKpiPort "$port") }
    if ($script:LblKpiVis) {
        $visText = if ($isPrivate) { 'Private (Invite Only)' } else { 'Public Server List' }
        $visCol  = if ($isPrivate) { $Theme.yellow } else { $Theme.green }
        [void](Set-CtrlText $script:LblKpiVis $visText $visCol)
    }
    $cgnat = if ($conn) { [bool]$conn.Cgnat } else { $false }
    if ($script:LblKpiGate) {
        if ($running -and $script:State.Frp) {
            [void](Set-CtrlText $script:LblKpiGate 'FRP Tunnel Active' $Theme.blue)
        } elseif ($running -and $script:State.UpnpOk) {
            [void](Set-CtrlText $script:LblKpiGate 'UPnP Port Forwarded' $Theme.green)
        } elseif ($cgnat) {
            [void](Set-CtrlText $script:LblKpiGate 'CGNAT (Use Tunnel/VPN)' $Theme.yellow)
        } elseif ($running) {
            [void](Set-CtrlText $script:LblKpiGate 'LAN / Direct Mode' $Theme.text)
        } else {
            [void](Set-CtrlText $script:LblKpiGate 'Ready (Auto on Start)' $Theme.textSec)
        }
    }
    if ($script:LblSideFooterStatus) {
        $stWord = if ($running) { "$bul ONLINE" } else { "$bul STANDBY" }
        $stCol  = if ($running) { $Theme.green } else { $Theme.textSec }
        [void](Set-CtrlText $script:LblSideFooterStatus "$stWord  $dot  Port $port  $dot  $(if ($isPrivate) { 'Private' } else { 'Public' })" $stCol)
    }
    if ($script:LblFooterState) {
        if ($running) {
            [void](Set-CtrlText $script:LblFooterState "$bul ENGINE ONLINE  $dot  Live on Port $port" $Theme.green)
        } elseif ($script:Starting) {
            [void](Set-CtrlText $script:LblFooterState "$bul STARTING ENGINE  $dot  Pre-flight checks..." $Theme.blue)
        } else {
            [void](Set-CtrlText $script:LblFooterState "$bul ENGINE STANDBY  $dot  Ready on Port $port" $Theme.yellow)
        }
    }

    if ($running) {
        $hintChanged = Set-CtrlText $script:LblStatusHint 'Server is online! Open BeamNG via BeamMP Launcher and Direct Connect using one of the endpoints below.' $Theme.green
    } else {
        $hintChanged = Set-CtrlText $script:LblStatusHint 'Ready to launch. Click Start Server in the sidebar (or press Ctrl+S) to run automatic key, mod, firewall, and UPnP checks.' $Theme.dim
    }
    if ($hintChanged) { $layoutChanged = $true }
    if ($cgnat) {
        if (-not $script:LblCgnatBadge.Visible) { $script:LblCgnatBadge.Visible = $true; $layoutChanged = $true }
        [void](Set-CtrlText $script:LblCgnatBadge '[CGNAT detected] Your ISP shares one public IP - port forwarding can never work. Friends must use FRP, a VPN (Network tab) or your ISP must give you a real public IP.')
    } else {
        if ($script:LblCgnatBadge.Visible) { $script:LblCgnatBadge.Visible = $false; $layoutChanged = $true }
        [void](Set-CtrlText $script:LblCgnatBadge '')
    }

    # 1. Loopback (You - Host PC)
    $loopSuffix = if ($running) { '   (Join from this PC)' } else { '   (Host PC Direct Connect)' }
    $loopCol = if ($running) { $Theme.green } else { $Theme.text }
    [void](Set-CtrlText $script:LblConnThis "$bul  127.0.0.1:$port$loopSuffix" $loopCol)
    Set-RowBtn $script:BtnConnThis 'Copy IP' "127.0.0.1:$port"

    # 2. Local LAN (Home WiFi)
    if ($conn -and $conn.LAN) {
        $lanCol = if ($running) { $Theme.green } else { $Theme.text }
        [void](Set-CtrlText $script:LblConnLan "$bul  $($conn.LAN):$port   (Same WiFi / Router)" $lanCol)
        Set-RowBtn $script:BtnConnLan 'Copy IP' "$($conn.LAN):$port"
    } else {
        [void](Set-CtrlText $script:LblConnLan "$hol  Detecting local network adapter..." $Theme.dim)
        Set-RowBtn $script:BtnConnLan 'Detect' '__REFRESH__'
    }

    # 3. Tunnel (FRP or Playit.gg)
    $playitAddress = Get-PlayitAddress
    if ($running -and $script:State.Frp) {
        $frpDisp = if ($script:StreamerMode) { ($script:State.Frp -replace '\b\d{1,3}(\.\d{1,3}){3}\b', '***.***.***.***') } else { $script:State.Frp }
        [void](Set-CtrlText $script:LblConnTunnel "$bul  $frpDisp   (FRP Public Tunnel)")
        if ($script:RowConnTunnel -and -not $script:RowConnTunnel.Visible) { $script:RowConnTunnel.Visible = $true; $layoutChanged = $true }
        if ($script:StreamerMode) {
            Set-RowBtn $script:BtnConnTunnel 'Protected' '__STREAMER_BLOCKED__'
        } else {
            Set-RowBtn $script:BtnConnTunnel 'Copy IP' "$($script:State.Frp)"
        }
    } elseif ($playitAddress) {
        $playitDisp = if ($script:StreamerMode) { ($playitAddress -replace '\b\d{1,3}(\.\d{1,3}){3}\b', '***.***.***.***') } else { $playitAddress }
        [void](Set-CtrlText $script:LblConnTunnel "$bul  $playitDisp   (Playit.gg Tunnel)")
        if ($script:RowConnTunnel -and -not $script:RowConnTunnel.Visible) { $script:RowConnTunnel.Visible = $true; $layoutChanged = $true }
        if ($script:StreamerMode) {
            Set-RowBtn $script:BtnConnTunnel 'Protected' '__STREAMER_BLOCKED__'
        } else {
            Set-RowBtn $script:BtnConnTunnel 'Copy IP' "$playitAddress"
        }
    } else {
        if ($script:RowConnTunnel -and $script:RowConnTunnel.Visible) { $script:RowConnTunnel.Visible = $false; $layoutChanged = $true }
    }

    # 4. Virtual LAN (VPN)
    $vpnLines = @()
    if ($conn) { $vpnLines = @($conn.Vpn | Where-Object { $_.Ip }) }
    if ($vpnLines.Count) {
        if ($script:StreamerMode) {
            $vpnText = (($vpnLines | ForEach-Object { "$($_.Name) $arr ***.***.***.***:$port [PROTECTED]" }) -join '   ')
            [void](Set-CtrlText $script:LblConnVpn "$bul  $vpnText" $Theme.blue)
            Set-RowBtn $script:BtnConnVpn 'Protected' '__STREAMER_BLOCKED__'
        } else {
            $vpnText = (($vpnLines | ForEach-Object { "$($_.Name) $arr $($_.Ip):$port" }) -join '   ')
            [void](Set-CtrlText $script:LblConnVpn "$bul  $vpnText" $Theme.green)
            Set-RowBtn $script:BtnConnVpn 'Copy IP' "$($vpnLines[0].Ip):$port"
        }
    } else {
        [void](Set-CtrlText $script:LblConnVpn "$hol  Standby   $dot   Radmin / ZeroTier / Hamachi" $Theme.dim)
        Set-RowBtn $script:BtnConnVpn 'Configure' '__NETWORK__'
    }
    if ($script:ConnVpnFlow) {
        $vpnSig = ($vpnLines | ForEach-Object { "$($_.Name):$($_.Ip):$port" }) -join '|'
        $vpnSig += ":$($script:StreamerMode)"
        if ($script:ConnVpnFlow.Tag -ne $vpnSig) {
            $script:ConnVpnFlow.Tag = $vpnSig
            $script:ConnVpnFlow.SuspendLayout()
            foreach ($oldB in @($script:ConnVpnFlow.Controls)) { try { $oldB.Dispose() } catch { } }
            $script:ConnVpnFlow.Controls.Clear()
            if ($vpnLines.Count -ge 2 -and -not $script:StreamerMode) {
                foreach ($v in $vpnLines) {
                    $b = New-CopyButton "Copy $($v.Name) IP" "Copy the $($v.Name) IP:port address ($($v.Ip):$port) - only for friends on the SAME $($v.Name) network." "$($v.Ip):$port" "$($v.Name) address $($v.Ip):$port"
                    $b.Size = New-Object System.Drawing.Size(150, 28)
                    $script:ConnVpnFlow.Controls.Add($b)
                }
                $script:ConnVpnFlow.Visible = $true
            } else {
                $script:ConnVpnFlow.Visible = $false
            }
            $script:ConnVpnFlow.ResumeLayout($true)
            $layoutChanged = $true
        }
    }

    # 5. Tailscale Mesh
    if ($conn -and $conn.Tailscale) {
        if ($script:StreamerMode) {
            [void](Set-CtrlText $script:LblConnTail "$bul  ***.***.***.***:$port   (Tailscale Mesh - Protected)" $Theme.blue)
            Set-RowBtn $script:BtnConnTail 'Protected' '__STREAMER_BLOCKED__'
        } else {
            [void](Set-CtrlText $script:LblConnTail "$bul  $($conn.Tailscale):$port   (Tailscale Mesh)" $Theme.blue)
            Set-RowBtn $script:BtnConnTail 'Copy IP' "$($conn.Tailscale):$port"
        }
    } else {
        [void](Set-CtrlText $script:LblConnTail "$hol  Standby   $dot   Tailscale not running" $Theme.dim)
        Set-RowBtn $script:BtnConnTail 'Set Up' '__NETWORK__'
    }

    # 6. Public Internet (WAN)
    $invText = 'Copy Invite'
    if ($script:BtnInvite.Text -ne $invText) {
        $script:BtnInvite.Text = $invText
        $script:BtnInvite.Invalidate()
        $script:Tip.SetToolTip($script:BtnInvite, $(if ($isPrivate) { 'Your server is PRIVATE - friends cannot find it in the list. This copies the full invite message with the address and connect steps.' } else { 'Copy a ready-made invite message. For a public server friends can also just find it in the BeamMP list.' }))
    }
    $privNote = if ($isPrivate) { '   [PRIVATE]' } else { '   (Public WAN)' }
    if ($script:StreamerMode) {
        [void](Set-CtrlText $script:LblConnPub "$bul  ***.***.***.***:$port$privNote  [PROTECTED / STREAMER MODE]" $Theme.blue)
        Set-RowBtn $script:BtnConnPub 'Protected' '__STREAMER_BLOCKED__'
    } elseif ($conn -and $conn.Public) {
        [void](Set-CtrlText $script:LblConnPub "$bul  $($conn.Public):$port$privNote" $Theme.text)
        Set-RowBtn $script:BtnConnPub 'Copy IP' "$($conn.Public):$port"
    } else {
        [void](Set-CtrlText $script:LblConnPub "$hol  Checking public WAN address..." $Theme.dim)
        Set-RowBtn $script:BtnConnPub 'Detect' '__REFRESH__'
    }

    # 7. Router UPnP Status
    if ($running) {
        if ($script:State.UpnpOk) {
            [void](Set-CtrlText $script:LblConnRouter "$bul  Port $port forwarded $em internet players CAN connect" $Theme.green)
            Set-RowBtn $script:BtnConnRouter 'Diagnostics' '__FIX__'
        } elseif ($cgnat) {
            [void](Set-CtrlText $script:LblConnRouter "$bul  CGNAT detected $em use FRP tunnel or VPN" $Theme.red)
            Set-RowBtn $script:BtnConnRouter 'Tunnels' '__NETWORK__'
        } else {
            [void](Set-CtrlText $script:LblConnRouter "$hol  Not forwarded $em forward port $port (TCP+UDP) or run Scan & Fix" $Theme.yellow)
            Set-RowBtn $script:BtnConnRouter 'Scan & Fix' '__FIX__'
        }
    } else {
        [void](Set-CtrlText $script:LblConnRouter "$hol  Standby $em Port $port opens automatically when the server starts" $Theme.dim)
        Set-RowBtn $script:BtnConnRouter 'Scan & Fix' '__FIX__'
    }

    $badVpn = @()
    if ($conn) { $badVpn = @($conn.Vpn | Where-Object { -not $_.Ip }) }
    if ($badVpn.Count) {
        $noteChanged = Set-CtrlText $script:LblConnNote "NOTE: $($badVpn[0].Name) is running but has no VPN IP yet - join your network inside the VPN app.`nTIP: Do not click your own server in the public BeamMP list from this PC - always use Direct Connect (127.0.0.1:$port)."
    } else {
        $noteChanged = Set-CtrlText $script:LblConnNote "TIP: Do not click your own server in the public BeamMP list from this PC $em always use Direct Connect (127.0.0.1:$port)."
    }
    if ($script:ConnContent) { $script:ConnContent.Invalidate() }
    if ($layoutChanged -or $noteChanged) {
        Layout-HomePage
    }
}

# ---------------------------------------------------------------------------------------
# SETTINGS PAGE
# ---------------------------------------------------------------------------------------
function Show-SettingsPage {
    Set-ActiveNav $script:BtnSettings
    $script:PageLayout = { Update-CardStackLayout }
    if ($script:SettingsPagePanel -and -not $script:SettingsPagePanel.IsDisposed) {
        $script:StackRefs = $script:SettingsStackRefs
        Switch-ContentPage $script:SettingsPagePanel
        Refresh-SettingsFields
        Refresh-Dashboard
        Update-CardStackLayout
        return
    }
    $p = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $p
    $p.SuspendLayout()
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg

    $top = New-PageTop $p 'Settings' 'Everything in one scroll - most settings apply on the next server start.'
    $script:BtnSave = New-Btn 'Save settings' 'Save every setting on this page (name, players, cars, description, tags, toggles). Applies on the next server start.' { Save-Settings }
    $script:BtnSave.BackColor = $Theme.btnSuccess
    $script:BtnSave.FlatAppearance.MouseOverBackColor = $Theme.btnSuccessHov
    $script:BtnSave.FlatAppearance.BorderColor = $Theme.green
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
    $script:TxtName.Height = 32
    Add-Row $card 'Server name:' $script:TxtName

    $flRow = New-ButtonBar
    $script:TxtPlayers = New-SettingsInput
    $script:TxtPlayers.Width = 84
    $script:TxtPlayers.Height = 32
    $script:TxtPlayers.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $lblPlayers = New-Lbl 'players' $Theme.dim 9 32
    $lblPlayers.Margin = New-Object System.Windows.Forms.Padding(0, 6, 20, 0)

    $script:TxtCars = New-SettingsInput
    $script:TxtCars.Width = 84
    $script:TxtCars.Height = 32
    $script:TxtCars.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
    $lblCars = New-Lbl 'max cars per player' $Theme.dim 9 32
    $lblCars.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)

    $flRow.Controls.Add($script:TxtPlayers)
    $flRow.Controls.Add($lblPlayers)
    $flRow.Controls.Add($script:TxtCars)
    $flRow.Controls.Add($lblCars)
    Add-Row $card 'Players / cars:' $flRow

    $script:TxtDescription = New-SettingsInput
    $script:TxtDescription.Multiline = $true
    $script:TxtDescription.Height = 68
    $script:TxtDescription.ScrollBars = 'Vertical'
    Add-Row $card 'Description (optional):' $script:TxtDescription

    $script:TxtTags = New-SettingsInput
    $script:TxtTags.Height = 32
    Add-Row $card 'Tags, comma separated:' $script:TxtTags
    Add-RowNote $card 'Example tags: Freeroam,KBnG,BeamMP - they help players find your server in the list.' $Theme.dim | Out-Null
    $cards += $card

    # ---- Visibility ----
    $card = New-Card 'Server visibility' 'Who can find your server in the BeamMP list.'
    $rFont95 = Get-CachedFont 'Segoe UI' 9.5 ([System.Drawing.FontStyle]::Regular)
    $rFont9  = Get-CachedFont 'Segoe UI' 9 ([System.Drawing.FontStyle]::Regular)
    $script:RadioPublic = New-Object System.Windows.Forms.RadioButton
    $script:RadioPublic.Text = 'Public - listed for everyone (strangers can find and join)'
    $script:RadioPublic.ForeColor = [System.Drawing.Color]::White
    $script:RadioPublic.BackColor = $Theme.card
    $script:RadioPublic.FlatStyle = 'Flat'
    $script:RadioPublic.Font = $rFont95
    $script:RadioPublic.Height = 24
    Add-RowFull $card $script:RadioPublic
    $script:RadioPrivate = New-Object System.Windows.Forms.RadioButton
    $script:RadioPrivate.Text = 'Private - hidden from the list (only people you send the address to can join)'
    $script:RadioPrivate.ForeColor = [System.Drawing.Color]::White
    $script:RadioPrivate.BackColor = $Theme.card
    $script:RadioPrivate.FlatStyle = 'Flat'
    $script:RadioPrivate.Font = $rFont95
    $script:RadioPrivate.Height = 24
    Add-RowFull $card $script:RadioPrivate
    $script:RadioPublic.Add_CheckedChanged({
        if ($script:SuppressSettingEvents) { return }
        if (-not [bool]$this.Checked) { return }
        $script:isPrivate = $false
        $this.ForeColor = $Theme.green
        $script:RadioPrivate.ForeColor = [System.Drawing.Color]::White
    })
    $script:RadioPrivate.Add_CheckedChanged({
        if ($script:SuppressSettingEvents) { return }
        if (-not [bool]$this.Checked) { return }
        $script:isPrivate = $true
        $this.ForeColor = $Theme.green
        $script:RadioPublic.ForeColor = [System.Drawing.Color]::White
    })
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
    $script:TxtMapSearch.Height = 32
    $script:TxtMapSearch.Add_TextChanged({ Refresh-MapListBox })
    Add-Row $card 'Search maps (type to filter):' $script:TxtMapSearch
    $script:CmbMaps = New-Object System.Windows.Forms.ComboBox
    $script:CmbMaps.DropDownStyle = 'DropDownList'
    $script:CmbMaps.Height = 26
    $script:CmbMaps.BackColor = $Theme.bg
    $script:CmbMaps.ForeColor = [System.Drawing.Color]::White
    $script:CmbMaps.FlatStyle = 'Flat'
    $script:CmbMaps.Font = $rFont9
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
    $script:ChkLock.Font = $rFont95
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
    $script:ChkAllowGuests.Font = $rFont9
    $script:ChkAllowGuests.Height = 24
    Add-RowFull $card $script:ChkAllowGuests
    $script:ChkLogChat = New-Object System.Windows.Forms.CheckBox
    $script:ChkLogChat.Text = 'Log chat messages to the server log'
    $script:ChkLogChat.ForeColor = [System.Drawing.Color]::White
    $script:ChkLogChat.BackColor = $Theme.card
    $script:ChkLogChat.Font = $rFont9
    $script:ChkLogChat.Height = 24
    Add-RowFull $card $script:ChkLogChat
    $script:ChkInfoPacket = New-Object System.Windows.Forms.CheckBox
    $script:ChkInfoPacket.Text = 'Send periodic info packets (server list refresh)'
    $script:ChkInfoPacket.ForeColor = [System.Drawing.Color]::White
    $script:ChkInfoPacket.BackColor = $Theme.card
    $script:ChkInfoPacket.Font = $rFont9
    $script:ChkInfoPacket.Height = 24
    Add-RowFull $card $script:ChkInfoPacket
    $script:ChkDebug = New-Object System.Windows.Forms.CheckBox
    $script:ChkDebug.Text = 'Debug mode (more detail written to the server log)'
    $script:ChkDebug.ForeColor = [System.Drawing.Color]::White
    $script:ChkDebug.BackColor = $Theme.card
    $script:ChkDebug.Font = $rFont9
    $script:ChkDebug.Height = 24
    Add-RowFull $card $script:ChkDebug
    $cards += $card

    # ---- Streamer Privacy Mode ----
    $card = New-Card 'Streamer Privacy Mode' 'Mask sensitive data during live broadcasting and recording.'
    $script:ChkStreamerMode = New-Object System.Windows.Forms.CheckBox
    $script:ChkStreamerMode.Text = 'Enable Streamer Privacy Mode (instantly redacts WAN IP, AuthKey, and Windows usernames)'
    $script:ChkStreamerMode.ForeColor = $Theme.green
    $script:ChkStreamerMode.BackColor = $Theme.card
    $script:ChkStreamerMode.Font = $rFont95
    $script:ChkStreamerMode.Height = 26
    $script:ChkStreamerMode.Checked = [bool]$script:StreamerMode
    $script:ChkStreamerMode.Add_CheckedChanged({
        if ($script:SuppressSettingEvents) { return }
        Set-StreamerMode $this.Checked
    })
    Add-RowFull $card $script:ChkStreamerMode
    Add-RowNote $card 'When active, WAN IPs, server keys, and local user file paths are replaced with *** across the Dashboard, Network tab, and Activity Console. A quick toggle is also always available in the top-right header.' $Theme.dim | Out-Null
    $cards += $card

    # ---- Advanced Server Settings (Collapsible Accordion) ----
    $card = New-Card 'Advanced Server Settings' 'Bind IP, custom port, resource folder, and engine update reminders.'
    $script:AdvancedControls = @()

    $advTopBar = New-ButtonBar
    $script:BtnToggleAdvanced = New-Btn $(if ($script:AdvancedExpanded) { 'v  Hide Advanced Settings' } else { '>  Show Advanced Settings (5 options)' }) 'Click to expand or collapse fine-grained server engine settings.' {
        $script:AdvancedExpanded = -not [bool]$script:AdvancedExpanded
        $script:BtnToggleAdvanced.Text = if ($script:AdvancedExpanded) { 'v  Hide Advanced Settings' } else { '>  Show Advanced Settings (5 options)' }
        $script:BtnToggleAdvanced.ForeColor = if ($script:AdvancedExpanded) { $Theme.blue } else { [System.Drawing.Color]::White }
        foreach ($ctrl in $script:AdvancedControls) {
            $ctrl.Visible = $script:AdvancedExpanded
        }
        Update-CardStackLayout
    }
    $script:BtnToggleAdvanced.Size = New-Object System.Drawing.Size(260, 32)
    $script:BtnToggleAdvanced.BackColor = $Theme.panel
    $advTopBar.Controls.Add($script:BtnToggleAdvanced)
    Add-RowFull $card $advTopBar

    # 1. Custom Listen Port
    $flPort = New-ButtonBar
    $flPort.Visible = [bool]$script:AdvancedExpanded
    $script:TxtCustomPort = New-SettingsInput
    $script:TxtCustomPort.Width = 90
    $script:TxtCustomPort.Height = 32
    $flPort.Controls.Add($script:TxtCustomPort)
    $flPort.Controls.Add((New-Lbl 'default: 30814 (TCP + UDP listen port; range: 1024-65535)' $Theme.dim 9 20))
    Add-Row $card 'Game listen port:' $flPort
    $script:AdvancedControls += $flPort
    $tAdv = $card.Tag
    if ($tAdv.Controls.Count -ge 2) { $script:AdvancedControls += $tAdv.Controls[$tAdv.Controls.Count - 2]; $tAdv.Controls[$tAdv.Controls.Count - 2].Visible = [bool]$script:AdvancedExpanded }

    # 2. Network Bind IP
    $flBind = New-ButtonBar
    $flBind.Visible = [bool]$script:AdvancedExpanded
    $script:TxtBindIp = New-SettingsInput
    $script:TxtBindIp.Width = 160
    $script:TxtBindIp.Height = 32
    $flBind.Controls.Add($script:TxtBindIp)
    $flBind.Controls.Add((New-Lbl 'default: :: (dual-stack IPv6/IPv4; or 0.0.0.0 for IPv4)' $Theme.dim 9 20))
    Add-Row $card 'Bind IP address (IP):' $flBind
    $script:AdvancedControls += $flBind
    if ($tAdv.Controls.Count -ge 2) { $script:AdvancedControls += $tAdv.Controls[$tAdv.Controls.Count - 2]; $tAdv.Controls[$tAdv.Controls.Count - 2].Visible = [bool]$script:AdvancedExpanded }

    # 3. Resource Folder
    $flRes = New-ButtonBar
    $flRes.Visible = [bool]$script:AdvancedExpanded
    $script:TxtResourceFolder = New-SettingsInput
    $script:TxtResourceFolder.Width = 160
    $script:TxtResourceFolder.Height = 32
    $flRes.Controls.Add($script:TxtResourceFolder)
    $flRes.Controls.Add((New-Lbl 'default: Resources (folder where synced mods reside)' $Theme.dim 9 20))
    Add-Row $card 'Resource folder:' $flRes
    $script:AdvancedControls += $flRes
    if ($tAdv.Controls.Count -ge 2) { $script:AdvancedControls += $tAdv.Controls[$tAdv.Controls.Count - 2]; $tAdv.Controls[$tAdv.Controls.Count - 2].Visible = [bool]$script:AdvancedExpanded }

    # 4. Hide Update Reminders
    $script:ChkImScaredOfUpdates = New-Object System.Windows.Forms.CheckBox
    $script:ChkImScaredOfUpdates.Text = 'Hide periodic update reminders in server console (ImScaredOfUpdates)'
    $script:ChkImScaredOfUpdates.ForeColor = [System.Drawing.Color]::White
    $script:ChkImScaredOfUpdates.BackColor = $Theme.card
    $script:ChkImScaredOfUpdates.Font = $rFont9
    $script:ChkImScaredOfUpdates.Height = 24
    $script:ChkImScaredOfUpdates.Visible = [bool]$script:AdvancedExpanded
    Add-RowFull $card $script:ChkImScaredOfUpdates
    $script:AdvancedControls += $script:ChkImScaredOfUpdates

    # 5. Update Reminder Frequency
    $flRem = New-ButtonBar
    $flRem.Visible = [bool]$script:AdvancedExpanded
    $script:TxtUpdateReminder = New-SettingsInput
    $script:TxtUpdateReminder.Width = 90
    $script:TxtUpdateReminder.Height = 32
    $flRem.Controls.Add($script:TxtUpdateReminder)
    $flRem.Controls.Add((New-Lbl 'default: 30s (e.g., 30s, 5min, 1h, 1d)' $Theme.dim 9 20))
    Add-Row $card 'Update reminder frequency:' $flRem
    $script:AdvancedControls += $flRem
    if ($tAdv.Controls.Count -ge 2) { $script:AdvancedControls += $tAdv.Controls[$tAdv.Controls.Count - 2]; $tAdv.Controls[$tAdv.Controls.Count - 2].Visible = [bool]$script:AdvancedExpanded }

    $cards += $card

    # ---- Presets ----
    $card = New-Card 'Presets' 'Save a whole setup (settings + enabled mods) under a name, load it back later. Great for different game nights.'
    $preRow = New-ButtonBar
    $script:TxtPresetName = New-SettingsInput
    $script:TxtPresetName.Width = 200
    $script:TxtPresetName.Height = 32
    $preRow.Controls.Add($script:TxtPresetName)
    $preRow.Controls.Add((New-Lbl 'or pick one:' $Theme.dim 9 20))
    $script:CmbPresets = New-Object System.Windows.Forms.ComboBox
    $script:CmbPresets.DropDownStyle = 'DropDownList'
    $script:CmbPresets.Width = 220
    $script:CmbPresets.Height = 26
    $script:CmbPresets.BackColor = $Theme.bg
    $script:CmbPresets.ForeColor = [System.Drawing.Color]::White
    $script:CmbPresets.FlatStyle = 'Flat'
    $script:CmbPresets.Font = $rFont9
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
    $p.ResumeLayout($false)
    $script:SettingsStackRefs = $script:StackRefs
    $script:SettingsPagePanel = $p
    Switch-ContentPage $p
    $script:SuppressSettingEvents = $true
    $script:ChkLock.Checked = (Test-StaticIpLocked)
    $script:SuppressSettingEvents = $false
    Refresh-SettingsFields
    Refresh-MapCombo
    Refresh-PresetCombo
    Refresh-Dashboard
}

function Get-AllConfigValues {
    $cfgPath = $script:RootDir + 'ServerConfig.toml'
    $res = @{}
    if (Test-Path -LiteralPath $cfgPath) {
        try {
            foreach ($line in [System.IO.File]::ReadAllLines($cfgPath)) {
                if ($line -match '^\s*([^#=\s]+)\s*=\s*(.+?)\s*$') {
                    $res[$Matches[1]] = $Matches[2].Trim().Trim('"')
                }
            }
        } catch { }
    }
    return $res
}

# Fills the settings inputs from the current ServerConfig.toml values.
function Refresh-SettingsFields {
    try {
        if (-not $script:TxtName) { return }
        $script:SuppressSettingEvents = $true
        try {
            $cfg = Get-AllConfigValues
            $script:TxtName.Text = if ($cfg.ContainsKey('Name')) { $cfg['Name'] } else { '' }
            $script:TxtPlayers.Text = if ($cfg.ContainsKey('MaxPlayers')) { $cfg['MaxPlayers'] } else { '8' }
            $script:TxtCars.Text = if ($cfg.ContainsKey('MaxCars')) { $cfg['MaxCars'] } else { '1' }
            $script:TxtDescription.Text = if ($cfg.ContainsKey('Description')) { $cfg['Description'] } else { '' }
            $script:TxtTags.Text = if ($cfg.ContainsKey('Tags')) { $cfg['Tags'] } else { '' }
            $script:ChkAllowGuests.Checked = ($cfg['AllowGuests'] -match 'true|1')
            $script:ChkLogChat.Checked = ($cfg['LogChat'] -match 'true|1')
            $script:ChkDebug.Checked = ($cfg['Debug'] -match 'true|1')
            $script:ChkInfoPacket.Checked = ($cfg['InformationPacket'] -match 'true|1')
            $curPort = if ($script:State -and $script:State.Port) { [string]$script:State.Port } elseif ($cfg.ContainsKey('Port')) { $cfg['Port'] } else { '30814' }
            if ($script:TxtCustomPort) { $script:TxtCustomPort.Text = $curPort }
            if ($script:LblSettings3) { $script:LblSettings3.Text = "Port: $curPort  (change it automatically if it is ever busy)" }
            if ($script:TxtBindIp) { $script:TxtBindIp.Text = if ($cfg.ContainsKey('IP')) { $cfg['IP'] } else { '::' } }
            if ($script:TxtResourceFolder) { $script:TxtResourceFolder.Text = if ($cfg.ContainsKey('ResourceFolder')) { $cfg['ResourceFolder'] } else { 'Resources' } }
            if ($script:ChkImScaredOfUpdates) { $script:ChkImScaredOfUpdates.Checked = ($cfg['ImScaredOfUpdates'] -match 'true|1') }
            if ($script:TxtUpdateReminder) { $script:TxtUpdateReminder.Text = if ($cfg.ContainsKey('UpdateReminderTime')) { $cfg['UpdateReminderTime'] } else { '30s' } }
            if ($script:ChkStreamerMode) { $script:ChkStreamerMode.Checked = [bool]$script:StreamerMode }
            $isPriv = ($cfg['Private'] -match 'true|1')
            $script:isPrivate = [bool]$isPriv
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
    $script:CmbPresets.BeginUpdate()
    try {
        $script:CmbPresets.Items.Clear()
        foreach ($n in Get-Presets) { [void]$script:CmbPresets.Items.Add($n) }
        if ($keep -and $script:CmbPresets.Items.Contains($keep)) { $script:CmbPresets.SelectedItem = $keep }
        elseif ($script:CmbPresets.Items.Count) { $script:CmbPresets.SelectedIndex = 0 }
    } finally {
        $script:CmbPresets.EndUpdate()
    }
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
        try {
            $script:CachedMaps = @(Get-AvailableMaps)
        } catch {
            $script:CachedMaps = @()
            Add-Log "[ERROR] Map scan failed: $($_.Exception.Message)"
        }
        Add-Log "[INFO] Map scan done - $($script:CachedMaps.Count) map(s) available."
    }
    Refresh-MapListBox
}

# Rebuilds the combo from $script:CachedMaps, honoring the search filter text.
function Refresh-MapListBox {
    if (-not $script:CmbMaps) { return }
    $q = ''
    if ($script:TxtMapSearch) { $q = $script:TxtMapSearch.Text.Trim() }
    $filtered = @($script:CachedMaps | Where-Object { -not $q -or $_.Name -like "*$q*" -or $_.Path -like "*$q*" })

    $cur = Get-ServerMap
    $curName = Get-MapNameFromPath $cur

    # If the current server map was not found in the scan and there is no search query,
    # insert a placeholder object at index 0 of both the array and the combo box
    # so every ComboBox item index matches $script:FilteredMaps 1-to-1.
    if ($curName -and -not $q) {
        $found = $false
        foreach ($m in $filtered) {
            if ($m.Name -ieq $curName) { $found = $true; break }
        }
        if (-not $found) {
            $placeholder = [pscustomobject]@{
                Name = $curName
                Kind = 'Missing'
                Path = $cur
                Zip = $null
                IsPlaceholder = $true
            }
            $filtered = @($placeholder) + @($filtered)
        }
    }

    $script:FilteredMaps = $filtered
    $script:CmbMaps.BeginUpdate()
    try {
        $script:CmbMaps.Items.Clear()
        foreach ($m in $script:FilteredMaps) {
            $disp = if ($m.IsPlaceholder) {
                "$($m.Name)   (current, not found in scan)"
            } elseif ($m.Kind -eq 'Vanilla') {
                "$($m.Name)   (Vanilla)"
            } else {
                "$($m.Name)   [MAP MOD]"
            }
            [void]$script:CmbMaps.Items.Add($disp)
        }

        if ($curName -and -not $q) {
            $idx = -1
            for ($i = 0; $i -lt $script:FilteredMaps.Count; $i++) {
                if ($script:FilteredMaps[$i].Name -ieq $curName) { $idx = $i; break }
            }
            if ($idx -ge 0) { $script:CmbMaps.SelectedIndex = $idx }
        } elseif ($script:FilteredMaps.Count -gt 0 -and $script:CmbMaps.SelectedIndex -lt 0) {
            $script:CmbMaps.SelectedIndex = 0
        }
    } finally {
        $script:CmbMaps.EndUpdate()
    }
}

function Apply-MapSelection {
    if (-not $script:CmbMaps) { return }
    $idx = $script:CmbMaps.SelectedIndex
    if ($idx -lt 0 -or $idx -ge $script:FilteredMaps.Count) { Add-Log "[INFO] Select a map first."; return }
    $map = $script:FilteredMaps[$idx]
    if (-not $map) { Add-Log "[INFO] Select a map first."; return }
    if ($map.IsPlaceholder) {
        Add-Log "[INFO] The current map was not found in the scan - pick another map from the list."
        return
    }
    $zipArg = ''
    if ($map.Zip) { $zipArg = " -ZipToHost " + (QStr $map.Zip) }
    Add-Log "[INFO] Applying map $($map.Name)..."
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Set-ServerMap -LevelName $(QStr $map.Name)$zipArg)`n`$State.MapRefresh = (Get-Date).ToString('o')" 'setmap'
}

function Apply-Visibility {
    if (-not $script:RadioPrivate) { return }
    $script:isPrivate = [bool]$script:RadioPrivate.Checked
    $script:State.IsPrivate = $script:isPrivate
    $priv = $script:isPrivate
    if ($script:LblSettingsResult) {
        $script:LblSettingsResult.Text = $(if ($priv) { 'Saving: PRIVATE server...' } else { 'Saving: PUBLIC server...' })
        $script:LblSettingsResult.ForeColor = $Theme.yellow
    }
    if ($script:BtnApplyVis) { $script:BtnApplyVis.Text = $(if ($priv) { 'Apply visibility (PRIVATE)' } else { 'Apply visibility (public)' }) }
    Add-Log "[INFO] Writing visibility to ServerConfig.toml: $(if ($priv) { 'private' } else { 'public' })..."
    # Evaluates $script:isPrivate at click time; the current AuthKey value is
    # preserved. No TOML read feeds back into the toggle - only this write.
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.IsPrivate = $(if ($priv) { '$true' } else { '$false' })`nSay (Save-AuthConfig -Private $(if ($priv) { '$true' } else { '$false' }) -AuthKey (Get-ConfigValue 'AuthKey'))`n`$State.VisRefresh = (Get-Date).ToString('o')" 'setvis'
}

function Save-Settings {
    $vals = @{}
    $name = $script:TxtName.Text.Trim()
    if ($name) {
        # Edge-case friendly: quotes and line breaks are sanitized instead of
        # rejecting the whole save; overlong names are trimmed to 60 chars.
        $origName = $name
        $name = $name.Replace('"', "'") -replace '[\x00-\x1F]', ' '
        if ($name.Length -gt 60) { $name = $name.Substring(0, 60).TrimEnd() }
        if ($name -ne $origName) { Add-Log "[INFO] Server name adjusted for compatibility (quotes/line breaks removed, 60 char limit)." }
        $vals['Name'] = '"' + $name + '"'
    }
    foreach ($pair in @(@{ Key = 'MaxPlayers'; Txt = $script:TxtPlayers }, @{ Key = 'MaxCars'; Txt = $script:TxtCars })) {
        $v = $pair.Txt.Text.Trim()
        if ($v) {
            # Non-numeric text (or "0" and odd formats) never blocks the save:
            # digits are extracted when possible, otherwise the current config
            # value is kept untouched.
            $num = 0
            try { $num = [int]([regex]::Match([string]$v, '\d+').Value) } catch { $num = 0 }
            if ($num -le 0) {
                Add-Log "[INFO] $($pair.Key) input was not a positive number - leaving the existing value unchanged."
            } else {
                if ($pair.Key -eq 'MaxPlayers' -and $num -gt 500) { $num = 500; Add-Log '[INFO] MaxPlayers capped at 500.' }
                if ($pair.Key -eq 'MaxCars' -and $num -gt 100) { $num = 100; Add-Log '[INFO] MaxCars capped at 100.' }
                $vals[$pair.Key] = [int]$num
            }
        }
    }
    $desc = $script:TxtDescription.Text.Trim().Replace('"', "'") -replace '[\x00-\x1F]', ' '
    if ($desc) { $vals['Description'] = '"' + $desc + '"' } else { $vals['Description'] = '""' }
    $tags = $script:TxtTags.Text.Trim().Replace('"', "'") -replace '[\x00-\x1F]', ' '
    if ($tags) { $vals['Tags'] = '"' + $tags + '"' } else { $vals['Tags'] = '""' }
    # Advanced settings validation & persistence
    if ($script:TxtCustomPort) {
        $pVal = $script:TxtCustomPort.Text.Trim()
        if ($pVal -match '^\d+$') {
            $pNum = [int]$pVal
            if ($pNum -ge 1024 -and $pNum -le 65535) {
                $vals['Port'] = $pNum
                $script:State.Port = $pNum
                if ($script:State.Conn) { $script:State.Conn.Port = $pNum }
                if ($script:LblSettings3) {
                    $script:LblSettings3.Text = "Port: $pNum  (change it automatically if it is ever busy)"
                }
                Add-Log "[INFO] Game listen port set to $pNum (applies on next start)."
            } else {
                Add-Log '[WARN] Game port must be between 1024 and 65535 - leaving unchanged.'
            }
        }
    }
    if ($script:TxtBindIp) {
        $bIp = $script:TxtBindIp.Text.Trim().Replace('"', '') -replace '[\x00-\x1F]', ''
        if ($bIp) { $vals['IP'] = '"' + $bIp + '"' } else { $vals['IP'] = '"::"' }
    }
    if ($script:TxtResourceFolder) {
        $rFold = $script:TxtResourceFolder.Text.Trim().Replace('"', '') -replace '[\x00-\x1F/\\\:]', ''
        if ($rFold) { $vals['ResourceFolder'] = '"' + $rFold + '"' } else { $vals['ResourceFolder'] = '"Resources"' }
    }
    if ($script:ChkImScaredOfUpdates) {
        $vals['ImScaredOfUpdates'] = $script:ChkImScaredOfUpdates.Checked.ToString().ToLower()
    }
    if ($script:TxtUpdateReminder) {
        $uRem = $script:TxtUpdateReminder.Text.Trim().Replace('"', '') -replace '[\x00-\x1F]', ''
        if ($uRem) { $vals['UpdateReminderTime'] = '"' + $uRem + '"' } else { $vals['UpdateReminderTime'] = '"30s"' }
    }

    $vals['AllowGuests'] = $script:ChkAllowGuests.Checked.ToString().ToLower()
    $vals['LogChat'] = $script:ChkLogChat.Checked.ToString().ToLower()
    $vals['Debug'] = $script:ChkDebug.Checked.ToString().ToLower()
    $vals['InformationPacket'] = $script:ChkInfoPacket.Checked.ToString().ToLower()
    # The Public/Private toggle is evaluated from $script:isPrivate right here,
    # so "Save settings" commits Private = true/false to the TOML on this click.
    $vals['Private'] = $(if ($script:isPrivate) { 'true' } else { 'false' })

    # FRP tunnel settings (persisted to the [FRP] section of ServerConfig.toml) -
    # the fields live on the Network page; keep them when that page was opened.
    if ($script:ChkFrp) {
        $vals['FRPEnabled'] = $script:ChkFrp.Checked.ToString().ToLower()
        $frpServer = $script:TxtFrpServer.Text.Trim()
        if ($frpServer) {
            # Pasted URLs / host:port strings are accepted: everything that is
            # not part of a hostname or IP is stripped, so no input can fail
            # the save.
            $cleanServer = ($frpServer -replace '^\s*(https?://)?', '') -replace '[:/,\s]+$', ''
            $cleanServer = $cleanServer -replace '[^A-Za-z0-9.\-]', ''
            if ($cleanServer -and $cleanServer -ne $frpServer) { Add-Log "[INFO] FRP server address adjusted to: $cleanServer" }
            if (-not $cleanServer) {
                Add-Log '[INFO] FRP server address could not be used as-is - leaving the existing value unchanged.'
            } else {
                $vals['FRPServerAddress'] = '"' + $cleanServer + '"'
            }
        }
        $frpPort = $script:TxtFrpPort.Text.Trim()
        if ($frpPort -match '^\d+$') {
            $p = [int]$frpPort
            if ($p -lt 1 -or $p -gt 65535) { $p = 7000; Add-Log '[INFO] FRP server port was out of range - using the default 7000.' }
            $vals['FRPServerPort'] = $p
        } elseif (-not $frpPort) {
            $vals['FRPServerPort'] = 7000
        } else {
            $p = 0
            try { $p = [int]([regex]::Match([string]$frpPort, '\d+').Value) } catch { $p = 0 }
            if ($p -lt 1 -or $p -gt 65535) { $p = 7000 }
            Add-Log "[INFO] FRP server port adjusted to $p."
            $vals['FRPServerPort'] = $p
        }
        $frpToken = $script:TxtFrpToken.Text
        if ($frpToken) {
            $vals['FRPToken'] = '"' + (($frpToken.Replace('"', '') -replace '[\x00-\x1F]', '')) + '"'
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
function Show-NetworkPage([bool]$ForceRefresh = $false) {
    Set-ActiveNav $script:BtnNetwork
    $script:PageLayout = { Update-CardStackLayout }
    if (-not $ForceRefresh -and $script:NetworkPagePanel -and -not $script:NetworkPagePanel.IsDisposed) {
        $script:StackRefs = $script:NetworkStackRefs
        Switch-ContentPage $script:NetworkPagePanel
        Refresh-FrpFields
        Update-CardStackLayout
        return
    }
    $p = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $p
    $p.SuspendLayout()
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg

    $top = New-PageTop $p 'Network' 'Everything about how friends reach you: FRP tunnel, VPNs and CGNAT.'
    $btnRefresh = New-Btn 'Refresh' 'Re-check which VPNs are installed / running and their IPs.' { Get-InstalledVpns $true | Out-Null; Show-NetworkPage $true }
    $btnRefresh.Size = New-Object System.Drawing.Size(90, 34)
    $top.Flow.Controls.Add($btnRefresh)
    $p.Controls.Add($top.Bar)

    $stack = New-CardStack $p
    $cards = @()

    # ---- FRP tunnel ----
    $card = New-Card 'FRP tunnel (Fast Reverse Proxy)' 'Host without router port forwarding - works even behind CGNAT.'
    $script:ChkFrp = New-Object System.Windows.Forms.CheckBox
    $script:ChkFrp.Text = 'Enable FRP tunnel (friends join through your FRP server)'
    $script:ChkFrp.ForeColor = $Theme.text
    $script:ChkFrp.BackColor = $Theme.card
    $script:ChkFrp.Font = Get-CachedFont 'Segoe UI' 9.5 ([System.Drawing.FontStyle]::Regular)
    $script:ChkFrp.Height = 26
    $script:ChkFrp.Add_CheckedChanged({
        if (-not $script:SuppressSettingEvents) { Persist-FrpToggle }
    })
    Add-RowFull $card $script:ChkFrp
    $script:TxtFrpServer = New-SettingsInput
    $script:TxtFrpServer.Height = 32
    Add-Row $card 'FRP server address (hostname or IP):' $script:TxtFrpServer
    $frpRow = New-ButtonBar
    $script:TxtFrpPort = New-SettingsInput
    $script:TxtFrpPort.Width = 90
    $script:TxtFrpPort.Height = 32
    $frpRow.Controls.Add($script:TxtFrpPort)
    $frpRow.Controls.Add((New-Lbl 'server port (almost always 7000)' $Theme.dim 9 20))
    Add-Row $card 'FRP server port:' $frpRow
    $script:TxtFrpToken = New-SettingsInput
    $script:TxtFrpToken.Height = 32
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
    Enable-DoubleBuffer $script:VpnRowsWrap
    $script:VpnRowsWrap.AutoSize = $false
    $script:VpnRowsWrap.Height = 252
    $script:VpnRowsWrap.MinimumSize = New-Object System.Drawing.Size(0, 252)
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

    Refresh-VpnRows
    Refresh-FrpFields
    & $script:MountCards $cards $stack.Content
    $p.ResumeLayout($false)
    $script:NetworkStackRefs = $script:StackRefs
    $script:NetworkPagePanel = $p
    Switch-ContentPage $p
    try { $script:Form.PerformLayout() } catch { }
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
    $b.BackColor = $Theme.btnDanger
    $b.FlatAppearance.MouseOverBackColor = $Theme.btnDangerHov
    $b.FlatAppearance.BorderColor = $Theme.btnDangerBorder
    $b.ForeColor = [System.Drawing.Color]::White
    return $b
}

function Refresh-VpnRows {
    if (-not $script:VpnRowsWrap) { return }
    $script:VpnRowsWrap.SuspendLayout()
    try {
        foreach ($oldC in @($script:VpnRowsWrap.Controls)) { try { $oldC.Dispose() } catch { } }
        $script:VpnRowsWrap.Controls.Clear()
        $rows = @()
        $apps = @(Get-InstalledVpns)
        $running = @(Get-VpnIps)
        $srvPort = if ($script:State -and $script:State.Port) { $script:State.Port } elseif ($conn -and $conn.Port) { $conn.Port } else { Get-ServerPort }
        foreach ($app in $apps) {
            $run = @($running | Where-Object { $_.Key -eq $app.Key })
            $rowPanel = New-Object System.Windows.Forms.Panel
            Enable-DoubleBuffer $rowPanel
            $rowPanel.BackColor = $Theme.panel
            $rowPanel.Dock = 'Top'
            $rowPanel.Height = 42
            $rowPanel.Padding = New-Object System.Windows.Forms.Padding(12, 5, 10, 5)
            $rowPanel.Add_Paint({
                param($s, $e)
                try {
                    $e.Graphics.DrawLine((Get-CachedPen $Theme.border 1), 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
                } catch { }
            })

            $state = ''
            $color = $Theme.dim
            $dot = [char]0x00B7
            $em  = [char]0x2014
            if (-not $app.Installed) {
                $state = 'NOT installed'
                $color = $Theme.yellow
            } elseif ($run.Count -and $run[0].Ip) {
                $dispVpnIp = if ($script:StreamerMode) { '***.***.***.***' } else { $run[0].Ip }
                $state = "RUNNING  $dot  IP $dispVpnIp"
                $color = if ($script:StreamerMode) { $Theme.blue } else { $Theme.green }
            } elseif ($run.Count) {
                $state = "RUNNING  $dot  connecting (no VPN IP yet)"
                $color = $Theme.yellow
            } else {
                $state = 'installed, not running'
                $color = $Theme.dim
            }

            $lbl = New-Lbl "$($app.Name)   $em   $state" $color 9.75 32
            $lbl.AutoSize = $false
            $lbl.Dock = 'Fill'
            $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
            $lbl.AutoEllipsis = $true
            $lbl.Padding = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
            $rowPanel.Controls.Add($lbl)

            $btnFlow = New-Object System.Windows.Forms.FlowLayoutPanel
            Enable-DoubleBuffer $btnFlow
            $btnFlow.Dock = 'Right'
            $btnFlow.AutoSize = $true
            $btnFlow.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
            $btnFlow.WrapContents = $false
            $btnFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
            $rowPanel.Controls.Add($btnFlow)

            if ($app.Installed -and $run.Count -and $run[0].Ip -and $app.Key -ne 'playit') {
                if ($script:StreamerMode) {
                    $btnCopy = New-Btn 'Protected' 'Streamer Privacy Mode: VPN IP is protected.' {
                        Add-Log '[NOTE] Clipboard copy blocked: VPN endpoint is masked while Streamer Privacy Mode is active.'
                    }
                    $btnCopy.ForeColor = $Theme.dim
                    $btnCopy.Size = New-Object System.Drawing.Size(84, 30)
                    $btnFlow.Controls.Add($btnCopy)
                } else {
                    $btnCopy = New-CopyButton 'Copy IP' "Copy the VPN address (IP:port) of $($app.Name) to your clipboard - paste it to your friends so they can direct-connect." "$($run[0].Ip):$srvPort" "VPN address of $($app.Name): $($run[0].Ip):$srvPort"
                    $btnCopy.Size = New-Object System.Drawing.Size(84, 30)
                    $btnFlow.Controls.Add($btnCopy)
                }
            }
            if ($app.Key -eq 'playit' -and $app.Installed) {
                $address = Get-PlayitAddress
                if ($address) {
                    if ($script:StreamerMode) {
                        $btnCopy = New-Btn 'Protected' 'Streamer Privacy Mode: Playit tunnel address is protected.' {
                            Add-Log '[NOTE] Clipboard copy blocked: Tunnel address is masked while Streamer Privacy Mode is active.'
                        }
                        $btnCopy.ForeColor = $Theme.dim
                        $btnCopy.Size = New-Object System.Drawing.Size(110, 30)
                        $btnFlow.Controls.Add($btnCopy)
                    } else {
                        $btnCopy = New-CopyButton 'Copy Address' "Copy the Playit.gg tunnel address to your clipboard - paste it to your friends so they can direct-connect." "$address" "Playit.gg address: $address"
                        $btnCopy.Size = New-Object System.Drawing.Size(110, 30)
                        $btnFlow.Controls.Add($btnCopy)
                    }
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
        $btnAllRow.Height = 42
        $btnAllRow.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 4)
        $btnAll.Dock = 'Left'
        $btnAllRow.Controls.Add($btnAll)
        $rows += $btnAllRow
        for ($i = $rows.Count - 1; $i -ge 0; $i--) { $script:VpnRowsWrap.Controls.Add($rows[$i]) }
        $wrapH = ($rows.Count * 42)
        $script:VpnRowsWrap.Height = $wrapH
        $script:VpnRowsWrap.MinimumSize = New-Object System.Drawing.Size(0, $wrapH)
    } finally {
        $script:VpnRowsWrap.ResumeLayout($true)
    }
    Update-CardStackLayout
    Add-Log "[INFO] VPN tools refreshed."
}

# ---------------------------------------------------------------------------------------
# FIX PAGE
# ---------------------------------------------------------------------------------------
function Show-FixPage {
    Set-ActiveNav $script:BtnFix
    $script:PageLayout = { Layout-FixRows }
    if ($script:FixPagePanel -and -not $script:FixPagePanel.IsDisposed) {
        Switch-ContentPage $script:FixPagePanel
        & $script:PageLayout
        return
    }
    $p = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $p
    $p.SuspendLayout()
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg
    $p.Padding = New-Object System.Windows.Forms.Padding(12, 4, 12, 4)

    $fixWrap = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $fixWrap
    $fixWrap.Dock = 'Fill'
    $fixWrap.BackColor = $Theme.bg

    $script:FixViewport = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $script:FixViewport
    $script:FixViewport.Dock = 'Fill'
    $script:FixViewport.BackColor = $Theme.bg
    $script:FixViewport.AutoScroll = $false

    $script:FixRowsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    Enable-DoubleBuffer $script:FixRowsPanel
    $script:FixRowsPanel.Location = New-Object System.Drawing.Point(0, 0)
    $script:FixRowsPanel.AutoSize = $true
    $script:FixRowsPanel.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $script:FixRowsPanel.FlowDirection = 'TopDown'
    $script:FixRowsPanel.WrapContents = $false
    $script:FixRowsPanel.AutoScroll = $false
    $script:FixRowsPanel.BackColor = $Theme.bg
    $script:FixViewport.Controls.Add($script:FixRowsPanel)

    $script:FixScrollBar = Attach-ModernScrollBar $fixWrap $script:FixViewport $script:FixRowsPanel {
        if ($script:FixRowsPanel) { $script:FixRowsPanel.PreferredSize.Height } else { 0 }
    }
    $fixWrap.Controls.Add($script:FixViewport)
    $script:FixViewport.BringToFront()

    $script:FixTop = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $script:FixTop
    $script:FixTop.Dock = 'Top'
    $script:FixTop.Height = 96
    $script:FixTop.BackColor = $Theme.bg

    $head = New-Lbl 'Help / Fix Problems' $Theme.text 13.5 26 $true
    $head.Location = New-Object System.Drawing.Point(4, 2)
    $script:FixTop.Controls.Add($head)
    $sub = New-Lbl 'Every check is run for you. PASS = fine, FIX = fix it (use the button on that row), WARN = needs your attention. Start the server first if you want the internet test to run.' $Theme.dim 9 20  $false 900
    $sub.Location = New-Object System.Drawing.Point(4, 30)
    $script:FixTop.Controls.Add($sub)

    $btnScan = New-Btn 'Re-scan everything' 'Run every check again (key, launcher, port, firewall, CGNAT, internet reachability...).' { Run-FixScan }
    $btnScan.Size = New-Object System.Drawing.Size(160, 34)
    $btnScan.Location = New-Object System.Drawing.Point(4, 54)
    $btnScan.BackColor = $Theme.btnAct
    $btnScan.FlatAppearance.BorderColor = $Theme.blue
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
    $script:BtnFixAll.BackColor = $Theme.btnSuccess
    $script:BtnFixAll.FlatAppearance.MouseOverBackColor = $Theme.btnSuccessHov
    $script:BtnFixAll.FlatAppearance.BorderColor = $Theme.green
    $script:BtnFixAll.Tag = @{ X = 390; Y = 54; W = 150; H = 34 }
    $script:FixTop.Controls.Add($script:BtnFixAll)

    $p.Controls.Add($fixWrap)
    $p.Controls.Add($script:FixTop)
    $p.ResumeLayout($false)
    $script:FixPagePanel = $p
    Switch-ContentPage $p
    $script:FixRowRefs = @()
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
    Layout-FixRows
}

function Run-FixScan {
    $script:FixRowsPanel.Controls.Clear()
    $script:FixRowRefs = @()
    $script:LblFixSummary = New-Lbl 'Scanning... (the first scan takes a few seconds, then it is fast)' $Theme.dim 10 22
    $script:LblFixSummary.Location = New-Object System.Drawing.Point(4, 4)
    $script:FixRowsPanel.Controls.Add($script:LblFixSummary)
    Layout-FixRows
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.FixReport = @(Get-FixReport)" 'fixscan'
}

function Run-FixAll {
    Add-Log "[INFO] Fix all: running the safe automatic fixes..."
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`nSay (Fix-AllPossible)`n`$State.FixReport = @(Get-FixReport)" 'fixall'
}

function Update-FixRows {
    if (-not $script:FixRowsPanel -or -not $script:State.FixReport) { return }
    $script:FixRowsPanel.SuspendLayout()
    try {
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
    } finally {
        $script:FixRowsPanel.ResumeLayout($true)
    }
}

function Add-FixRow($row) {
    $rowPanel = New-Object System.Windows.Forms.Panel
    Enable-DoubleBuffer $rowPanel
    $rowPanel.Width = $script:FixRowsPanel.ClientSize.Width - 22
    $rowPanel.Height = 44
    $rowPanel.BackColor = $Theme.card
    $rowPanel.Margin = New-Object System.Windows.Forms.Padding(3, 3, 3, 5)
    $rowPanel.Padding = New-Object System.Windows.Forms.Padding(10, 5, 10, 5)

    $status = if ($row.Ok) { 'PASS' } elseif ($row.NeedsAction) { 'FIX' } else { 'WARN' }
    $color = if ($row.Ok) { $Theme.green } elseif ($row.NeedsAction) { $Theme.red } else { $Theme.yellow }
    $badgeBg = if ($row.Ok) { [System.Drawing.Color]::FromArgb(18, 48, 32) } elseif ($row.NeedsAction) { [System.Drawing.Color]::FromArgb(52, 22, 26) } else { [System.Drawing.Color]::FromArgb(52, 40, 18) }
    $rowPanel.Tag = $color
    $rowPanel.Add_Paint({
        param($s, $e)
        try {
            $e.Graphics.DrawRectangle((Get-CachedPen $Theme.border 1), 0, 0, ($s.Width - 1), ($s.Height - 1))
            $accCol = if ($s.Tag -is [System.Drawing.Color]) { $s.Tag } else { $Theme.blue }
            $e.Graphics.FillRectangle((Get-CachedBrush $accCol), 0, 0, 3, $s.Height)
        } catch { }
    })
    $lbl = New-Lbl $status $color 8.25 22 $true
    $lbl.BackColor = $badgeBg
    $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $lbl.Location = New-Object System.Drawing.Point(12, 11)
    $lbl.Size = New-Object System.Drawing.Size(44, 22)
    $rowPanel.Controls.Add($lbl)

    $em = [char]0x2014
    $lbl2 = New-Lbl ("$($row.Label)  $em  $($row.Detail)") $Theme.text 9.25 30 $false 620
    $lbl2.Location = New-Object System.Drawing.Point(66, 7)
    $rowPanel.Controls.Add($lbl2)

    $btn = $null
    $idealBtnW = 0
    if ($row.Action) {
        $prefix = if ($row.NeedsAction) { 'Fix: ' } else { 'Info: ' }
        $btn = New-Btn ("$prefix$($row.Action)") $row.Action { FixRowAction $row.Key }
        $btn.AccessibleRole = [System.Windows.Forms.AccessibleRole]::PushButton
        $btn.Font = Get-CachedFont 'Segoe UI Semibold' 8.5 ([System.Drawing.FontStyle]::Regular)
        $tw = [System.Windows.Forms.TextRenderer]::MeasureText($btn.Text, $btn.Font).Width
        $idealBtnW = [int][math]::Max(130, [math]::Min(430, ($tw + 26)))
        $btn.Size = New-Object System.Drawing.Size($idealBtnW, 30)
        $btn.AutoEllipsis = $true
        $btn.Location = New-Object System.Drawing.Point(690, 7)
        $rowPanel.Controls.Add($btn)
    }
    $script:FixRowRefs += @{ Row = $rowPanel; Badge = $lbl; Lbl = $lbl2; Btn = $btn; IdealBtnW = $idealBtnW }
    $script:FixRowsPanel.Controls.Add($rowPanel)
}

function Layout-FixRows {
    if (-not $script:FixRowsPanel) { return }
    try {
        $availW = if ($script:FixViewport -and $script:FixViewport.ClientSize.Width -gt 50) { $script:FixViewport.ClientSize.Width } else { $script:FixRowsPanel.ClientSize.Width }
        $w = [int][math]::Max(320, ($availW - 14))
        if ($script:LblFixSummary) {
            $script:LblFixSummary.Width = $w
            $m = Measure-Text $script:LblFixSummary.Text $script:LblFixSummary.Font $w
            $script:LblFixSummary.Height = [int][math]::Max(22, ($m.Height + 6))
        }
        if ($script:FixTop) {
            $topW = [int][math]::Max(320, ($script:FixTop.ClientSize.Width - 8))
            $btnY = 54
            foreach ($c in $script:FixTop.Controls) {
                if ($c -is [System.Windows.Forms.Label] -and $c.Top -ge 24) {
                    $c.Width = $topW
                    $m = Measure-Text $c.Text $c.Font $c.Width
                    $c.Height = [int][math]::Max(20, ($m.Height + 4))
                    $btnY = $c.Top + $c.Height + 8
                }
            }
            $curX = 4
            $curY = $btnY
            $rowH = 34
            foreach ($c in $script:FixTop.Controls) {
                if ($c -is [System.Windows.Forms.Button] -and $c.Tag -is [hashtable] -and $c.Tag.ContainsKey('W')) {
                    $btnW = [int][math]::Max($c.Width, $c.Tag.W)
                    $btnH = [int]$c.Tag.H
                    if ($curX -gt 4 -and ($curX + $btnW) -gt $topW) {
                        $curX = 4
                        $curY += $rowH + 6
                    }
                    $c.Size = New-Object System.Drawing.Size($btnW, $btnH)
                    $c.Location = New-Object System.Drawing.Point($curX, $curY)
                    $curX += $btnW + 8
                }
            }
            $script:FixTop.Height = [int]($curY + $rowH + 8)
        }
        foreach ($r in $script:FixRowRefs) {
            $r.Row.Width = $w
            $btnW = 0
            if ($r.Btn) {
                $maxBtnW = [int][math]::Max(130, [math]::Floor($w * 0.42))
                $btnW = [int][math]::Min($r.IdealBtnW, $maxBtnW)
                $r.Btn.Size = New-Object System.Drawing.Size($btnW, 30)
            }
            $bxp = if ($r.Btn) { $w - $btnW - 12 } else { $w - 12 }
            $lblW = [int][math]::Max(160, ($bxp - 68))
            $r.Lbl.Width = $lblW
            $m = Measure-Text $r.Lbl.Text $r.Lbl.Font $lblW
            $lh = [int][math]::Max(24, ($m.Height + 6))
            $rh = [int][math]::Max(44, ($lh + 14))
            $r.Row.Height = $rh
            $r.Lbl.Height = $lh
            $ly = [int][math]::Max(6, (($rh - $lh) / 2))
            $r.Lbl.Location = New-Object System.Drawing.Point(64, $ly)
            if ($r.Badge) {
                $r.Badge.Location = New-Object System.Drawing.Point(12, [int][math]::Max(8, (($rh - 22) / 2)))
            }
            if ($r.Btn) {
                $byp = [int][math]::Max(6, (($rh - 30) / 2))
                $r.Btn.Location = New-Object System.Drawing.Point($bxp, $byp)
            }
            $r.Row.Invalidate()
        }
        $totH = if ($script:FixRowsPanel) { $script:FixRowsPanel.PreferredSize.Height } else { 0 }
        $script:FixRowsPanel.Size = New-Object System.Drawing.Size($w, [math]::Max(10, ($totH + 48)))
        $curScrollY = if ($script:FixScrollBar) { & $script:FixScrollBar.GetScrollY } else { 0 }
        $script:FixRowsPanel.Location = New-Object System.Drawing.Point(0, -$curScrollY)
        if ($script:FixScrollBar) { & $script:FixScrollBar.Sync }
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
    Set-ActiveNav $script:BtnMods
    $script:PageLayout = { Layout-Mods }
    if ($script:ModsPagePanel -and -not $script:ModsPagePanel.IsDisposed) {
        Switch-ContentPage $script:ModsPagePanel
        & $script:PageLayout
        Populate-ModLists
        return
    }
    $p = New-Object System.Windows.Forms.Panel
    $p.SuspendLayout()
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg
    $p.Padding = New-Object System.Windows.Forms.Padding(12, 4, 12, 4)
    Enable-DoubleBuffer $p

    $script:ModsListPanel = New-Object System.Windows.Forms.Panel
    $script:ModsListPanel.Dock = 'Fill'
    $script:ModsListPanel.BackColor = $Theme.bg
    $script:ModsListPanel.Padding = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
    Enable-DoubleBuffer $script:ModsListPanel

    $lblOn = New-Lbl 'Enabled mods (click to select)' $Theme.green 9.5 18 $true
    $lblOn.Location = New-Object System.Drawing.Point(0, 2)
    $script:ModsListPanel.Controls.Add($lblOn)
    $script:ListEnabled = New-Object System.Windows.Forms.ListBox
    $script:ListEnabled.Location = New-Object System.Drawing.Point(0, 24)
    $script:ListEnabled.Size = New-Object System.Drawing.Size(470, 280)
    $script:ListEnabled.BackColor = $Theme.card
    $script:ListEnabled.ForeColor = $Theme.text
    $script:ListEnabled.BorderStyle = 'FixedSingle'
    $script:ListEnabled.Font = Get-CachedFont 'Segoe UI' 9.25 ([System.Drawing.FontStyle]::Regular)
    $script:ListEnabled.SelectionMode = 'MultiExtended'
    $script:ListEnabled.Add_KeyDown({
        param($s, $e)
        if ($e.Control -and $e.KeyCode -eq 'A') {
            $s.BeginUpdate()
            try {
                $s.ClearSelected()
                for ($i = 0; $i -lt $s.Items.Count; $i++) { $s.SetSelected($i, $true) }
            } finally { $s.EndUpdate() }
            $e.SuppressKeyPress = $true
        }
    })

    $lblOff = New-Lbl 'Disabled mods (click to select)' $Theme.yellow 9.5 18 $true
    $lblOff.Location = New-Object System.Drawing.Point(480, 2)
    $script:ModsListPanel.Controls.Add($lblOff)
    $script:ListDisabled = New-Object System.Windows.Forms.ListBox
    $script:ListDisabled.Location = New-Object System.Drawing.Point(480, 24)
    $script:ListDisabled.Size = New-Object System.Drawing.Size(470, 280)
    $script:ListDisabled.BackColor = $Theme.card
    $script:ListDisabled.ForeColor = $Theme.text
    $script:ListDisabled.BorderStyle = 'FixedSingle'
    $script:ListDisabled.Font = Get-CachedFont 'Segoe UI' 9.25 ([System.Drawing.FontStyle]::Regular)
    $script:ListDisabled.SelectionMode = 'MultiExtended'
    $script:ListDisabled.Add_KeyDown({
        param($s, $e)
        if ($e.Control -and $e.KeyCode -eq 'A') {
            $s.BeginUpdate()
            try {
                $s.ClearSelected()
                for ($i = 0; $i -lt $s.Items.Count; $i++) { $s.SetSelected($i, $true) }
            } finally { $s.EndUpdate() }
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
    Enable-DoubleBuffer $script:ModsTop

    $head = New-Lbl 'Mod Manager' $Theme.text 13.5 26 $true
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
    $btnEnable.BackColor = $Theme.btnSuccess
    $btnEnable.FlatAppearance.MouseOverBackColor = $Theme.btnSuccessHov
    $btnEnable.FlatAppearance.BorderColor = $Theme.green
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
    $p.ResumeLayout($false)
    $script:ModsPagePanel = $p
    Switch-ContentPage $p
    & $script:PageLayout
    Populate-ModLists
    if (-not $script:State.ModsInfo) { Refresh-ModListsAsync }
}

function Populate-ModLists {
    if (-not $script:ListEnabled) { return }
    $info = $script:State.ModsInfo
    $script:ListEnabled.BeginUpdate()
    $script:ListDisabled.BeginUpdate()
    try {
        $script:ListEnabled.Items.Clear()
        $script:ListDisabled.Items.Clear()
        if (-not $info) {
            [void]$script:ListEnabled.Items.Add('(loading mods...)')
            return
        }
        foreach ($f in @($info.Enabled)) { [void]$script:ListEnabled.Items.Add(("{0}  ({1:N1} MB)" -f $f.Name, ($f.Length / 1MB))) }
        foreach ($f in @($info.Disabled)) { [void]$script:ListDisabled.Items.Add($f.Name) }
    } finally {
        $script:ListEnabled.EndUpdate()
        $script:ListDisabled.EndUpdate()
    }
    Add-Log "[INFO] Mods: $(@($info.Enabled).Count) enabled, $(@($info.Disabled).Count) disabled."
}

function Refresh-ModListsAsync {
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.ModsInfo = Get-ModsInfo" 'modslist'
}

function Layout-Mods {
    if (-not $script:ModsListPanel) { return }
    try {
        $topW = [int][math]::Max(320, ($script:ModsTop.ClientSize.Width - 8))
        $btnY = 54
        foreach ($c in $script:ModsTop.Controls) {
            if ($c -is [System.Windows.Forms.Label] -and $c.Location.Y -ge 24) {
                $c.Width = $topW
                $m = Measure-Text $c.Text $c.Font $c.Width
                $c.Height = [int][math]::Max(20, ($m.Height + 4))
                $btnY = $c.Location.Y + $c.Height + 8
            }
        }
        $curX = 4
        $curY = $btnY
        $rowH = 32
        foreach ($c in $script:ModsTop.Controls) {
            if ($c -is [System.Windows.Forms.Button] -and $c.Tag -is [hashtable] -and $c.Tag.ContainsKey('W')) {
                $btnW = [int][math]::Max($c.Width, $c.Tag.W)
                $btnH = [int]$c.Tag.H
                if ($curX -gt 4 -and ($curX + $btnW) -gt $topW) {
                    $curX = 4
                    $curY += $rowH + 6
                }
                $c.Size = New-Object System.Drawing.Size($btnW, $btnH)
                $c.Location = New-Object System.Drawing.Point($curX, $curY)
                $curX += $btnW + 6
            }
        }
        $script:ModsTop.Height = [int]($curY + $rowH + 8)
        $w = [int][math]::Max(320, $script:ModsListPanel.ClientSize.Width)
        $h = $script:ModsListPanel.ClientSize.Height
        $tipH = 24
        if ($script:ModsTip) {
            $tm = Measure-Text $script:ModsTip.Text $script:ModsTip.Font $w
            $tipH = [int][math]::Max(24, ($tm.Height + 6))
            $script:ModsTip.Height = $tipH
        }
        $colW = [int][math]::Max(140, (($w - 10) / 2))
        $listH = [int][math]::Max(60, ($h - 32 - $tipH))
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
    Set-ActiveNav $script:BtnTransfer
    $script:PageLayout = { Update-CardStackLayout }
    if ($script:TransferPagePanel -and -not $script:TransferPagePanel.IsDisposed) {
        $script:StackRefs = $script:TransferStackRefs
        Switch-ContentPage $script:TransferPagePanel
        Update-CardStackLayout
        return
    }
    $p = New-Object System.Windows.Forms.Panel
    $p.SuspendLayout()
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg
    Enable-DoubleBuffer $p

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
    $script:CmbChunkSize.ForeColor = $Theme.text
    $script:CmbChunkSize.FlatStyle = 'Flat'
    $script:CmbChunkSize.Font = Get-CachedFont 'Segoe UI' 9.5 ([System.Drawing.FontStyle]::Regular)
    [void]$script:CmbChunkSize.Items.AddRange(@('5GB', '10GB', '15GB', '20GB', '25GB'))
    $script:CmbChunkSize.SelectedIndex = 2
    Add-Row $card 'Max folder size' $script:CmbChunkSize

    $barE = New-ButtonBar
    $btnExport = New-Btn 'Export Server Mods' 'Copies every .zip into Export\Part_1, Part_2... inside your selected destination so each folder stays under the chosen size. Uses Copy-Item only - your live mods stay untouched.' { Start-TransferExport }
    $btnExport.Size = New-Object System.Drawing.Size(170, 34)
    $btnExport.BackColor = $Theme.btnAct
    $btnExport.FlatAppearance.BorderColor = $Theme.blue
    $barE.Controls.Add($btnExport)
    Add-RowFull $card $barE

    $bar2 = New-ButtonBar
    $btnDrive = New-Btn 'Upload to Google Drive (15GB)' 'Opens Google Drive in your browser - drag the Export parts that fit 15GB into it.' { Start-Process 'https://drive.google.com/drive/my-drive' }
    $btnDrive.Size = New-Object System.Drawing.Size(215, 34)
    $bar2.Controls.Add($btnDrive)
    $btnMega = New-Btn 'Upload to Mega.io (20GB Free)' 'Opens Mega.io in your browser - drag the Export parts that fit 20GB into it.' { Start-Process 'https://mega.io/' }
    $btnMega.Size = New-Object System.Drawing.Size(215, 34)
    $bar2.Controls.Add($btnMega)
    Add-RowFull $card $bar2

    Add-RowNote $card 'An "Export" folder with Part_1, Part_2, ... is created inside your selected destination. Mods are COPIED, never moved or unzipped.' $Theme.dim | Out-Null
    $cards += $card

    $card = New-Card 'Player tools - install downloaded mods' 'Moves every .zip from a folder you pick into the BeamMP client mods folder. All other file types are ignored.'
    $script:LblClientDir = New-Lbl 'Client mods folder: (scan to find it)' $Theme.dim 9 20
    $script:LblClientDir.AutoSize = $true
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
    $script:ClbClientMods.ForeColor = $Theme.text
    $script:ClbClientMods.BorderStyle = 'FixedSingle'
    $script:ClbClientMods.Font = Get-CachedFont 'Segoe UI' 9 ([System.Drawing.FontStyle]::Regular)
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
    $btnDelete.BackColor = $Theme.btnDanger
    $btnDelete.FlatAppearance.BorderColor = $Theme.btnDangerBorder
    $btnDelete.FlatAppearance.MouseOverBackColor = $Theme.btnDangerHov
    $btnDelete.ForeColor = [System.Drawing.Color]::White
    $bar.Controls.Add($btnDelete)
    Add-RowFull $card $bar
    Add-RowNote $card 'Refreshing the list never deletes anything - files are only removed when you tick them and press "Delete Selected Mods".' $Theme.dim | Out-Null
    $cards += $card

    & $script:MountCards $cards $stack.Content
    $p.ResumeLayout($false)
    $script:TransferStackRefs = $script:StackRefs
    $script:TransferPagePanel = $p
    Switch-ContentPage $p
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
    Update-CardStackLayout
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
    Update-CardStackLayout
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
    $script:ClbClientMods.BeginUpdate()
    try {
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
    } finally {
        $script:ClbClientMods.EndUpdate()
    }
    Update-CardStackLayout
    Add-Log "[INFO] Client mods: $(@($info.Mods).Count) .zip file(s) installed."
}

function Set-ClientModChecks([bool]$On) {
    if (-not $script:ClbClientMods) { return }
    $script:ClbClientMods.BeginUpdate()
    try {
        for ($i = 0; $i -lt $script:ClbClientMods.Items.Count; $i++) { $script:ClbClientMods.SetItemChecked($i, $On) }
    } finally {
        $script:ClbClientMods.EndUpdate()
    }
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
function Add-GuideSpan([string]$Text, [string]$Color = 'text', [bool]$Bold = $false, [float]$Size = 10, [int]$Indent = 18, [int]$HangingIndent = 0) {
    if (-not $script:GuideBox) { return }
    if (-not $script:GuideBox.IsHandleCreated) { [void]$script:GuideBox.Handle }
    $script:GuideBox.SelectionStart = $script:GuideBox.TextLength
    $script:GuideBox.SelectionLength = 0
    $script:GuideBox.SelectionIndent = $Indent
    $script:GuideBox.SelectionHangingIndent = $HangingIndent
    $script:GuideBox.SelectionRightIndent = 16
    $script:GuideBox.SelectionColor = $(if ($Color -eq 'white') { [System.Drawing.Color]::White } else { $Theme[$Color] })
    $script:GuideBox.SelectionFont = Get-CachedFont 'Segoe UI' $Size $(if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular })
    $script:GuideBox.AppendText($Text)
}

function Add-GuideSection([string]$StepNum, [string]$Title, [string]$Subtitle = '', [bool]$First = $false) {
    if (-not $First) {
        Add-GuideSpan ([Environment]::NewLine) 'dim' $false 6 0 0
        $rule = ([string][char]0x2500) * 76
        Add-GuideSpan ($rule + [Environment]::NewLine) 'borderHi' $false 8.5 0 0
        Add-GuideSpan ([Environment]::NewLine) 'dim' $false 4 0 0
    }
    Add-GuideSpan ("STEP $StepNum") 'blue' $true 11 0 0
    Add-GuideSpan ("   $([char]0x2014)   " + $Title + [Environment]::NewLine) 'white' $true 12 0 0
    if ($Subtitle) {
        Add-GuideSpan ($Subtitle + [Environment]::NewLine) 'dim' $false 9.25 0 0
    }
    Add-GuideSpan ([Environment]::NewLine) 'dim' $false 4 0 0
}

function Add-GuidePara([string]$LeadBold, [string]$Body, [string]$LeadColor = 'text') {
    if ($LeadBold) {
        Add-GuideSpan ($LeadBold + ' ') $LeadColor $true 9.75 16 0
        Add-GuideSpan ($Body + [Environment]::NewLine) 'textSec' $false 9.75 16 0
    } else {
        Add-GuideSpan ($Body + [Environment]::NewLine) 'textSec' $false 9.75 16 0
    }
    Add-GuideSpan ([Environment]::NewLine) 'dim' $false 3 16 0
}

function Add-GuideBullet([string]$LeadBold, [string]$Body, [string]$BulletColor = 'blue', [string]$LeadColor = 'text') {
    $bullet = " $([char]0x25B8)   "
    Add-GuideSpan $bullet $BulletColor $true 9.75 20 18
    if ($LeadBold) {
        Add-GuideSpan ($LeadBold + "  $([char]0x2014)  ") $LeadColor $true 9.75 20 18
    }
    Add-GuideSpan ($Body + [Environment]::NewLine) 'textSec' $false 9.75 20 18
    Add-GuideSpan ([Environment]::NewLine) 'dim' $false 2 20 0
}

function Add-GuideCallout([string]$Badge, [string]$Body, [string]$Color = 'yellow') {
    Add-GuideSpan (" $([char]0x25CF)  $Badge :  ") $Color $true 9.5 16 0
    Add-GuideSpan ($Body + [Environment]::NewLine) 'text' $false 9.5 16 0
    Add-GuideSpan ([Environment]::NewLine) 'dim' $false 4 16 0
}

function Show-GuidePage {
    Set-ActiveNav $script:BtnMore
    $script:PageLayout = $null
    if ($script:GuidePagePanel -and -not $script:GuidePagePanel.IsDisposed) {
        Switch-ContentPage $script:GuidePagePanel
        return
    }
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg
    Enable-DoubleBuffer $p

    $top = New-PageTop $p "Guide & Walkthrough" 'Step-by-step reference for hosting, connecting friends, mods, and troubleshooting.'
    $btnJumpFix = New-Btn 'Scan & Fix (^F)' 'Jump to Scan & Fix diagnostics.' { Show-FixPage }
    $btnJumpFix.Size = New-Object System.Drawing.Size(116, 32)
    $btnJumpNet = New-Btn 'Network (^V)' 'Jump to Network & Tunnels (FRP & VPNs).' { Show-NetworkPage }
    $btnJumpNet.Size = New-Object System.Drawing.Size(106, 32)
    $btnJumpMods = New-Btn 'Mods (^M)' 'Jump to Mod Manager.' { Show-ModsPage }
    $btnJumpMods.Size = New-Object System.Drawing.Size(92, 32)
    $btnJumpSet = New-Btn 'Settings (^T)' 'Jump to Server Settings.' { Show-SettingsPage }
    $btnJumpSet.Size = New-Object System.Drawing.Size(104, 32)
    $top.Flow.Controls.Add($btnJumpFix)
    $top.Flow.Controls.Add($btnJumpNet)
    $top.Flow.Controls.Add($btnJumpMods)
    $top.Flow.Controls.Add($btnJumpSet)
    $p.Controls.Add($top.Bar)

    $guideWrap = New-Object System.Windows.Forms.Panel
    $guideWrap.Dock = 'Fill'
    $guideWrap.BackColor = $Theme.bg
    $guideWrap.Padding = New-Object System.Windows.Forms.Padding(16, 10, 16, 8)
    Enable-DoubleBuffer $guideWrap
    $p.Controls.Add($guideWrap)
    $guideWrap.BringToFront()

    $script:GuideCard = New-Object System.Windows.Forms.Panel
    $script:GuideCard.Dock = 'Fill'
    $script:GuideCard.BackColor = $Theme.card
    $script:GuideCard.Padding = New-Object System.Windows.Forms.Padding(24, 18, 20, 16)
    Enable-DoubleBuffer $script:GuideCard
    $script:GuideCard.Add_SizeChanged({ $this.Invalidate() })
    $script:GuideCard.Add_Paint({
        param($s, $e)
        try {
            $pen = Get-CachedPen $Theme.border 1
            $e.Graphics.DrawRectangle($pen, 0, 0, ($s.Width - 1), ($s.Height - 1))
            $penHi = Get-CachedPen $Theme.borderHi 1
            $e.Graphics.DrawLine($penHi, 1, 0, ($s.Width - 2), 0)
            $e.Graphics.FillRectangle((Get-CachedBrush $Theme.blue), 0, 14, 3, 24)
        } catch { }
    })
    $guideWrap.Controls.Add($script:GuideCard)

    $script:GuideBox = New-Object System.Windows.Forms.RichTextBox
    $script:GuideBox.ReadOnly = $true
    $script:GuideBox.DetectUrls = $false
    $script:GuideBox.BackColor = $Theme.card
    $script:GuideBox.ForeColor = $Theme.text
    $script:GuideBox.BorderStyle = 'None'
    $script:GuideBox.WordWrap = $true
    $script:GuideBox.ScrollBars = 'Vertical'
    $script:GuideBox.Dock = 'Fill'
    $script:GuideBox.Font = Get-CachedFont 'Segoe UI' 10 ([System.Drawing.FontStyle]::Regular)
    [void]$script:GuideBox.Handle
    $script:GuideBox.ZoomFactor = 1.0
    $script:GuideCard.Controls.Add($script:GuideBox)

    # --- STEP 01 ---
    Add-GuideSection '01' 'START THE SERVER' 'Get your server online and test it on your own PC in under a minute.' $true
    Add-GuideBullet 'Launch the Tool' 'Double-click Start_Here.bat to open the Dashboard (Ctrl+H), which displays live server telemetry and every address your friends can use.' 'green'
    Add-GuideBullet 'First-Time AuthKey' 'On your first launch, get a free server key at https://keymaster.beammp.com, paste it into the prompt, and click Save. It is stored privately on your PC.' 'green'
    Add-GuideBullet 'Start & Join' 'Click Start Server (Ctrl+S) in the top-left sidebar. BeamMP Launcher opens automatically. In BeamNG.drive, open More... -> BeamMP -> Direct Connect and use the "THIS PC (Loopback)" address.' 'green'

    # --- STEP 02 ---
    Add-GuideSection '02' 'HOW YOUR FRIENDS CONNECT' 'Pick the right Direct Connect address on the Dashboard for your friends.'
    Add-GuidePara 'How to join:' 'Send your friend ONE address from the Dashboard. In BeamNG.drive they open More... -> BeamMP -> Direct Connect and paste that address:'
    Add-GuideBullet 'THIS PC (Loopback)' '127.0.0.1:30814 - only for you when testing or playing on the same machine hosting the server.' 'blue' 'green'
    Add-GuideBullet 'Friends (Same WiFi / LAN)' 'For anyone connected to your home router or local WiFi network.' 'blue'
    Add-GuideBullet 'Friends (FRP Tunnel)' 'Works from anywhere over the internet without router port forwarding (configure in Network & Tunnels).' 'blue'
    Add-GuideBullet 'Friends (VPN / Tailscale / Playit)' 'Works from anywhere, even behind ISP CGNAT where port forwarding is impossible.' 'blue'
    Add-GuideBullet 'Anyone (Internet / WAN)' 'Direct public IP connection - requires UDP/TCP port 30814 forwarded on your router.' 'blue'
    Add-GuideCallout 'IMPORTANT' 'Never click your own server in the public BeamMP server list from inside your own home network (NAT loopback will fail). Always join your own server using Direct Connect with 127.0.0.1:30814.' 'yellow'

    # --- STEP 03 ---
    Add-GuideSection '03' 'PUBLIC vs. PRIVATE SERVER' 'Control whether strangers see your server in the public BeamMP browser.'
    Add-GuideBullet 'PUBLIC Visibility' 'Lists your server in the public BeamMP Server Browser so anyone can search for its name and join.' 'green' 'green'
    Add-GuideBullet 'PRIVATE Visibility' 'Hides your server from the public list. Only people you send the Direct Connect IP:Port to can join (applies on next server start).' 'yellow' 'yellow'
    Add-GuideCallout 'ONE-CLICK INVITE' 'On the Dashboard, click "Copy Invite Message" to copy a ready-to-paste Discord/chat invite with your server address and step-by-step connection instructions.' 'blue'

    # --- STEP 04 ---
    Add-GuideSection '04' 'CANNOT CONNECT? RUN SCAN & FIX' 'Automated diagnostics for keys, ports, firewall rules, CGNAT, and mods.'
    Add-GuideBullet 'Full Health Check' 'Open Scan & Fix (Ctrl+F) to inspect your AuthKey, port 30814, Windows Firewall rules, mod integrity, disk space, VPN adapters, and ISP CGNAT status.' 'blue'
    Add-GuideBullet 'One-Click Repair' 'Click "Fix All Possible" to automatically free stuck ports, add Windows Firewall rules, repair broken map paths, and attempt UPnP port mapping.' 'green'
    Add-GuideCallout 'CGNAT NOTICE' 'If Scan & Fix reports that your ISP uses CGNAT, router port forwarding can never work. Use the FRP Tunnel, Playit.gg, or a VPN in the Network & Tunnels tab instead.' 'yellow'

    # --- STEP 05 ---
    Add-GuideSection '05' 'MOD MANAGER' 'Add, scan, enable, or disable vehicle and map .zip mods.'
    Add-GuideBullet 'Drag & Drop Install' 'Open Mod Manager (Ctrl+M) and drag .zip mod files directly onto the lists. Every zip is automatically scanned for dangerous executables (.exe, .vbs, .cmd, .scr) before being added.' 'blue'
    Add-GuideBullet 'Automatic Player Sync' 'All enabled .zip mods in Resources\Client are automatically downloaded by players when they join your server.' 'green'
    Add-GuideBullet 'Multi-Select Controls' 'Use Ctrl+Click to pick individual mods, Shift+Click to select a range, or Ctrl+A to select all, then click Enable or Disable Selected.' 'blue'

    # --- STEP 06 ---
    Add-GuideSection '06' 'SERVER SETTINGS, MAPS & PRESETS' 'Customize your server name, player/car caps, active map, and saved presets.'
    Add-GuideBullet 'Server Configuration' 'Open Server Settings (Ctrl+T) to edit your server name, max players, max cars per player, description, tags, port, and visibility. Click "Save All Settings" at the top right.' 'blue'
    Add-GuideBullet 'Map Picker & Search' 'Filter maps using the search box, pick a vanilla or modded map, and click "Apply Selected Map".' 'green'
    Add-GuideBullet 'Saved Presets' 'Save your entire configuration plus currently enabled mods under a preset name (e.g. "Drift Night" or "Track Day") and switch setups in one click.' 'blue'
    Add-GuideCallout 'WARNING' 'Never change the map from inside BeamNG.drive while hosting - it breaks the BeamMP multiplayer state. Always change maps from Server Settings.' 'red'

    # --- STEP 07 ---
    Add-GuideSection '07' 'NETWORK: FRP TUNNEL & VPN TOOLS' 'Host for friends anywhere without touching your router.'
    Add-GuideBullet 'FRP Tunnel (No Port Forward)' 'Open Network & Tunnels (Ctrl+V), click "FRP Setup Guide", enter your frps server address, port (usually 7000), and token, tick "Enable FRP Tunnel", and start your server.' 'blue'
    Add-GuideBullet 'Playit.gg & VPNs' 'Manage Playit.gg, Tailscale, Radmin VPN, ZeroTier, and Hamachi from dedicated rows with one-click Start, Stop, Download, and Copy IP actions.' 'green'
    Add-GuideCallout 'VPN TIP' 'When using a VPN (Tailscale, Radmin, ZeroTier, Hamachi), your friends must have the same VPN app installed and joined to your virtual network.' 'yellow'

    # --- STEP 08 ---
    Add-GuideSection '08' 'SHARING THE FOLDER SAFELY' 'Wipe private keys and logs before zipping or sharing this tool.'
    Add-GuideBullet 'Clean Personal Info' 'Click More Tools -> Clean Personal Info to erase your AuthKey, Discord webhook, logs, backups, and cached IPs so the folder is 100% safe to zip and share.' 'red'
    Add-GuideCallout 'SECURITY' 'Never share your private AuthKey or Discord webhook URL with anyone.' 'red'

    # --- STEP 09 ---
    Add-GuideSection '09' 'AUTOMATIC UPDATES & LOST WINDOWS' 'Keep K BNG M Hoster up to date and restore minimized windows.'
    Add-GuideBullet 'GitHub Auto-Updater' 'On launch, the app checks GitHub for new releases and offers a one-click update while keeping all your mods, keys, presets, and settings intact.' 'green'
    Add-GuideBullet 'Restore Minimized Windows' 'The BeamMP-Server console opens minimized on purpose. Open More Tools -> Extra & Windows (Ctrl+E) anytime and click "Show Window" to bring it to the front.' 'blue'
    Add-GuideBullet 'One-Click Issue Report' 'In Extra & Windows (Ctrl+E), click "Submit Issue" to copy a diagnostic summary to your clipboard and open the GitHub Issues page.' 'blue'

    $script:GuideBox.SelectionStart = 0
    $script:GuideBox.ScrollToCaret()
    $script:GuidePagePanel = $p
    Switch-ContentPage $p
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
    Set-ActiveNav $script:BtnMore
    $script:PageLayout = { Update-CardStackLayout }
    if ($script:ExtraPagePanel -and -not $script:ExtraPagePanel.IsDisposed) {
        $script:StackRefs = $script:ExtraStackRefs
        Switch-ContentPage $script:ExtraPagePanel
        Refresh-WinRows
        Update-CardStackLayout
        return
    }
    $p = New-Object System.Windows.Forms.Panel
    $p.SuspendLayout()
    $p.Dock = 'Fill'
    $p.BackColor = $Theme.bg
    Enable-DoubleBuffer $p

    $top = New-PageTop $p 'Extra' 'Open windows (restore them from here) and problem reporting.'
    $p.Controls.Add($top.Bar)

    $stack = New-CardStack $p
    $cards = @()

    $card = New-Card 'Windows opened by the tool' 'The server console opens minimized on purpose - restore it from this list anytime.'
    $script:WinRows = New-Object System.Windows.Forms.Panel
    $script:WinRows.AutoSize = $false
    $script:WinRows.Height = 28
    $script:WinRows.BackColor = $Theme.card
    Enable-DoubleBuffer $script:WinRows
    Add-RowFull $card $script:WinRows
    $cards += $card

    $card = New-Card 'Report a problem' 'Copies a ready-made report to your clipboard and opens the GitHub issues page - you review and paste it yourself.'
    $issueBar = New-ButtonBar
    $btnIssue = New-Btn 'Submit issue (copies report, opens GitHub)' 'One press: copies the diagnostic report to your clipboard and opens the GitHub issues page - you just paste it there.' { Submit-Issue }
    $btnIssue.Size = New-Object System.Drawing.Size(330, 38)
    $btnIssue.BackColor = $Theme.btnDanger
    $btnIssue.FlatAppearance.MouseOverBackColor = $Theme.btnDangerHov
    $btnIssue.FlatAppearance.BorderColor = $Theme.btnDangerBorder
    $btnIssue.ForeColor = [System.Drawing.Color]::White
    $issueBar.Controls.Add($btnIssue)
    Add-RowFull $card $issueBar
    $script:IssueLog = New-Lbl '(activity appears here)' $Theme.dim 8.5 30
    $script:IssueLog.AutoSize = $true
    Add-RowFull $card $script:IssueLog
    $cards += $card

    & $script:MountCards $cards $stack.Content
    $p.ResumeLayout($false)
    $script:ExtraStackRefs = $script:StackRefs
    $script:ExtraPagePanel = $p
    Switch-ContentPage $p
    Refresh-WinRows
}

# Rebuilds the window list rows inside the Extra page.
function Refresh-WinRows {
    if (-not $script:WinRows) { return }
    $script:WinRows.SuspendLayout()
    try {
        $oldRows = @($script:WinRows.Controls)
        $script:WinRows.Controls.Clear()
        foreach ($oc in $oldRows) { try { $oc.Dispose() } catch { } }
        $wins = Get-ToolWindows
        $rows = @()
        if (-not $wins.Count) {
            $lbl = New-Lbl 'No tool windows are open right now. (Start the server and the list appears here.)' $Theme.dim 9 20
            $lbl.AutoSize = $true
            $rows += $lbl
            $script:WinRows.Height = 28
        } else {
            foreach ($w in $wins) {
                $row = New-Object System.Windows.Forms.Panel
                $row.Dock = 'Top'
                $row.Height = 42
                $row.BackColor = $Theme.panel
                $row.Padding = New-Object System.Windows.Forms.Padding(10, 4, 10, 4)
                Enable-DoubleBuffer $row
                $lbl = New-Lbl $w.Name $Theme.text 9 20
                $lbl.AutoSize = $false
                $lbl.Dock = 'Fill'
                $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
                $lbl.AutoEllipsis = $true
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
            $script:WinRows.Height = ($rows.Count * 42)
        }
        for ($i = $rows.Count - 1; $i -ge 0; $i--) { $script:WinRows.Controls.Add($rows[$i]) }
    } catch { Write-Log "[LAYOUT-ERROR] WINROWS $($_.Exception.Message)" }
    finally { $script:WinRows.ResumeLayout($true) }
    Update-CardStackLayout
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
    Update-CardStackLayout
}

# ---------------------------------------------------------------------------------------
# DIALOGS
# ---------------------------------------------------------------------------------------
$LicenseFullText = @'
PROPRIETARY LICENSE AGREEMENT (EULA)
Product: K BNG M Hoster
Licensor / Copyright Holder: Kinan (@kinan_sx240)
Copyright (c) 2026 Kinan. All Rights Reserved.

IMPORTANT --- READ CAREFULLY: BY DOWNLOADING, INSTALLING, ACCESSING, OR USING THE
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
1.3 "Licensor" means Kinan (@kinan_sx240), the copyright holder and creator.
    "Licensee" means any person or entity that downloads, installs, accesses,
    or uses the Software.

2. LICENSE GRANT --- LIMITED USE
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
    and the handle @kinan_sx240).
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
    $box.ForeColor = $Theme.textSec
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
    $accept.BackColor = $Theme.btnSuccess
    $accept.FlatAppearance.MouseOverBackColor = $Theme.btnSuccessHov
    $accept.FlatAppearance.BorderColor = $Theme.green
    $accept.Enabled = $false
    $dlg.Controls.Add($accept)

    $decline = New-Btn 'Decline / Exit' 'Decline the license and close K BNG M Hoster immediately.' { [System.Windows.Forms.Application]::Exit() }
    $decline.Size = New-Object System.Drawing.Size(150, 36)
    $decline.Location = New-Object System.Drawing.Point(170, 616)
    $decline.ForeColor = [System.Drawing.Color]::White
    $decline.BackColor = $Theme.btnDanger
    $decline.FlatAppearance.MouseOverBackColor = $Theme.btnDangerHov
    $decline.FlatAppearance.BorderColor = $Theme.btnDangerBorder
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
# Set $script:EnableLicenseGate = $true to re-enable the startup license check.
# ---------------------------------------------------------------------------------------
$script:EnableLicenseGate = $true
$script:LicenseLocked = $true
$script:LicenseSavedStates = @{}
$script:LicenseLocalVersion = ''
$script:LicenseRemoteVersion = $null
$script:LicenseCheckDone = $false
$script:LicensePs = $null
$script:LicenseHandle = $null
$script:FrpInitPs = $null
$script:FrpInitHandle = $null

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
        if (-not $script:LicenseSavedStates) { $script:LicenseSavedStates = @{} }
        foreach ($c in @(Get-AllControls $script:Form)) {
            if ($c -is [System.Windows.Forms.Button]) {
                if (-not $script:LicenseSavedStates.ContainsKey($c)) {
                    $script:LicenseSavedStates[$c] = $c.Enabled
                }
                $c.Enabled = $false
                $c.Invalidate()
            }
        }
    } else {
        foreach ($k in @($script:LicenseSavedStates.Keys)) {
            try { $k.Enabled = $script:LicenseSavedStates[$k]; $k.Invalidate() } catch { }
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
    $r = Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/Kinan0713/K-BNG-M-Hoster/main/license_version.txt' -TimeoutSec 2 -ErrorAction Stop
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

# One-time FRP setup (zip extract + "frpc.exe -v" probe) in its own runspace.
# Started from Form.Add_Shown so it can only run AFTER the window is painted.
# The extract lock file inside Initialize-FrpBinary makes it race-safe with any
# core runspace that initializes it on demand.
function Start-FrpInitAsync {
    $script:FrpInitPs = [powershell]::Create()
    $null = $script:FrpInitPs.AddScript($script:CoreText)
    $null = $script:FrpInitPs.AddScript('$null = Initialize-FrpBinary')
    $script:FrpInitHandle = $script:FrpInitPs.BeginInvoke()
}

function Finish-LicenseGate {
    $script:LicenseCheckDone = $true
    try {
        $remote = [string]$script:LicenseRemoteVersion
        $local = [string]$script:LicenseLocalVersion

        # First run (no accepted license on this computer): always present the
        # interactive license prompt. A missing remote version (offline / blocked
        # / transient network failure) must never hard-lock a brand-new user out.
        if (-not $local) {
            if (-not $remote) {
                Add-Log '[INFO] Offline first run - remote license version unavailable, presenting agreement for local acceptance.'
            } else {
                Add-Log "[INFO] License version $remote required (accepted: none)."
            }
            if (Show-EulaDialog) {
                # Record a version even when offline ('0' = accepted, unverified)
                # so the user stays unlocked on subsequent offline launches.
                $stored = if ($remote) { $remote } else { '0' }
                Save-LocalLicenseVersion $stored
                $script:LicenseLocalVersion = $stored
                Set-LicenseLock $false
                Add-Log '[INFO] License accepted - all controls unlocked.'
            } else {
                [System.Windows.Forms.Application]::Exit()
            }
            return
        }

        # Returning user: only re-prompt when the remote version is newer.
        if (Test-LicenseNeedsAccept $local $remote) {
            Add-Log "[INFO] License version $remote required (accepted: $local)."
            if (Show-EulaDialog) {
                Save-LocalLicenseVersion $remote
                $script:LicenseLocalVersion = $remote
                Set-LicenseLock $false
                Add-Log '[INFO] License accepted - all controls unlocked.'
            } else {
                [System.Windows.Forms.Application]::Exit()
            }
            return
        }

        # Previously accepted and no newer remote version (including offline):
        # pass straight through.
        Set-LicenseLock $false
        Add-Log "[INFO] License check passed (version $local)."
    } catch {
        # Never let a transient network/state problem crash initialization.
        # Fail open so the UI always comes up.
        try { Add-Log "[WARN] License check failed: $($_.Exception.Message)" } catch { }
        try { Set-LicenseLock $false } catch { }
    }
}

function Start-LicenseGate {
    if (-not $script:EnableLicenseGate) {
        $script:LicenseLocked = $false
        $script:LicenseCheckDone = $true
        Update-BusyUi
        return
    }
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

    $txtAuthKey = New-Object System.Windows.Forms.TextBox
    $txtAuthKey.Location = New-Object System.Drawing.Point(14, 118)
    $txtAuthKey.Size = New-Object System.Drawing.Size(570, 26)
    $txtAuthKey.BackColor = $Theme.panel
    $txtAuthKey.ForeColor = [System.Drawing.Color]::White
    $txtAuthKey.BorderStyle = 'FixedSingle'
    $dlg.Controls.Add($txtAuthKey)

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
        $entered = $txtAuthKey.Text.Trim().Trim('"', "'")
        $private = [bool]$script:isPrivate -or (Get-ServerPrivate)
        # "0" is always a valid server key (Keymaster auth skipped). A blank
        # key is valid for private servers too. Any other non-empty string is
        # accepted as-is (custom keys must never be rejected) - only line
        # breaks / control characters are refused because they would corrupt
        # the config file.
        if ($entered -eq '0' -or ($private -and -not $entered) -or ($entered -and $entered -notmatch '[\x00-\x1F]')) {
            $txtAuthKey.Text = $entered
            $txtAuthKey.BackColor = [System.Drawing.Color]::FromArgb(34, 92, 44)
            # Explicitly commits the textbox value + the current Private toggle
            # state to ServerConfig.toml on THIS Save click.
            $r = Save-AuthConfig -AuthKey $txtAuthKey.Text -Private $private
            if ($chk.Checked) {
                $port = New-SetupConfig
                $lblResult.Text = "$($r.Message)  Server settings applied (port $port)."
            } else {
                $lblResult.Text = $r.Message
            }
            $lblResult.ForeColor = $Theme.green
            $dlg.DialogResult = 'OK'
            return
        }
        $txtAuthKey.BackColor = $Theme.panel
        $lblResult.Text = "The key cannot contain line breaks or control characters. Any other key text is accepted - or type 0 for a private server."
        $lblResult.ForeColor = $Theme.red
    }
    $save.Size = New-Object System.Drawing.Size(110, 36)
    $save.Location = New-Object System.Drawing.Point(14, 250)
    $save.BackColor = $Theme.btnSuccess
    $save.FlatAppearance.MouseOverBackColor = $Theme.btnSuccessHov
    $save.FlatAppearance.BorderColor = $Theme.green
    $dlg.Controls.Add($save)

    $skip = New-Btn 'Skip for now' 'Continue without a key. You can set it up later in Settings.' { $dlg.DialogResult = 'Cancel' }
    $skip.Size = New-Object System.Drawing.Size(110, 36)
    $skip.Location = New-Object System.Drawing.Point(130, 250)
    $dlg.Controls.Add($skip)

    $note = New-Lbl 'Any non-empty key text is accepted (letters, numbers, dashes, custom strings). For a private server, type 0 (or leave empty) - Keymaster authentication is skipped.' $Theme.dim 8.5 44  $false 570
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

    # Launch click commits the toggle state from $script:isPrivate straight to
    # ServerConfig.toml (one-way write - nothing reads back into the toggle).
    $null = Save-AuthConfig -Private ([bool]$script:isPrivate) -AuthKey (Get-ConfigValue 'AuthKey')

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
    $script:BtnStart.Invalidate()
    Refresh-Dashboard
    Add-Log "===== Starting the server ====="
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.Pre = Get-ConnectionInfo" 'precheck'
}

function Continue-StartFlow {
    $script:Starting = $false
    $script:BtnStart.Text = "$([char]0x25B6)  Start Server"
    $script:BtnStart.Enabled = -not $script:State.Running
    $script:BtnStart.Invalidate()
    Update-BusyUi
    Refresh-Dashboard
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
    $script:BtnStart.Invalidate()
    $script:BtnStop.Invalidate()
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
    if ($script:StreamerMode) {
        Add-Log "[NOTE] Clipboard copy blocked: Sensitive endpoint is masked while Streamer Privacy Mode is active."
        return
    }
    $conn = $script:State.Conn
    if (-not $conn) {
        $conn = [pscustomobject]@{ Port = (Get-ServerPort); LAN = (Get-LanIp); Tailscale = ''; Public = ''; Vpn = @(); Cgnat = $false }
    }
    $port = if ($script:State -and $script:State.Port -and $script:State.Port -gt 0) { $script:State.Port } elseif ($conn -and $conn.Port) { $conn.Port } else { Get-ServerPort }
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
    if ($script:StreamerMode) {
        Add-Log "[NOTE] Clipboard copy blocked: Server invite is protected while Streamer Privacy Mode is active."
        return
    }
    $conn = $script:State.Conn
    if (-not $conn) {
        $conn = [pscustomobject]@{ Port = (Get-ServerPort); LAN = (Get-LanIp); Tailscale = ''; Public = ''; Vpn = @(); Cgnat = $false }
    }
    $port = if ($script:State -and $script:State.Port -and $script:State.Port -gt 0) { $script:State.Port } elseif ($conn -and $conn.Port) { $conn.Port } else { Get-ServerPort }
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
    $logBatch = $null
    while ($script:Queue.TryDequeue([ref]$line)) {
        if (-not $logBatch) { $logBatch = New-Object 'System.Collections.Generic.List[string]' }
        $logBatch.Add($line)
    }
    if ($logBatch -and $logBatch.Count -gt 0) { Add-LogBatch $logBatch.ToArray() }

    if ($script:FrpInitHandle -and $script:FrpInitHandle.IsCompleted) {
        try { $null = $script:FrpInitPs.EndInvoke($script:FrpInitHandle) } catch { }
        try { $script:FrpInitPs.Dispose() } catch { }
        $script:FrpInitPs = $null
        $script:FrpInitHandle = $null
    }

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
            'settings' {
                $script:LblSettingsResult.Text = 'Settings saved.'
                $script:LblSettingsResult.ForeColor = $Theme.green
                Refresh-SettingsFields
                Refresh-Dashboard
            }
            'setport' {
                $newPort = Get-ServerPort
                $script:State.Port = $newPort
                if ($script:State.Conn) { $script:State.Conn.Port = $newPort }
                if ($script:LblSettingsResult) { $script:LblSettingsResult.Text = "Port changed to $newPort."; $script:LblSettingsResult.ForeColor = $Theme.green }
                Refresh-SettingsFields
                Refresh-Dashboard
            }
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
                if ($script:BtnApplyVis) { $script:BtnApplyVis.Text = 'Apply visibility' }
                if ($script:RadioPrivate) {
                    # Suppressed refresh: re-reading ServerConfig.toml here must
                    # only update the GUI, never re-fire the toggle handlers.
                    $script:SuppressSettingEvents = $true
                    try {
                        $cur = Get-ServerPrivate
                        $script:isPrivate = [bool]$cur
                        $script:RadioPrivate.Checked = $cur
                        $script:RadioPublic.Checked = -not $cur
                    } finally {
                        $script:SuppressSettingEvents = $false
                    }
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
        if ($script:ActionQueue.Count -and -not $script:PendingAction) {
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
        $script:BtnStart.Text = "$([char]0x25B6)  Start Server"
        $script:BtnStart.Invalidate()
        $script:BtnStop.Invalidate()
        Set-CtrlText $script:LblPlayers ''
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
        $script:BtnStart.Invalidate()
        $script:BtnStop.Invalidate()
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
        if ($state) { Set-CtrlText $script:LblPlayers $state }
    } elseif (-not $script:State.Running) {
        Set-CtrlText $script:LblPlayers ''
    }
    if ($script:State.Running -and -not $script:Busy) {
        Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.Conn = Get-ConnectionInfo" 'live'
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
    if ($script:BtnWinMax) { $script:BtnWinMax.Invalidate() }
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
    } elseif (-not $e.Alt) {
        $handled = $false
        switch ($e.KeyCode) {
            'PageDown' {
                if ([WheelFilter]::ScrollCallback) { & [WheelFilter]::ScrollCallback -240; $handled = $true }
            }
            'PageUp' {
                if ([WheelFilter]::ScrollCallback) { & [WheelFilter]::ScrollCallback 240; $handled = $true }
            }
            'Down' {
                if ($script:Form.ActiveControl -isnot [System.Windows.Forms.ListBox] -and $script:Form.ActiveControl -isnot [System.Windows.Forms.ComboBox]) {
                    if ([WheelFilter]::ScrollCallback) { & [WheelFilter]::ScrollCallback -60; $handled = $true }
                }
            }
            'Up' {
                if ($script:Form.ActiveControl -isnot [System.Windows.Forms.ListBox] -and $script:Form.ActiveControl -isnot [System.Windows.Forms.ComboBox]) {
                    if ([WheelFilter]::ScrollCallback) { & [WheelFilter]::ScrollCallback 60; $handled = $true }
                }
            }
        }
        if ($handled) { $e.SuppressKeyPress = $true }
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
    Add-Log "[READY] K BNG M Hoster v$($script:AppVersion) initialized. Press Start Server (Ctrl+S) when ready."
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
    if ($script:LicenseLocked) { Set-LicenseLock $true }
    try { [Win32Chrome]::ApplyModernWindow($script:Form.Handle) } catch { }
    # The window is fully painted at this point. All slow one-time work starts
    # HERE, exclusively on background runspaces (FRP zip extraction + probe,
    # GitHub update check, and full WAN/CGNAT address detection).
    Start-FrpInitAsync
    Start-ToolUpdateCheck
    Start-CoreAction "param(`$Queue, `$State)`n`$script:Q = `$Queue`n`$State.Conn = Get-ConnectionInfo" 'live'
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
if ($script:FrpInitPs) {
    try { $script:FrpInitPs.Dispose() } catch { }
    $script:FrpInitPs = $null
}
Stop-FrpTunnel | Out-Null
exit 0
