param(
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if (-not $OutputPath) {
    $reportDir = Join-Path $repoRoot "reports"
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path $reportDir "studio-xdr-support-$stamp.txt"
}

$report = [System.Collections.Generic.List[string]]::new()

function Add-Line {
    param([string]$Line = "")
    $script:report.Add($Line)
}

function Add-Section {
    param(
        [string]$Title,
        [scriptblock]$Body
    )

    Add-Line ""
    Add-Line "== $Title =="
    try {
        $text = (& $Body *>&1 | Out-String -Width 240).TrimEnd()
        if ([string]::IsNullOrWhiteSpace($text)) {
            Add-Line "(no output)"
        }
        else {
            Add-Line $text
        }
    }
    catch {
        Add-Line "ERROR: $($_.Exception.Message)"
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)

Add-Line "Studio Display XDR Windows Support Report"
Add-Line "Generated: $(Get-Date -Format o)"
Add-Line "Root: $repoRoot"
Add-Line "User: $($identity.Name)"
Add-Line "Admin: $($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"

Add-Section "Package Metadata" {
    $metadata = Join-Path $repoRoot "PACKAGE.json"
    if (Test-Path -LiteralPath $metadata) {
        Get-Content -LiteralPath $metadata
    }
    else {
        "PACKAGE.json not found. This may be a development checkout or an older package."
    }
}

Add-Section "Source State" {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot ".git"))) {
        "Not a git checkout. This is expected when running from a downloaded release ZIP."
        return
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        "Git is not installed or not on PATH."
        return
    }

    git -C $repoRoot status --short
}

Add-Section "OS And .NET" {
    $os = Get-CimInstance Win32_OperatingSystem
    $dotnetRuntimes = "(dotnet not installed; not required for the packaged app or scripts)"
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        try { $dotnetRuntimes = ((& dotnet --list-runtimes 2>$null) -join "; ") } catch { $dotnetRuntimes = "ERROR: $($_.Exception.Message)" }
    }

    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        Windows = $os.Caption
        Version = $os.Version
        Build = $os.BuildNumber
        PowerShell = $PSVersionTable.PSVersion.ToString()
        DotNetRuntimes = $dotnetRuntimes
    } | Format-List
}

Add-Section "App Configuration" {
    $localRoot = Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "StudioDisplayXdr"
    $settingsPath = Join-Path $localRoot "settings.json"
    $installedRoot = Join-Path $localRoot "Support"
    $installedApp = Join-Path $installedRoot "StudioDisplayXdr.App\StudioDisplayXdr.exe"
    $runKeyPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    $startupValue = $null

    try {
        $startupValue = (Get-ItemProperty -LiteralPath $runKeyPath -Name "StudioDisplayXdr" -ErrorAction SilentlyContinue).StudioDisplayXdr
    }
    catch {
        $startupValue = "ERROR: $($_.Exception.Message)"
    }

    $settings = [ordered]@{
        LocalRoot = $localRoot
        SettingsPath = $settingsPath
        SettingsPresent = Test-Path -LiteralPath $settingsPath
        AutoBrightnessEnabled = $null
        AutoMinimumBrightnessPercent = $null
        AutoMaximumBrightnessPercent = $null
        AutoResponsePercent = $null
        SettingsError = $null
    }

    if ($settings.SettingsPresent) {
        try {
            $settingsJson = Get-Content -Raw -LiteralPath $settingsPath |
                ForEach-Object { $_.TrimStart([char]0xFEFF) }
            $settingsData = $settingsJson | ConvertFrom-Json
            $settings.AutoBrightnessEnabled = $settingsData.AutoBrightnessEnabled
            $settings.AutoMinimumBrightnessPercent = $settingsData.AutoMinimumBrightnessPercent
            $settings.AutoMaximumBrightnessPercent = $settingsData.AutoMaximumBrightnessPercent
            $settings.AutoResponsePercent = $settingsData.AutoResponsePercent
        }
        catch {
            $settings.SettingsError = $_.Exception.Message
        }
    }

    [pscustomobject]$settings | Format-List
    [pscustomobject]@{
        OpenAtLoginEnabled = -not [string]::IsNullOrWhiteSpace($startupValue)
        StartupRunValue = $startupValue
        StableInstallRoot = $installedRoot
        StableInstallRootPresent = Test-Path -LiteralPath $installedRoot
        StableAppPresent = Test-Path -LiteralPath $installedApp
    } | Format-List

    $processes = @(Get-Process -Name "StudioDisplayXdr" -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        "RunningAppProcesses: none"
    }
    else {
        "RunningAppProcesses:"
        $processes |
            Select-Object Id,ProcessName,MainWindowTitle,MainWindowHandle,@{ Name = "Path"; Expression = { try { $_.Path } catch { "(unavailable)" } } } |
            Format-Table -AutoSize
    }
}

Add-Section "Readiness Summary" {
    & (Join-Path $PSScriptRoot "Test-StudioXdrReadiness.ps1")
}

Add-Section "Display Mode And Monitor EDID" {
    & (Join-Path $PSScriptRoot "Get-StudioXdrStatus.ps1")
}

Add-Section "HDR And Color Target" {
    & (Join-Path $PSScriptRoot "Get-StudioXdrColorStatus.ps1")
}

Add-Section "Color Profile Discovery" {
    & (Join-Path $PSScriptRoot "Find-StudioXdrColorProfiles.ps1")
}

Add-Section "5K120 Mode Test" {
    & (Join-Path $PSScriptRoot "Set-StudioXdrDisplayMode.ps1") -RefreshRate 120 -TestOnly
}

Add-Section "Gaming And Tearing Diagnostic" {
    & (Join-Path $PSScriptRoot "Get-StudioXdrGamingStatus.ps1")
}

Add-Section "Brightness HID" {
    . (Join-Path $PSScriptRoot "AppleDisplayBrightnessCore.ps1")
    Get-AppleDisplayBrightnessDevice |
        Select-Object DisplayName,ProductId,Percent,CurrentValue,Path |
        Format-List
}

Add-Section "Ambient Connector" {
    & (Join-Path $PSScriptRoot "Get-StudioXdrAmbientStatus.ps1")
}

Add-Section "Ambient Driver Target" {
    & (Join-Path $PSScriptRoot "Test-StudioXdrAmbientDriverTarget.ps1")
}

Add-Section "Ambient Driver Package Signing" {
    & (Join-Path $PSScriptRoot "New-StudioXdrAmbientDriverPackage.ps1") -CheckOnly
}

Add-Section "Ambient Preflight" {
    & (Join-Path $PSScriptRoot "Test-StudioXdrAmbientPreflight.ps1")
}

Add-Section "Studio Display XDR HID Collections" {
    & (Join-Path $PSScriptRoot "Dump-StudioXdrHidCollections.ps1")
}

Add-Section "Apple Display USB Topology" {
    & (Join-Path $PSScriptRoot "Get-AppleDisplayUsbTopology.ps1")
}

Add-Section "Apple Display Sensor Correlation" {
    & (Join-Path $PSScriptRoot "Get-AppleDisplaySensorCorrelation.ps1")
}

Add-Section "Studio Display USB Devices" {
    Get-PnpDevice -PresentOnly |
        Where-Object {
            $_.InstanceId -match "VID_05AC&PID_1116|USB4\\VID_8087&PID_5786" -or
            $_.FriendlyName -match "Studio Display|Studio XDR|FaceTime|Apple"
        } |
        Sort-Object Class,FriendlyName |
        Select-Object Status,Class,FriendlyName,InstanceId |
        Format-Table -AutoSize
}

Add-Section "Camera, Speakers, Microphone" {
    Get-PnpDevice -PresentOnly -Class Camera,Image,Media,AudioEndpoint |
        Where-Object { $_.InstanceId -match "VID_05AC&PID_1116" -or $_.FriendlyName -match "Studio Display" } |
        Sort-Object Class,FriendlyName |
        Select-Object Status,Class,FriendlyName,InstanceId |
        Format-Table -AutoSize
}

Add-Section "Graphics Drivers" {
    Get-CimInstance Win32_VideoController |
        Select-Object Name,AdapterCompatibility,VideoModeDescription,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate,CurrentBitsPerPixel,DriverVersion,DriverDate |
        Format-List
}

Add-Section "Relevant Color Profiles Folder" {
    $colorDir = Join-Path $env:WINDIR "System32\spool\drivers\color"
    Get-ChildItem -LiteralPath $colorDir -File |
        Where-Object { $_.Name -match "Apple|Studio|Display|XDR|P3|Adobe|BT2020|HDR|sRGB|wscRGB|wsRGB" } |
        Select-Object Name,Length,LastWriteTime |
        Sort-Object Name |
        Format-Table -AutoSize
}

Add-Section "Package Artifacts" {
    $installedRoot = Join-Path (Join-Path ([Environment]::GetFolderPath("LocalApplicationData")) "StudioDisplayXdr") "Support"
    $artifactPaths = @(
        "StudioDisplayXdrSetup.exe",
        "Prepare-Ambient-Driver.cmd",
        "Check-Gaming.cmd",
        "StudioDisplayXdr.App\StudioDisplayXdr.exe",
        "assets\StudioDisplayXdr.ico",
        "tools\LibUsbDotNet.LibUsbDotNet.net45.dll",
        "drivers\StudioXdrAmbientWinUsb.inf",
        "drivers\StudioXdrAmbientWinUsb.cat",
        "scripts\New-StudioXdrAmbientDriverPackage.ps1",
        "scripts\Get-StudioXdrGamingStatus.ps1",
        "PACKAGE.json",
        "dist\studio-display-xdr-windows.zip",
        "dist\PackageSetup\StudioDisplayXdrSetup.exe",
        "dist\StudioDisplayXdr.App\StudioDisplayXdr.exe",
        "dist\PackageTools\tools\LibUsbDotNet.LibUsbDotNet.net45.dll"
    )

    $artifacts = foreach ($relativePath in $artifactPaths) {
        $path = Join-Path $repoRoot $relativePath
        if (Test-Path -LiteralPath $path) {
            Get-Item -LiteralPath $path |
                Select-Object @{ Name = "RelativePath"; Expression = { $relativePath } }, Length, LastWriteTime
        }
    }

    $artifacts | Format-Table -AutoSize

    if (Test-Path -LiteralPath $installedRoot) {
        ""
        "Stable install root: $installedRoot"
        foreach ($relativePath in @("StudioDisplayXdr.App\StudioDisplayXdr.exe", "StudioDisplayXdrSetup.exe", "PACKAGE.json")) {
            $path = Join-Path $installedRoot $relativePath
            if (Test-Path -LiteralPath $path) {
                Get-Item -LiteralPath $path |
                    Select-Object @{ Name = "RelativePath"; Expression = { "installed\$relativePath" } }, Length, LastWriteTime
            }
        }
    }
}

$reportText = ($report -join [Environment]::NewLine).Trim() + [Environment]::NewLine
Set-Content -LiteralPath $OutputPath -Value $reportText -Encoding UTF8

Write-Host "Support report written:"
Write-Host $OutputPath
Get-Item -LiteralPath $OutputPath
