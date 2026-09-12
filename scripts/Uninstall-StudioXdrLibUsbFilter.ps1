param(
    [string]$InstallerPath = "",
    [switch]$NoPrompt,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script as administrator."
    }
}

function Find-InstallFilter {
    if (-not [string]::IsNullOrWhiteSpace($InstallerPath) -and (Test-Path -LiteralPath $InstallerPath)) {
        return (Resolve-Path -LiteralPath $InstallerPath).Path
    }

    $candidates = @(
        "$env:USERPROFILE\usb_driver\amd64\install-filter.exe",
        "$env:USERPROFILE\Downloads\libusb-win32-bin-1.4.0.0\bin\amd64\install-filter-win.exe",
        "$env:USERPROFILE\Downloads\libusb-win32-bin-1.4.0.0\bin\amd64\install-filter.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

Assert-Admin

$device = Get-PnpDevice -PresentOnly |
    Where-Object { $_.InstanceId -like "USB\VID_05AC&PID_1116&MI_08\*" } |
    Select-Object -First 1

if (-not $device) {
    throw "Studio Display XDR MI_08 interface is not present."
}

$properties = Get-PnpDeviceProperty -InstanceId $device.InstanceId
$hardwareIds = @(
    $properties |
        Where-Object { $_.KeyName -eq "DEVPKEY_Device_HardwareIds" } |
        Select-Object -ExpandProperty Data
)

$targetHardwareId = $hardwareIds | Where-Object { $_ -like "USB\VID_05AC&PID_1116&REV_*&MI_08" } | Select-Object -First 1
if (-not $targetHardwareId) {
    $targetHardwareId = "USB\VID_05AC&PID_1116&MI_08"
}

$installer = Find-InstallFilter
if (-not $installer) {
    throw "Could not find libusb-win32 install-filter.exe. Pass -InstallerPath or install/extract libusb-win32 first."
}

Write-Host "Target device: $($device.InstanceId)"
Write-Host "Current state: $($device.Status) / $($device.Service) / $($device.FriendlyName)"
Write-Host "Filter installer: $installer"
Write-Host "Filter target: $targetHardwareId"
Write-Host ""
Write-Warning "This removes a libusb-win32 upper device filter from the Studio Display XDR MI_08 interface only."

if (-not $NoPrompt -and -not $Force) {
    $answer = Read-Host "Remove the libusb-win32 filter for this exact interface? Type YES to continue"
    if ($answer -ne "YES") {
        Write-Host "Cancelled."
        return
    }
}

$prompt = "Remove libusb-win32 filter for Studio Display XDR MI_08?"
$wait = "Filter removal command finished. Reboot Windows, then run Get-StudioXdrAmbientStatus.ps1."

& $installer uninstall "--device=$targetHardwareId" "--prompt=$prompt" "--wait=$wait"
if ($LASTEXITCODE -ne 0) {
    throw "install-filter.exe failed with exit code $LASTEXITCODE."
}

Write-Host ""
Write-Host "Filter removal command completed. Reboot Windows before retesting the ambient sensor path."
