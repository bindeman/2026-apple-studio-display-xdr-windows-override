param(
    [string]$MonitorInstanceId = "",
    # Remove every EDID_OVERRIDE key created by this project (tagged with the name "Studio XDR"),
    # even when the Studio Display XDR is not currently present. Use this from Safe Mode or from
    # another monitor when the Apple display is black.
    [switch]$All,
    # With -All: also remove EDID_OVERRIDE keys created by other tools (for example CRU).
    [switch]$Force
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

function Get-OverrideName([string]$overridePath) {
    # Install-StudioXdrEdidOverride.ps1 writes CRU_Name as one flag byte followed by ASCII "Studio XDR".
    try {
        $key = Get-Item -LiteralPath $overridePath -ErrorAction Stop
        $bytes = $key.GetValue("CRU_Name")
        if ($bytes -is [byte[]] -and $bytes.Length -gt 1) {
            return [Text.Encoding]::ASCII.GetString($bytes, 1, $bytes.Length - 1).Trim([char]0)
        }
    }
    catch { }

    return ""
}

Assert-Admin

$removed = 0

if ($All) {
    $overrideKeys = @(Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -eq "EDID_OVERRIDE" })

    if ($overrideKeys.Count -eq 0) {
        Write-Host "No EDID_OVERRIDE keys found under HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY."
    }

    foreach ($key in $overrideKeys) {
        $name = Get-OverrideName $key.PSPath
        if ($name -eq "Studio XDR" -or $Force) {
            Remove-Item -LiteralPath $key.PSPath -Recurse -Force
            $removed++
            $label = if ($name) { $name } else { "unnamed" }
            Write-Host "Removed EDID override ($label) from $($key.Name)"
        }
        else {
            Write-Host "Kept EDID override '$name' at $($key.Name). Pass -Force with -All to remove overrides created by other tools."
        }
    }
}
else {
    $present = @(Get-PnpDevice -Class Monitor -PresentOnly | Where-Object { $_.InstanceId -match "^DISPLAY\\" })
    if ($MonitorInstanceId) {
        $targets = @($present | Where-Object { $_.InstanceId -ieq $MonitorInstanceId })
    } else {
        $targets = @($present | Where-Object { $_.InstanceId -match "^DISPLAY\\MS_0001\\" -or $_.FriendlyName -match "Studio XDR|Generic Monitor" })
    }

    if ($targets.Count -eq 0) {
        throw "No matching active monitor override target found. Pass -MonitorInstanceId, or use -All to remove every Studio XDR override even when the display is not active."
    }

    foreach ($target in $targets) {
        $deviceParametersPath = Get-DisplayRegistryPath $target.InstanceId
        $overridePath = Join-Path $deviceParametersPath "EDID_OVERRIDE"
        if (Test-Path $overridePath) {
            Remove-Item -Path $overridePath -Recurse -Force
            $removed++
            Write-Host "Removed EDID override from $($target.InstanceId)"
        } else {
            Write-Host "No EDID override found on $($target.InstanceId)"
        }
    }
}

Write-Host ""
Write-Host "Removed $removed EDID override key(s)."
Write-Host "Reboot Windows or restart the graphics driver for removal to take effect."
