param(
    [switch]$SkipEdid,
    [switch]$SkipHdr,
    [switch]$SkipNativeMode,
    [switch]$SkipColorProfile,
    [switch]$SkipAmbientSensor,
    [switch]$SkipShortcuts,
    [switch]$SkipAppInstall,
    [switch]$SkipLaunch,
    [switch]$ApplyNativeMode,
    [switch]$Force,
    [switch]$NoPrompt,
    [string]$InstallRoot = ""
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this installer as administrator."
    }
}

function Get-RepoRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-DefaultInstallRoot {
    Join-Path (Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "StudioDisplayXdr") "Support"
}

function Assert-SafeInstallRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Get-DefaultInstallRoot
    }

    $base = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "StudioDisplayXdr"
    $trimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $baseFull = [System.IO.Path]::GetFullPath($base).TrimEnd($trimChars)
    $targetFull = [System.IO.Path]::GetFullPath($Path).TrimEnd($trimChars)
    $prefix = "$baseFull$([System.IO.Path]::DirectorySeparatorChar)"

    if (-not $targetFull.Equals($baseFull, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $targetFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "InstallRoot must be under $baseFull. Refusing to use: $targetFull"
    }

    $targetFull
}

function Write-Step([string]$text) {
    Write-Host ""
    Write-Host "== $text ==" -ForegroundColor Cyan
}

function Confirm-Step([string]$question, [bool]$defaultYes = $true) {
    if ($NoPrompt) {
        return $defaultYes
    }

    $suffix = if ($defaultYes) { "[Y/n]" } else { "[y/N]" }
    $answer = Read-Host "$question $suffix"
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return $defaultYes
    }

    return $answer -match "^(y|yes)$"
}

function Get-StudioMonitorSummary {
    $monitor = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue |
        Where-Object {
            $name = -join ($_.UserFriendlyName | Where-Object { $_ } | ForEach-Object { [char]$_ })
            $instance = $_.InstanceName
            $name -match "Studio|XDR" -or $instance -match "DISPLAY\\MS_0001"
        } |
        Select-Object -First 1

    if (-not $monitor) {
        return $null
    }

    [pscustomobject]@{
        InstanceName = $monitor.InstanceName
        Manufacturer = -join ($monitor.ManufacturerName | Where-Object { $_ } | ForEach-Object { [char]$_ })
        Product = -join ($monitor.ProductCodeID | Where-Object { $_ } | ForEach-Object { [char]$_ })
        Name = -join ($monitor.UserFriendlyName | Where-Object { $_ } | ForEach-Object { [char]$_ })
    }
}

function Test-StudioHidBrightness {
    . (Join-Path $PSScriptRoot "AppleDisplayBrightnessCore.ps1")
    @(Get-AppleDisplayBrightnessDevice | Where-Object { $_.ProductId -eq "1116" } | Select-Object -First 1)
}

function Test-WindowsDesktopRuntime {
    # "dotnet" is not installed on most end-user machines. Calling a missing command
    # under $ErrorActionPreference = "Stop" throws, so check for it first.
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        return $false
    }

    try {
        $runtime = & dotnet --list-runtimes 2>$null | Where-Object { $_ -match "^Microsoft\.WindowsDesktop\.App 8\." } | Select-Object -First 1
        return [bool]$runtime
    }
    catch {
        return $false
    }
}

function Test-BundledControlPanel {
    param([string]$Root)

    $app = Find-ControlPanelApp -Root $Root
    if ([string]::IsNullOrWhiteSpace($app) -or -not (Test-Path -LiteralPath $app)) {
        return $false
    }

    $wpfRuntime = Join-Path (Split-Path -Parent $app) "PresentationFramework.dll"
    Test-Path -LiteralPath $wpfRuntime
}

function Find-ControlPanelApp {
    param([string]$Root)

    $candidates = @(
        (Join-Path $Root "StudioDisplayXdr.App\StudioDisplayXdr.exe"),
        (Join-Path $Root "dist\StudioDisplayXdr.App\StudioDisplayXdr.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

function Copy-PackageItem {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourceRoot,

        [Parameter(Mandatory=$true)]
        [string]$TargetRoot,

        [Parameter(Mandatory=$true)]
        [string]$RelativePath,

        [string]$TargetRelativePath = ""
    )

    $source = Join-Path $SourceRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source)) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($TargetRelativePath)) {
        $TargetRelativePath = $RelativePath
    }

    $target = Join-Path $TargetRoot $TargetRelativePath
    $parent = Split-Path -Parent $target
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
    return $true
}

function Install-AppPackage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourceRoot,

        [Parameter(Mandatory=$true)]
        [string]$InstallRoot
    )

    $sourceFull = (Resolve-Path -LiteralPath $SourceRoot).Path
    $targetFull = Assert-SafeInstallRoot -Path $InstallRoot
    $trimChars = [char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $sourceComparable = [System.IO.Path]::GetFullPath($sourceFull).TrimEnd($trimChars)

    if ($sourceComparable.Equals($targetFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "App files are already running from $targetFull"
        return $targetFull
    }

    if (Test-Path -LiteralPath $targetFull) {
        Remove-Item -LiteralPath $targetFull -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $targetFull | Out-Null

    $rootFiles = @(
        "README.md",
        "LICENSE",
        "THIRD_PARTY_NOTICES.md",
        "PACKAGE.json",
        "CONTINUE.md",
        "RELEASE_NOTES.md",
        "Install-StudioDisplayXdrSupport.cmd",
        "Install-Ambient-Connector.cmd",
        "Install-LibUsb-Ambient-Filter.cmd",
        "Install-Color-Profile.cmd",
        "Install-StudioXdr.cmd",
        "Uninstall-StudioDisplayXdrSupport.cmd",
        "Uninstall-LibUsb-Ambient-Filter.cmd",
        "Check-Status.cmd",
        "Check-Ambient.cmd",
        "Check-Color.cmd",
        "Enable-HDR.cmd",
        "Disable-HDR.cmd",
        "Studio-Display-XDR.cmd",
        "Support-Report.cmd",
        "Apple-Brightness-Tray.cmd",
        "Brightness-Up.cmd",
        "Brightness-Down.cmd",
        "Brightness-Status.cmd",
        "Uninstall-Override.cmd"
    )

    foreach ($file in $rootFiles) {
        [void](Copy-PackageItem -SourceRoot $sourceFull -TargetRoot $targetFull -RelativePath $file)
    }

    if (-not (Copy-PackageItem -SourceRoot $sourceFull -TargetRoot $targetFull -RelativePath "StudioDisplayXdrSetup.exe")) {
        [void](Copy-PackageItem -SourceRoot $sourceFull -TargetRoot $targetFull -RelativePath "dist\PackageSetup\StudioDisplayXdrSetup.exe" -TargetRelativePath "StudioDisplayXdrSetup.exe")
    }

    $appCopied = Copy-PackageItem -SourceRoot $sourceFull -TargetRoot $targetFull -RelativePath "StudioDisplayXdr.App"
    if (-not $appCopied) {
        $appCopied = Copy-PackageItem -SourceRoot $sourceFull -TargetRoot $targetFull -RelativePath "dist\StudioDisplayXdr.App" -TargetRelativePath "StudioDisplayXdr.App"
    }
    if (-not $appCopied) {
        Write-Host "Compiled control panel is not included in this package (scripts-only). Shortcuts will use the PowerShell brightness tray instead."
    }

    foreach ($dir in @("drivers", "edid", "profiles", "scripts", "docs")) {
        [void](Copy-PackageItem -SourceRoot $sourceFull -TargetRoot $targetFull -RelativePath $dir)
    }

    if (-not (Copy-PackageItem -SourceRoot $sourceFull -TargetRoot $targetFull -RelativePath "tools\LibUsbDotNet.LibUsbDotNet.net45.dll")) {
        [void](Copy-PackageItem -SourceRoot $sourceFull -TargetRoot $targetFull -RelativePath "dist\PackageTools\tools\LibUsbDotNet.LibUsbDotNet.net45.dll" -TargetRelativePath "tools\LibUsbDotNet.LibUsbDotNet.net45.dll")
    }

    Write-Host "Installed app files to:"
    Write-Host "  $targetFull"
    return $targetFull
}

function New-Shortcut {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [string]$Target,

        [string]$Arguments = "",
        [string]$WorkingDirectory = "",
        [string]$Description = ""
    )

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $shortcut.TargetPath = $Target
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.Description = $Description
    $shortcut.IconLocation = $Target
    $shortcut.Save()
}

function Install-AppShortcuts {
    param([string]$Root)

    $app = Find-ControlPanelApp -Root $Root
    $appDescription = "Open the Studio Display XDR control panel"
    if ([string]::IsNullOrWhiteSpace($app) -or -not (Test-Path -LiteralPath $app)) {
        # Scripts-only package: point the main shortcut at the launcher, which falls back
        # to the PowerShell brightness tray when the compiled control panel is absent.
        $app = Join-Path $Root "Studio-Display-XDR.cmd"
        $appDescription = "Open the Studio Display XDR brightness tray"
        if (-not (Test-Path -LiteralPath $app)) {
            Write-Warning "Neither the compiled control panel nor Studio-Display-XDR.cmd was found under $Root. Skipping shortcuts."
            return
        }
        Write-Host "Compiled control panel not found. Shortcuts will target Studio-Display-XDR.cmd (PowerShell brightness tray)."
    }

    $programs = [Environment]::GetFolderPath("Programs")
    $desktop = [Environment]::GetFolderPath("DesktopDirectory")
    $folder = Join-Path $programs "Studio Display XDR"
    New-Item -ItemType Directory -Force -Path $folder | Out-Null

    New-Shortcut `
        -Path (Join-Path $folder "Studio Display XDR.lnk") `
        -Target $app `
        -WorkingDirectory (Split-Path -Parent $app) `
        -Description $appDescription

    New-Shortcut `
        -Path (Join-Path $desktop "Studio Display XDR.lnk") `
        -Target $app `
        -WorkingDirectory (Split-Path -Parent $app) `
        -Description $appDescription

    $support = Join-Path $Root "Support-Report.cmd"
    if (Test-Path -LiteralPath $support) {
        New-Shortcut `
            -Path (Join-Path $folder "Studio Display XDR Support Report.lnk") `
            -Target $support `
            -WorkingDirectory $Root `
            -Description "Generate a Studio Display XDR support report"
    }

    $status = Join-Path $Root "Check-Status.cmd"
    if (Test-Path -LiteralPath $status) {
        New-Shortcut `
            -Path (Join-Path $folder "Studio Display XDR Check Status.lnk") `
            -Target $status `
            -WorkingDirectory $Root `
            -Description "Run a Studio Display XDR readiness check"
    }

    $ambient = Join-Path $Root "Check-Ambient.cmd"
    if (Test-Path -LiteralPath $ambient) {
        New-Shortcut `
            -Path (Join-Path $folder "Studio Display XDR Check Ambient.lnk") `
            -Target $ambient `
            -WorkingDirectory $Root `
            -Description "Run a Studio Display XDR automatic-brightness preflight"
    }

    $color = Join-Path $Root "Check-Color.cmd"
    if (Test-Path -LiteralPath $color) {
        New-Shortcut `
            -Path (Join-Path $folder "Studio Display XDR Check Color.lnk") `
            -Target $color `
            -WorkingDirectory $Root `
            -Description "Run a Studio Display XDR color and profile check"
    }

    Write-Host "Shortcuts installed:"
    Write-Host "  $folder"
    Write-Host "  $desktop\Studio Display XDR.lnk"
}

Assert-Admin
$repoRoot = Get-RepoRoot
$shortcutRoot = $repoRoot

Write-Host "Studio Display XDR Support Installer" -ForegroundColor White
Write-Host "This will configure the 2026 Apple Studio Display XDR support package for Windows."

Write-Step "Detected display"
$studioMonitor = Get-StudioMonitorSummary
if ($studioMonitor) {
    $studioMonitor | Format-List
} else {
    Write-Warning "No Studio Display XDR monitor identity was found through WMI."
}

Write-Step "Detected Studio USB/HID control path"
$brightnessDevice = Test-StudioHidBrightness
if ($brightnessDevice) {
    [pscustomobject]@{
        Display = $brightnessDevice.DisplayName
        Product = "05AC:$($brightnessDevice.ProductId)"
        Brightness = "$($brightnessDevice.Percent)%"
        Raw = $brightnessDevice.CurrentValue
    } | Format-List
} else {
    Write-Warning "Brightness HID was not detected. Brightness control requires Thunderbolt / USB4, not a video-only adapter."
}

Write-Step "Control panel runtime"
if (Test-BundledControlPanel -Root $repoRoot) {
    Write-Host "Self-contained Studio Display XDR control panel found. No separate .NET runtime install is required."
}
elseif (Find-ControlPanelApp -Root $repoRoot) {
    if (Test-WindowsDesktopRuntime) {
        Write-Host ".NET 8 Windows Desktop Runtime found for the framework-dependent control panel."
    } else {
        Write-Warning ".NET 8 Windows Desktop Runtime was not found. Install it before using a framework-dependent control panel build."
    }
} else {
    Write-Host "This is the scripts-only package: the compiled control panel is not included."
    Write-Host "Brightness control uses the PowerShell tray (Studio-Display-XDR.cmd / Apple-Brightness-Tray.cmd). No .NET runtime is required."
}

if (-not $SkipEdid -and (Confirm-Step "Install or refresh the Studio Display XDR EDID override?")) {
    Write-Step "Installing EDID override"
    $installArgs = @()
    if ($Force) { $installArgs += "-Force" }
    & (Join-Path $PSScriptRoot "Install-StudioXdrEdidOverride.ps1") @installArgs
}

if (-not $SkipHdr -and (Confirm-Step "Enable Windows HDR / Advanced Color for Studio Display XDR?")) {
    Write-Step "Enabling HDR"
    & (Join-Path $PSScriptRoot "Enable-StudioXdrHdr.ps1")
}

if (-not $SkipNativeMode) {
    Write-Step "Testing native 5K120 mode"
    $modeTest = & (Join-Path $PSScriptRoot "Set-StudioXdrDisplayMode.ps1") -RefreshRate 120 -TestOnly
    Write-Host $modeTest

    if ($modeTest -match "test success; result=0") {
        if ($ApplyNativeMode -or (Confirm-Step "Apply 5120 x 2880 @ 120 Hz now? The screen may flicker." $false)) {
            Write-Step "Applying native 5K120 mode"
            & (Join-Path $PSScriptRoot "Set-StudioXdrDisplayMode.ps1") -RefreshRate 120
        }
    }
    else {
        Write-Warning "Windows did not accept the 5120 x 2880 @ 120 Hz test. Reboot after the EDID override, then use Display Settings or the app's Optimize button."
    }
}

if (-not $SkipColorProfile) {
    $displayP3Profile = Join-Path $repoRoot "profiles\StudioDisplayXDR-DisplayP3.icm"
    if (Test-Path -LiteralPath $displayP3Profile) {
        if (Confirm-Step "Install the generated Studio Display XDR Display P3 color profile?" $false) {
            Write-Step "Installing Display P3 color profile"
            & (Join-Path $PSScriptRoot "Install-StudioXdrColorProfile.ps1") -ProfilePath $displayP3Profile
        }
    }
    else {
        Write-Warning "Generated Display P3 profile not found: $displayP3Profile"
    }
}

if (-not $SkipAmbientSensor) {
    Write-Step "Experimental automatic brightness sensor"
    & (Join-Path $PSScriptRoot "Get-StudioXdrAmbientStatus.ps1")

    if (Confirm-Step "Install the experimental WinUSB ambient connector for MI_08? This is for native sensor research." $false) {
        Write-Step "Installing experimental WinUSB ambient connector"
        $ambientArgs = @()
        if ($Force) { $ambientArgs += "-Force" }
        & (Join-Path $PSScriptRoot "Install-StudioXdrAmbientConnector.ps1") @ambientArgs
    }

    if (Confirm-Step "Install the experimental libusb-win32 MI_08 filter? Use this only for the SDBC-style native sensor test." $false) {
        Write-Step "Installing experimental libusb-win32 MI_08 filter"
        & (Join-Path $PSScriptRoot "Install-StudioXdrLibUsbFilter.ps1") -Force
    }
}

if (-not $SkipAppInstall) {
    $resolvedInstallRoot = Assert-SafeInstallRoot -Path $InstallRoot
    if (Confirm-Step "Install app files to $resolvedInstallRoot? This keeps shortcuts working after the extracted ZIP is moved." $true) {
        Write-Step "Installing app files"
        $shortcutRoot = Install-AppPackage -SourceRoot $repoRoot -InstallRoot $resolvedInstallRoot
    }
}

if (-not $SkipShortcuts -and (Confirm-Step "Install Start Menu and Desktop shortcuts?")) {
    Write-Step "Installing shortcuts"
    Install-AppShortcuts -Root $shortcutRoot
}

Write-Step "Final status"
& (Join-Path $PSScriptRoot "Get-StudioXdrStatus.ps1")

if (-not $SkipLaunch -and (Confirm-Step "Open the Studio Display XDR control panel now?")) {
    $app = Find-ControlPanelApp -Root $shortcutRoot
    if (-not [string]::IsNullOrWhiteSpace($app) -and (Test-Path -LiteralPath $app)) {
        Start-Process -FilePath $app -WorkingDirectory (Split-Path -Parent $app)
    } else {
        Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "AppleDisplayBrightnessTray.ps1"))
    }
}

Write-Host ""
Write-Host "Done. Reboot Windows after installing the EDID override, then choose 5120 x 2880 and 120 Hz in Display Settings." -ForegroundColor Green
if (-not $NoPrompt) {
    Read-Host "Press Enter to close"
}
