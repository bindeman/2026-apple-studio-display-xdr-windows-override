$ErrorActionPreference = "Stop"

Write-Host "== Windows ambient-light sensor API =="
try {
    . (Join-Path $PSScriptRoot "WindowsLightSensorTools.ps1")
    $lightStatus = Get-WindowsLightSensorStatus
    $lightStatus |
        Select-Object HasSensor,Selector,CandidateCount,DeviceId,MinimumReportInterval,ReportInterval,Error |
        Format-List

    if ($lightStatus.Selected) {
        Write-Host "Selected light sensor:"
        $lightStatus.Selected | Format-List
    }

    if ($lightStatus.CurrentReading) {
        Write-Host "Current reading:"
        $lightStatus.CurrentReading | Format-List
    }

    if ($lightStatus.Candidates.Count -gt 0) {
        Write-Host "Light sensor candidates:"
        $lightStatus.Candidates |
            Sort-Object Score -Descending |
            Format-Table Name,IsEnabled,Score,Opened,Kind,Id,Error -AutoSize -Wrap
    }
}
catch {
    Write-Host "Could not query Windows.Devices.Sensors.LightSensor: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "== Apple sensor-class devices =="
$appleSensors = Get-PnpDevice -Class Sensor -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -like "*VID_05AC&PID_1116*" -or $_.FriendlyName -like "*Apple*" -or $_.FriendlyName -like "*Studio*" }

if ($appleSensors) {
    $appleSensors | Format-List Status,Class,FriendlyName,InstanceId,Problem,Service
}
else {
    Write-Host "No Apple/Studio Display sensor-class device is available to Windows."
}

Write-Host ""
Write-Host "== Studio Display XDR HID sensor usage map =="
$studioHidChildren = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -like "HID\VID_05AC&PID_1116*" })
if ($studioHidChildren.Count -eq 0) {
    Write-Host "No Studio Display XDR HID child collections are visible."
}
else {
    foreach ($hid in $studioHidChildren | Sort-Object InstanceId) {
        $hardwareIds = @(
            Get-PnpDeviceProperty -InstanceId $hid.InstanceId -ErrorAction SilentlyContinue |
                Where-Object { $_.KeyName -eq "DEVPKEY_Device_HardwareIds" } |
                Select-Object -ExpandProperty Data
        )

        [pscustomobject]@{
            Status = $hid.Status
            FriendlyName = $hid.FriendlyName
            InstanceId = $hid.InstanceId
            HidMeaning = if (($hardwareIds -join ";") -match "UP:0020_U:0041|UP:0020_U:04D1") {
                "Candidate ambient light HID collection"
            }
            elseif (($hardwareIds -join ";") -match "UP:0020_U:008A") {
                "Device orientation sensor, not ambient light"
            }
            elseif ($hid.InstanceId -like "HID\VID_05AC&PID_1116&MI_07&COL01\*" -or ($hardwareIds -join ";") -match "UP:0080_U:0001") {
                "Monitor-control HID collection; brightness value is UP:0082_U:0010"
            }
            elseif (($hardwareIds -join ";") -match "UP:0082_U:0010") {
                "Monitor brightness HID collection"
            }
            else {
                "Vendor or non-light HID collection"
            }
            HardwareIds = ($hardwareIds -join "; ")
        } | Format-List
    }

    Write-Host "Reference: HID Sensor Page 0x20 uses 0x41 for Ambient Light and 0x04D1 for Illuminance. Usage 0x008A is Device Orientation; 0x030E is Report Interval."
}

Write-Host ""
Write-Host "== Studio Display XDR ambient interface =="
$device = Get-PnpDevice -PresentOnly |
    Where-Object { $_.InstanceId -like "USB\VID_05AC&PID_1116&MI_08\*" } |
    Select-Object -First 1

if (-not $device) {
    Write-Host "USB\VID_05AC&PID_1116&MI_08 is not present."
    return
}

$device | Format-List Status,Class,FriendlyName,InstanceId,Problem,ConfigManagerErrorCode,Service

Write-Host ""
Write-Host "== Driver binding =="
Get-CimInstance Win32_PnPSignedDriver |
    Where-Object { $_.DeviceID -eq $device.InstanceId } |
    Select-Object DeviceName,DriverProviderName,DriverVersion,InfName,DriverDate,IsSigned |
    Format-List

Write-Host ""
Write-Host "== Driver problem detail =="
Get-PnpDeviceProperty -InstanceId $device.InstanceId |
    Where-Object {
        $_.KeyName -in @(
            "DEVPKEY_Device_DriverProblemDesc",
            "DEVPKEY_Device_Service",
            "DEVPKEY_Device_Class",
            "DEVPKEY_Device_DriverInfPath",
            "DEVPKEY_Device_ProblemCode",
            "DEVPKEY_Device_ProblemStatus"
        )
    } |
    Format-Table -AutoSize KeyName,Data

Write-Host ""
Write-Host "== Matching driver candidates for MI_08 =="
pnputil /enum-devices /instanceid "$($device.InstanceId)" /drivers | Write-Host

Write-Host ""
Write-Host "== Exact Studio XDR INF in driver store =="
$exactInfMatches = Select-String -Path "C:\Windows\INF\oem*.inf" -Pattern "USB\\VID_05AC&PID_1116(&REV_[0-9A-Fa-f]+)?&MI_08|Studio Display XDR Ambient|6F94F6F0-7B76-4DFB-AD85-905E20C82D9D" -List -ErrorAction SilentlyContinue
if ($exactInfMatches) {
    $exactInfMatches | Select-Object Path,LineNumber,Line | Format-List
}
else {
    Write-Host "No installed OEM INF targets USB\VID_05AC&PID_1116&REV_*&MI_08 or USB\VID_05AC&PID_1116&MI_08."
}

Write-Host ""
Write-Host "== MI_08 filter drivers =="
$deviceKey = Join-Path "HKLM:\SYSTEM\CurrentControlSet\Enum" $device.InstanceId
$instanceFilters = Get-ItemProperty -Path $deviceKey -ErrorAction SilentlyContinue |
    Select-Object UpperFilters,LowerFilters,Service,Driver
if ($instanceFilters) {
    $instanceFilters | Format-List
    if (-not $instanceFilters.UpperFilters -and -not $instanceFilters.LowerFilters) {
        Write-Host "No UpperFilters or LowerFilters are registered on the MI_08 device instance."
    }
}
else {
    Write-Host "Could not read the MI_08 device-instance registry filters."
}

Write-Host ""
Write-Host "== Suggested exact libusb filter target =="
$hardwareIds = @(
    Get-PnpDeviceProperty -InstanceId $device.InstanceId -ErrorAction SilentlyContinue |
        Where-Object { $_.KeyName -eq "DEVPKEY_Device_HardwareIds" } |
        Select-Object -ExpandProperty Data
)
$filterTarget = $hardwareIds | Where-Object { $_ -like "USB\VID_05AC&PID_1116&REV_*&MI_08" } | Select-Object -First 1
if (-not $filterTarget) {
    $filterTarget = "USB\VID_05AC&PID_1116&MI_08"
}

$filterHelpers = @(
    "$env:USERPROFILE\usb_driver\amd64\install-filter.exe",
    "$env:USERPROFILE\Downloads\libusb-win32-bin-1.4.0.0\bin\amd64\install-filter-win.exe",
    "$env:USERPROFILE\Downloads\libusb-win32-bin-1.4.0.0\bin\amd64\install-filter.exe"
) | Where-Object { Test-Path -LiteralPath $_ }

Write-Host "Target hardware ID: $filterTarget"
if ($filterHelpers) {
    $filterHelpers | ForEach-Object { Write-Host "Filter helper: $_" }
    Write-Host "Guarded launcher: Install-LibUsb-Ambient-Filter.cmd"
    Write-Host "This requires administrator approval and a reboot; it should target only the MI_08 interface above."
}
else {
    Write-Host "No libusb-win32 install-filter helper was found in the known locations."
}

Write-Host ""
Write-Host "== libusb/libwdi packages =="
$libwdiMatches = Select-String -Path "C:\Windows\INF\oem*.inf" -Pattern "libwdi|libusb-win32|WinUSB_Generic_Device|LIBUSB0|USB\\VID_05AC&PID_1116&MI_08" -List -ErrorAction SilentlyContinue
if ($libwdiMatches) {
    $libwdiMatches | Select-Object Path,LineNumber,Line | Format-List
    if ($device.Service -ne "WinUSB") {
        Write-Host "A generic USB package may be installed, but MI_08 is not bound to WinUSB. For the SDBC-style libusb path, MI_08 also needs an exact libusb-win32/libusb-compatible filter."
    }
}
else {
    Write-Host "No libusb/libwdi USB package is visible in the driver store."
}

Write-Host ""
Write-Host "== Ambient packet probe =="
& (Join-Path $PSScriptRoot "Test-StudioXdrAmbientConnector.ps1")

Write-Host ""
Write-Host "== Ambient libusb probe =="
& (Join-Path $PSScriptRoot "Test-StudioXdrLibUsbAmbient.ps1")
