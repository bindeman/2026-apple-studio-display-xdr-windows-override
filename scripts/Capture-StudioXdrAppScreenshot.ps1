param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "docs\screenshots\control-panel.png"),
    [switch]$Bottom
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repoRoot "dist\StudioDisplayXdr.App\StudioDisplayXdr.exe"

if (-not (Test-Path -LiteralPath $app)) {
    throw "Compiled app not found. Run scripts\Build-StudioDisplayXdrPackage.ps1 first."
}

$process = Get-Process StudioDisplayXdr -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1

if (-not $process) {
    $process = Start-Process -FilePath $app -WorkingDirectory (Split-Path -Parent $app) -PassThru
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        $process.Refresh()
        if ($process.MainWindowHandle -ne 0) {
            break
        }
    }
}

if (-not $process -or $process.MainWindowHandle -eq 0) {
    throw "Studio Display XDR app window was not found."
}

$source = @"
using System;
using System.Runtime.InteropServices;

public static class WindowCaptureNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
}
"@

if (-not ("WindowCaptureNative" -as [type])) {
    Add-Type -TypeDefinition $source
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient

[WindowCaptureNative]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
$hwndTopMost = [IntPtr](-1)
$hwndNoTopMost = [IntPtr](-2)
$swRestore = 9
$swpNoMove = 0x0002
$swpNoSize = 0x0001
$swpShowWindow = 0x0040
[WindowCaptureNative]::ShowWindow($process.MainWindowHandle, $swRestore) | Out-Null
[WindowCaptureNative]::SetWindowPos($process.MainWindowHandle, $hwndTopMost, 40, 40, 0, 0, ($swpNoSize -bor $swpShowWindow)) | Out-Null
[WindowCaptureNative]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 700

$root = [System.Windows.Automation.AutomationElement]::RootElement
$handleCondition = [System.Windows.Automation.PropertyCondition]::new(
    [System.Windows.Automation.AutomationElement]::NativeWindowHandleProperty,
    [int]$process.MainWindowHandle)
$windowElement = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $handleCondition)

if ($windowElement) {
    $scrollCondition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::IsScrollPatternAvailableProperty,
        $true)
    $scrollElement = $windowElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $scrollCondition)
    if ($scrollElement) {
        $scrollPattern = $scrollElement.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
        $verticalPercent = if ($Bottom) { 100 } else { 0 }
        try {
            $scrollPattern.SetScrollPercent([System.Windows.Automation.ScrollPattern]::NoScroll, $verticalPercent)
            Start-Sleep -Milliseconds 500
        }
        catch {
            Write-Warning "Could not set screenshot scroll position: $($_.Exception.Message)"
        }
    }

    $bounds = $windowElement.Current.BoundingRectangle
    $left = [int][Math]::Round($bounds.Left)
    $top = [int][Math]::Round($bounds.Top)
    $width = [int][Math]::Round($bounds.Width)
    $height = [int][Math]::Round($bounds.Height)
}
else {
    $rect = New-Object WindowCaptureNative+RECT
    if (-not [WindowCaptureNative]::GetWindowRect($process.MainWindowHandle, [ref]$rect)) {
        throw "Could not read app window bounds."
    }

    $left = $rect.Left
    $top = $rect.Top
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
}

if ($width -le 0 -or $height -le 0) {
    throw "Invalid app window bounds: ${width}x${height}"
}

$destination = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $destination)) {
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
}

$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
    $hdc = $graphics.GetHdc()
    try {
        $printed = [WindowCaptureNative]::PrintWindow($process.MainWindowHandle, $hdc, 2)
    }
    finally {
        $graphics.ReleaseHdc($hdc)
    }

    if (-not $printed) {
        $graphics.CopyFromScreen($left, $top, 0, 0, [System.Drawing.Size]::new($width, $height))
    }

    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    [WindowCaptureNative]::SetWindowPos($process.MainWindowHandle, $hwndNoTopMost, 0, 0, 0, 0, ($swpNoMove -bor $swpNoSize)) | Out-Null
    $graphics.Dispose()
    $bitmap.Dispose()
}

Get-Item -LiteralPath $OutputPath
