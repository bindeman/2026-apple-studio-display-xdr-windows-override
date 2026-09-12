$ErrorActionPreference = "Stop"

Write-Host "== Active video controllers =="
Get-CimInstance -ClassName Win32_VideoController |
    Select-Object Name,VideoModeDescription,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate,CurrentBitsPerPixel,DriverVersion |
    Format-Table -AutoSize

Write-Host ""
Write-Host "== Active Studio Display XDR DisplayConfig target =="
$colorStatusScript = Join-Path $PSScriptRoot "Get-StudioXdrColorStatus.ps1"
if (Test-Path -LiteralPath $colorStatusScript) {
    & $colorStatusScript
}
else {
    Write-Host "Get-StudioXdrColorStatus.ps1 not found."
}

Write-Host ""
Write-Host "== Present monitors =="
Get-PnpDevice -Class Monitor -PresentOnly |
    Select-Object FriendlyName,Status,InstanceId |
    Format-Table -AutoSize

Write-Host ""
Write-Host "== Studio Display XDR USB device =="
Get-PnpDevice -PresentOnly |
    Where-Object { $_.InstanceId -match "VID_05AC&PID_1116|USB4\\VID_8087&PID_5786" -or $_.FriendlyName -match "Studio Display XDR|Studio Display" } |
    Select-Object Class,FriendlyName,Status,InstanceId |
    Format-Table -AutoSize

Write-Host ""
Write-Host "== Monitor source modes exposed through WMI =="
Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorListedSupportedSourceModes |
    ForEach-Object {
        $name = $_.InstanceName
        $_.MonitorSourceModes | ForEach-Object {
            [pscustomobject]@{
                InstanceName = $name
                Width = $_.HorizontalActivePixels
                Height = $_.VerticalActivePixels
                VerticalHz = if ($_.VerticalRefreshRateDenominator) {
                    [math]::Round($_.VerticalRefreshRateNumerator / $_.VerticalRefreshRateDenominator, 3)
                } else {
                    $null
                }
                PixelClockMHz = [math]::Round($_.PixelClockRate / 1000000, 3)
            }
        }
    } |
    Sort-Object InstanceName,Width,Height,VerticalHz |
    Format-Table -AutoSize
