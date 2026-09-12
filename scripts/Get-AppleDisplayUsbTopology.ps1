param(
    [string[]]$ProductId = @("1116", "1114", "1118", "9243"),
    [switch]$AllAppleUsb
)

$ErrorActionPreference = "Stop"

$productNames = @{
    "1116" = "Studio Display XDR"
    "1114" = "Studio Display"
    "1118" = "Studio Display Gen 2"
    "9243" = "Pro Display XDR"
}

function Get-DevicePropertyMap {
    param(
        [string]$InstanceId
    )

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

    return [string]$Value
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

$pidPattern = if ($AllAppleUsb) { "[0-9A-Fa-f]{4}" } else { ($ProductId | ForEach-Object { [regex]::Escape($_) }) -join "|" }
$devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match "VID_05AC&PID_($pidPattern)" })

if ($devices.Count -eq 0) {
    Write-Host "No matching Apple display USB devices are present."
    return
}

$driverById = @{}
foreach ($driver in (Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue)) {
    if ($driver.DeviceID -and -not $driverById.ContainsKey($driver.DeviceID)) {
        $driverById[$driver.DeviceID] = $driver
    }
}

$rows = foreach ($device in $devices) {
    $appleProductId = Get-AppleDisplayPid $device.InstanceId
    $driver = $driverById[$device.InstanceId]
    $properties = Get-DevicePropertyMap $device.InstanceId
    $containerId = $properties["DEVPKEY_Device_ContainerId"]
    $locationPaths = $properties["DEVPKEY_Device_LocationPaths"]
    $hardwareIds = $properties["DEVPKEY_Device_HardwareIds"]
    $compatibleIds = $properties["DEVPKEY_Device_CompatibleIds"]
    $busReported = $properties["DEVPKEY_Device_BusReportedDeviceDesc"]
    $problemDesc = $properties["DEVPKEY_Device_DriverProblemDesc"]
    $problemCode = $properties["DEVPKEY_Device_ProblemCode"]
    $service = $properties["DEVPKEY_Device_Service"]
    $infPath = $properties["DEVPKEY_Device_DriverInfPath"]

    [pscustomobject]@{
        ProductId = $appleProductId
        Product = if ($productNames.ContainsKey($appleProductId)) { $productNames[$appleProductId] } else { "Apple USB device" }
        Interface = Get-UsbInterfaceNumber $device.InstanceId
        Class = $device.Class
        Status = $device.Status
        FriendlyName = $device.FriendlyName
        BusReportedName = Format-PropertyValue $busReported
        Service = Format-PropertyValue $service
        ProblemCode = Format-PropertyValue $problemCode
        Problem = Format-PropertyValue $problemDesc
        DriverProvider = $driver.DriverProviderName
        DriverInf = if ($driver.InfName) { $driver.InfName } else { Format-PropertyValue $infPath }
        DriverVersion = $driver.DriverVersion
        ContainerId = Format-PropertyValue $containerId
        LocationPaths = Format-PropertyValue $locationPaths
        HardwareIds = Format-PropertyValue $hardwareIds
        CompatibleIds = Format-PropertyValue $compatibleIds
        InstanceId = $device.InstanceId
    }
}

Write-Host "== Apple display USB topology summary =="
$rows |
    Sort-Object ProductId,Interface,Class,FriendlyName |
    Select-Object Product,ProductId,Interface,Class,Status,FriendlyName,Service,ProblemCode,DriverProvider,DriverInf |
    Format-Table -AutoSize

Write-Host ""
Write-Host "== Apple display USB interface details =="
foreach ($row in ($rows | Sort-Object ProductId,Interface,Class,FriendlyName)) {
    $row | Format-List Product,ProductId,Interface,Class,Status,FriendlyName,BusReportedName,Service,ProblemCode,Problem,DriverProvider,DriverInf,DriverVersion,ContainerId,LocationPaths,HardwareIds,CompatibleIds,InstanceId
}

Write-Host ""
Write-Host "== Studio Display XDR MI_08 focus =="
$mi08 = @($rows | Where-Object { $_.ProductId -eq "1116" -and $_.Interface -eq "MI_08" })
if ($mi08.Count -eq 0) {
    Write-Host "No Studio Display XDR MI_08 interface is present."
}
else {
    $mi08 | Format-List Product,Interface,Status,FriendlyName,BusReportedName,Service,ProblemCode,Problem,DriverProvider,DriverInf,HardwareIds,CompatibleIds,InstanceId
}
