param(
    [string]$EdidPath = "",
    [string]$MonitorInstanceId = "",
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

function Get-RepoRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-DisplayRegistryPath([string]$instanceId) {
    $parts = $instanceId -split "\\", 3
    if ($parts.Count -lt 3 -or $parts[0] -ne "DISPLAY") {
        throw "Unexpected monitor instance ID: $instanceId"
    }

    "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\$($parts[1])\$($parts[2])\Device Parameters"
}

function Backup-MonitorEdids([string]$backupDir) {
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $outFile = Join-Path $backupDir "monitor-edids-$timestamp.json"

    $items = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -eq "Device Parameters" } |
        ForEach-Object {
            $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if ($props.EDID) {
                [pscustomobject]@{
                    RegistryPath = $_.Name
                    Length = $props.EDID.Length
                    Product = "{0:X2}{1:X2}" -f $props.EDID[11], $props.EDID[10]
                    Name = ([Text.Encoding]::ASCII.GetString($props.EDID) -replace "[^ -~]", ".")
                    EdidHex = ($props.EDID | ForEach-Object { $_.ToString("X2") }) -join ""
                }
            }
        }

    $items | ConvertTo-Json -Depth 4 | Set-Content -Path $outFile -Encoding ASCII
    $outFile
}

function Find-StudioMonitor {
    $present = @(Get-PnpDevice -Class Monitor -PresentOnly | Where-Object { $_.InstanceId -match "^DISPLAY\\" })
    if ($present.Count -eq 0) {
        throw "No active monitor devices found."
    }

    if ($MonitorInstanceId) {
        $match = $present | Where-Object { $_.InstanceId -ieq $MonitorInstanceId } | Select-Object -First 1
        if (-not $match) {
            throw "Requested monitor instance is not currently present: $MonitorInstanceId"
        }
        return $match
    }

    $fallback = $present | Where-Object { $_.InstanceId -match "^DISPLAY\\MS_0001\\" } | Select-Object -First 1
    if ($fallback) {
        return $fallback
    }

    if ($present.Count -eq 1) {
        return $present[0]
    }

    if (-not $Force) {
        Write-Host "Multiple monitors are present:"
        $present | Select-Object FriendlyName,InstanceId | Format-Table -AutoSize
        throw "Disconnect other displays or pass -MonitorInstanceId with the Studio Display XDR monitor instance."
    }

    return $present[0]
}

function Install-Override([string]$deviceParametersPath, [byte[]]$edid) {
    if ($edid.Length % 128 -ne 0) {
        throw "EDID length must be a multiple of 128 bytes. Actual length: $($edid.Length)"
    }

    $overridePath = Join-Path $deviceParametersPath "EDID_OVERRIDE"
    New-Item -Path $overridePath -Force | Out-Null

    $blockCount = [int]($edid.Length / 128)
    for ($i = 0; $i -lt $blockCount; $i++) {
        $block = New-Object byte[] 128
        [Array]::Copy($edid, $i * 128, $block, 0, 128)
        New-ItemProperty -Path $overridePath -Name ([string]$i) -PropertyType Binary -Value $block -Force | Out-Null
    }

    $nameBytes = [byte[]](1) + [Text.Encoding]::ASCII.GetBytes("Studio XDR")
    New-ItemProperty -Path $overridePath -Name "CRU_Name" -PropertyType Binary -Value $nameBytes -Force | Out-Null
    New-ItemProperty -Path $overridePath -Name "CRU_Serial_Number" -PropertyType Binary -Value ([byte[]](0)) -Force | Out-Null
    New-ItemProperty -Path $overridePath -Name "CRU_Extensions" -PropertyType Binary -Value ([byte[]](0)) -Force | Out-Null

    $stale = Get-ItemProperty -Path $overridePath |
        Select-Object -ExpandProperty PSObject |
        Select-Object -ExpandProperty Properties |
        Where-Object { $_.Name -match "^\d+$" -and [int]$_.Name -ge $blockCount }

    foreach ($prop in $stale) {
        Remove-ItemProperty -Path $overridePath -Name $prop.Name -ErrorAction SilentlyContinue
    }
}

Assert-Admin

$repoRoot = Get-RepoRoot
if (-not $EdidPath) {
    $EdidPath = Join-Path $repoRoot "edid\studio-display-xdr-ae42.bin"
}

if (-not (Test-Path -LiteralPath $EdidPath)) {
    throw "EDID file not found: $EdidPath"
}

$edid = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $EdidPath))
$monitor = Find-StudioMonitor
$deviceParametersPath = Get-DisplayRegistryPath $monitor.InstanceId

Write-Host "Selected monitor:"
Write-Host "  $($monitor.FriendlyName)"
Write-Host "  $($monitor.InstanceId)"
Write-Host ""

$backupFile = Backup-MonitorEdids (Join-Path $repoRoot "backups")
Write-Host "Backed up current EDIDs:"
Write-Host "  $backupFile"
Write-Host ""

Install-Override $deviceParametersPath $edid

Write-Host "Installed Studio Display XDR EDID override."
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Reboot Windows, or restart the graphics driver."
Write-Host "2. Set display resolution to 5120 x 2880."
Write-Host "3. Set refresh rate to 120 Hz."
Write-Host "4. Run scripts\Enable-StudioXdrHdr.ps1 if HDR is not visible in Settings."
