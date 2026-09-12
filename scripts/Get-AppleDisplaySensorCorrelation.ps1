param(
    [switch]$AllSensors,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$productNames = @{
    "1116" = "Studio Display XDR"
    "1114" = "Studio Display"
    "1118" = "Studio Display Gen 2"
    "9243" = "Pro Display XDR"
}

function Get-DevicePropertyMap {
    param([string]$InstanceId)

    $map = @{}
    try {
        foreach ($property in (Get-PnpDeviceProperty -InstanceId $InstanceId -ErrorAction Stop)) {
            $map[$property.KeyName] = $property.Data
        }
    }
    catch {
    }

    $map
}

function Format-PropertyValue {
    param($Value)

    if ($null -eq $Value) {
        return ""
    }

    if ($Value -is [array]) {
        return ($Value -join "; ")
    }

    [string]$Value
}

function Get-AppleDisplayPid {
    param([string]$InstanceId)

    $match = [regex]::Match($InstanceId, "VID_05AC&PID_([0-9A-Fa-f]{4})")
    if ($match.Success) {
        return $match.Groups[1].Value.ToUpperInvariant()
    }

    $null
}

function Get-UsbInterfaceNumber {
    param([string]$InstanceId)

    $match = [regex]::Match($InstanceId, "&MI_([0-9A-Fa-f]{2})")
    if ($match.Success) {
        return "MI_$($match.Groups[1].Value.ToUpperInvariant())"
    }

    ""
}

$appleDevices = @(
    Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match "VID_05AC&PID_(1116|1114|1118|9243)" } |
        ForEach-Object {
            $applePid = Get-AppleDisplayPid $_.InstanceId
            $properties = Get-DevicePropertyMap $_.InstanceId
            [pscustomobject]@{
                Product = if ($productNames.ContainsKey($applePid)) { $productNames[$applePid] } else { "Apple display" }
                ProductId = $applePid
                Interface = Get-UsbInterfaceNumber $_.InstanceId
                Class = $_.Class
                Status = $_.Status
                FriendlyName = $_.FriendlyName
                ContainerId = Format-PropertyValue $properties["DEVPKEY_Device_ContainerId"]
                HardwareIds = Format-PropertyValue $properties["DEVPKEY_Device_HardwareIds"]
                InstanceId = $_.InstanceId
            }
        }
)

$displayContainers = @(
    $appleDevices |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.ContainerId) } |
        Group-Object ProductId,ContainerId |
        ForEach-Object {
            $first = $_.Group | Select-Object -First 1
            [pscustomobject]@{
                Product = $first.Product
                ProductId = $first.ProductId
                ContainerId = $first.ContainerId
                Interfaces = (($_.Group | Where-Object { $_.Interface } | Select-Object -ExpandProperty Interface -Unique | Sort-Object) -join ", ")
                DeviceCount = $_.Group.Count
            }
        }
)

$containerById = @{}
foreach ($container in $displayContainers) {
    if (-not $containerById.ContainsKey($container.ContainerId)) {
        $containerById[$container.ContainerId] = [System.Collections.Generic.List[object]]::new()
    }
    $containerById[$container.ContainerId].Add($container)
}

$driversById = @{}
foreach ($driver in (Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue)) {
    if ($driver.DeviceID -and -not $driversById.ContainsKey($driver.DeviceID)) {
        $driversById[$driver.DeviceID] = $driver
    }
}

$sensorRows = @(
    Get-PnpDevice -PresentOnly -Class Sensor -ErrorAction SilentlyContinue |
        ForEach-Object {
            $properties = Get-DevicePropertyMap $_.InstanceId
            $containerId = Format-PropertyValue $properties["DEVPKEY_Device_ContainerId"]
            $hardwareIds = Format-PropertyValue $properties["DEVPKEY_Device_HardwareIds"]
            $problem = Format-PropertyValue $properties["DEVPKEY_Device_DriverProblemDesc"]
            $service = Format-PropertyValue $properties["DEVPKEY_Device_Service"]
            $driver = $driversById[$_.InstanceId]
            $owners = if ($containerById.ContainsKey($containerId)) {
                ($containerById[$containerId] | ForEach-Object { "$($_.Product) ($($_.ProductId))" }) -join "; "
            }
            else {
                ""
            }

            $text = "$($_.FriendlyName) $($_.InstanceId) $hardwareIds"
            $relevant = $AllSensors -or
                -not [string]::IsNullOrWhiteSpace($owners) -or
                $text -match "Apple|Studio|Display|XDR|05AC|Ambient|Light"

            if ($relevant) {
                [pscustomobject]@{
                    Owner = $owners
                    Status = $_.Status
                    FriendlyName = $_.FriendlyName
                    Service = if ($service) { $service } else { $_.Service }
                    DriverInf = if ($driver) { $driver.InfName } else { "" }
                    ContainerId = $containerId
                    IsAmbientHid = $hardwareIds -match "UP:0020_U:0041|UP:0020_U:04D1|Ambient|Light"
                    IsOrientationHid = $hardwareIds -match "UP:0020_U:008A"
                    Problem = $problem
                    HardwareIds = $hardwareIds
                    InstanceId = $_.InstanceId
                }
            }
        }
)

$winRt = $null
try {
    . (Join-Path $PSScriptRoot "WindowsLightSensorTools.ps1")
    $winRt = Get-WindowsLightSensorStatus
}
catch {
    $winRt = [pscustomobject]@{
        HasSensor = $false
        CandidateCount = 0
        Error = $_.Exception.Message
        Candidates = @()
        Selected = $null
    }
}

$ambientSensorRows = @($sensorRows | Where-Object { $_.IsAmbientHid })
$appleOwnedSensors = @($sensorRows | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Owner) })
$summary = [pscustomobject]@{
    AppleDisplayContainerCount = $displayContainers.Count
    SensorDeviceCount = $sensorRows.Count
    AppleOwnedSensorCount = $appleOwnedSensors.Count
    AmbientHidSensorCount = $ambientSensorRows.Count
    WindowsLightSensorCandidateCount = $winRt.CandidateCount
    WindowsLightSensorReady = [bool]$winRt.HasSensor
    SelectedWindowsLightSensor = if ($winRt.Selected) { $winRt.Selected.Name } else { "" }
}

if ($Json) {
    [pscustomobject]@{
        Summary = $summary
        AppleDisplayContainers = @($displayContainers)
        SensorDevices = @($sensorRows)
        WindowsLightSensor = $winRt
    } | ConvertTo-Json -Depth 8
    return
}

Write-Host "Apple display sensor correlation"
Write-Host ""
Write-Host "== Summary =="
$summary | Format-List

Write-Host ""
Write-Host "== Apple display containers =="
if ($displayContainers.Count -eq 0) {
    Write-Host "No Apple display USB containers found."
}
else {
    $displayContainers | Sort-Object ProductId,ContainerId | Format-Table Product,ProductId,ContainerId,Interfaces,DeviceCount -AutoSize -Wrap
}

Write-Host ""
Write-Host "== Windows LightSensor API candidates =="
$winRt |
    Select-Object HasSensor,CandidateCount,DeviceId,MinimumReportInterval,ReportInterval,Error |
    Format-List
if ($winRt.Selected) {
    Write-Host "Selected Windows LightSensor:"
    $winRt.Selected | Format-List
}
if ($winRt.Candidates.Count -gt 0) {
    $winRt.Candidates | Sort-Object Score -Descending | Format-Table Name,IsEnabled,Score,Opened,Kind,Id,Error -AutoSize -Wrap
}

Write-Host ""
Write-Host "== Sensor devices correlated to Apple display containers =="
if ($sensorRows.Count -eq 0) {
    Write-Host "No relevant Sensor-class devices found."
}
else {
    $sensorRows | Sort-Object Owner,FriendlyName | Format-Table Owner,Status,FriendlyName,Service,DriverInf,IsAmbientHid,IsOrientationHid,ContainerId -AutoSize -Wrap

    Write-Host ""
    Write-Host "Sensor details:"
    foreach ($sensor in ($sensorRows | Sort-Object Owner,FriendlyName)) {
        $sensor | Format-List Owner,Status,FriendlyName,Service,DriverInf,IsAmbientHid,IsOrientationHid,Problem,HardwareIds,InstanceId
    }
}

Write-Host ""
Write-Host "== Interpretation =="
if ($winRt.HasSensor) {
    Write-Host "A Windows LightSensor is available and can be used by the app's automatic-brightness source priority."
}
elseif ($ambientSensorRows.Count -gt 0) {
    Write-Host "A Sensor-class ambient-looking HID device exists, but WinRT LightSensor did not expose a usable source."
}
elseif ($appleOwnedSensors.Count -gt 0) {
    Write-Host "Apple-owned Sensor-class devices exist, but none currently look like ambient-light sensors."
}
else {
    Write-Host "No Apple display ambient sensor is exposed through Windows Sensor-class or WinRT LightSensor APIs."
}
