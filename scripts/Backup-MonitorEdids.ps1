$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$backupDir = Join-Path $repoRoot "backups"
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
Write-Host "Saved EDID backup:"
Write-Host $outFile
