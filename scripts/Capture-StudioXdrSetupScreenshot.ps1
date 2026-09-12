param(
    [string]$OutputPath = (Join-Path (Split-Path -Parent $PSScriptRoot) "docs\screenshots\setup-launcher.png")
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$setup = Join-Path $repoRoot "dist\PackageSetup\StudioDisplayXdrSetup.exe"

if (-not (Test-Path -LiteralPath $setup)) {
    throw "Setup launcher not found. Run scripts\Build-StudioDisplayXdrPackage.ps1 first."
}

$startedProcess = $false
$process = Get-Process StudioDisplayXdrSetup -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1

if (-not $process) {
    $process = Start-Process -FilePath $setup -WorkingDirectory $repoRoot -PassThru
    $startedProcess = $true
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        $process.Refresh()
        if ($process.MainWindowHandle -ne 0) {
            break
        }
    }
}

if (-not $process -or $process.MainWindowHandle -eq 0) {
    throw "Studio Display XDR setup launcher window was not found."
}

$source = @"
using System;
using System.Runtime.InteropServices;

public static class SetupWindowCaptureNative
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
}
"@

if (-not ("SetupWindowCaptureNative" -as [type])) {
    Add-Type -TypeDefinition $source
}

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient

$hwndTopMost = [IntPtr](-1)
$swRestore = 9
$swpNoMove = 0x0002
$swpNoSize = 0x0001
$swpShowWindow = 0x0040

[SetupWindowCaptureNative]::ShowWindow($process.MainWindowHandle, $swRestore) | Out-Null
[SetupWindowCaptureNative]::SetWindowPos($process.MainWindowHandle, $hwndTopMost, 0, 0, 0, 0, ($swpNoMove -bor $swpNoSize -bor $swpShowWindow)) | Out-Null
[SetupWindowCaptureNative]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 500

$root = [System.Windows.Automation.AutomationElement]::RootElement
$handleCondition = [System.Windows.Automation.PropertyCondition]::new(
    [System.Windows.Automation.AutomationElement]::NativeWindowHandleProperty,
    [int]$process.MainWindowHandle)
$windowElement = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $handleCondition)

if ($windowElement) {
    $bounds = $windowElement.Current.BoundingRectangle
    $left = [int][Math]::Round($bounds.Left)
    $top = [int][Math]::Round($bounds.Top)
    $width = [int][Math]::Round($bounds.Width)
    $height = [int][Math]::Round($bounds.Height)
}
else {
    $rect = New-Object SetupWindowCaptureNative+RECT
    if (-not [SetupWindowCaptureNative]::GetWindowRect($process.MainWindowHandle, [ref]$rect)) {
        throw "Could not read setup launcher window bounds."
    }

    $left = $rect.Left
    $top = $rect.Top
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
}

if ($width -le 0 -or $height -le 0) {
    throw "Invalid setup launcher window bounds: ${width}x${height}"
}

$destination = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $destination)) {
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
}

$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.CopyFromScreen($left, $top, 0, 0, [System.Drawing.Size]::new($width, $height))
    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $graphics.Dispose()
    $bitmap.Dispose()
    if ($startedProcess -and -not $process.HasExited) {
        $process.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 250
        if (-not $process.HasExited) {
            $process.Kill()
        }
    }
}

Get-Item -LiteralPath $OutputPath
