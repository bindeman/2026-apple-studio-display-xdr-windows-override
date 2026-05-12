param(
    [string]$MonitorInstanceId = ""
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script from an elevated PowerShell session."
    }
}

function Get-DisplayRegistryPath([string]$instanceId) {
    $parts = $instanceId -split "\\", 3
    if ($parts.Count -lt 3 -or $parts[0] -ne "DISPLAY") {
        throw "Unexpected monitor instance ID: $instanceId"
    }

    "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\$($parts[1])\$($parts[2])\Device Parameters"
}

Assert-Admin

$present = @(Get-PnpDevice -Class Monitor -PresentOnly | Where-Object { $_.InstanceId -match "^DISPLAY\\" })
if ($MonitorInstanceId) {
    $targets = @($present | Where-Object { $_.InstanceId -ieq $MonitorInstanceId })
} else {
    $targets = @($present | Where-Object { $_.InstanceId -match "^DISPLAY\\MS_0001\\" -or $_.FriendlyName -match "Studio XDR|Generic Monitor" })
}

if ($targets.Count -eq 0) {
    throw "No matching active monitor override target found. Pass -MonitorInstanceId if needed."
}

foreach ($target in $targets) {
    $deviceParametersPath = Get-DisplayRegistryPath $target.InstanceId
    $overridePath = Join-Path $deviceParametersPath "EDID_OVERRIDE"
    if (Test-Path $overridePath) {
        Remove-Item -Path $overridePath -Recurse -Force
        Write-Host "Removed EDID override from $($target.InstanceId)"
    } else {
        Write-Host "No EDID override found on $($target.InstanceId)"
    }
}

Write-Host ""
Write-Host "Reboot Windows or restart the graphics driver for removal to take effect."
