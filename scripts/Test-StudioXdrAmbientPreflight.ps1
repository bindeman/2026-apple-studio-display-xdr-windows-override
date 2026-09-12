param(
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$generated = Get-Date
$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [string]$Area,
        [string]$Status,
        [string]$Detail
    )

    $script:checks.Add([pscustomobject]@{
        Area = $Area
        Status = $Status
        Detail = $Detail
    })
}

function Get-DeviceHardwareIds {
    param([string]$InstanceId)

    @(
        Get-PnpDeviceProperty -InstanceId $InstanceId -ErrorAction SilentlyContinue |
            Where-Object { $_.KeyName -eq "DEVPKEY_Device_HardwareIds" } |
            Select-Object -ExpandProperty Data
    )
}

function Get-DeviceProblemDetail {
    param([string]$InstanceId)

    $problem = Get-PnpDeviceProperty -InstanceId $InstanceId -ErrorAction SilentlyContinue |
        Where-Object { $_.KeyName -eq "DEVPKEY_Device_DriverProblemDesc" } |
        Select-Object -ExpandProperty Data -First 1

    if ([string]::IsNullOrWhiteSpace($problem)) {
        return ""
    }

    $problem
}

function Test-WindowsAmbientSensor {
    try {
        . (Join-Path $PSScriptRoot "WindowsLightSensorTools.ps1")
        $status = Get-WindowsLightSensorStatus
        if (-not $status.HasSensor) {
            $detail = "No Windows LightSensor is exposed. Candidate count: $($status.CandidateCount)."
            if (-not [string]::IsNullOrWhiteSpace($status.Error)) {
                $detail = "$detail Error: $($status.Error)"
            }
            Add-Check "Windows ambient sensor" "Info" $detail
            return $false
        }

        $name = if ($status.Selected -and -not [string]::IsNullOrWhiteSpace($status.Selected.Name)) { $status.Selected.Name } else { "Windows ambient light sensor" }
        $detail = "$name is available: $($status.DeviceId)"
        if ($status.CurrentReading -and $null -ne $status.CurrentReading.IlluminanceInLux) {
            $detail = "$detail, $([math]::Round($status.CurrentReading.IlluminanceInLux, 1)) lux"
        }
        Add-Check "Windows ambient sensor" "Ready" $detail
        return $true
    }
    catch {
        Add-Check "Windows ambient sensor" "Info" "Could not query LightSensor API: $($_.Exception.Message)"
        return $false
    }
}

function Test-StudioCameraFallback {
    $camera = Get-PnpDevice -PresentOnly -Class Camera,Image -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match "VID_05AC&PID_1116" -or $_.FriendlyName -match "Studio Display Camera" } |
        Select-Object -First 1

    if ($camera -and $camera.Status -eq "OK") {
        Add-Check "Camera fallback" "Ready" "$($camera.FriendlyName) is available for opt-in automatic brightness fallback."
        return $true
    }

    if ($camera) {
        Add-Check "Camera fallback" "Warn" "$($camera.FriendlyName) is present but reports $($camera.Status)."
        return $false
    }

    Add-Check "Camera fallback" "Info" "No Studio Display Camera fallback device is present."
    return $false
}

function Test-StudioMi08Binding {
    $device = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like "USB\VID_05AC&PID_1116&MI_08\*" } |
        Select-Object -First 1

    if (-not $device) {
        Add-Check "Native MI_08 interface" "Warn" "USB\VID_05AC&PID_1116&MI_08 is not present."
        return $null
    }

    $driver = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceID -eq $device.InstanceId } |
        Select-Object -First 1
    $problem = Get-DeviceProblemDetail -InstanceId $device.InstanceId
    $driverText = if ($driver) { "$($driver.InfName) / $($driver.DriverProviderName)" } else { "unknown driver" }
    $detail = "Status=$($device.Status), Service=$($device.Service), Driver=$driverText"
    if (-not [string]::IsNullOrWhiteSpace($problem)) {
        $detail = "$detail, Problem=$problem"
    }

    $mi08Ready = $device.Status -eq "OK" -and $device.Service -match "WinUSB|libusb|libusb0"
    $status = if ($mi08Ready) { "Ready" } elseif ($device.Service -eq "HidUsb") { "NeedsBinding" } else { "Warn" }
    Add-Check "Native MI_08 interface" $status $detail

    $hardwareIds = Get-DeviceHardwareIds -InstanceId $device.InstanceId
    $filterTarget = $hardwareIds | Where-Object { $_ -like "USB\VID_05AC&PID_1116&REV_*&MI_08" } | Select-Object -First 1
    if (-not $filterTarget) {
        $filterTarget = "USB\VID_05AC&PID_1116&MI_08"
    }
    Add-Check "Exact filter target" "Info" $filterTarget

    $deviceKey = Join-Path "HKLM:\SYSTEM\CurrentControlSet\Enum" $device.InstanceId
    $filters = Get-ItemProperty -Path $deviceKey -ErrorAction SilentlyContinue |
        Select-Object -First 1 UpperFilters,LowerFilters
    $upper = @($filters.UpperFilters | Where-Object { $_ })
    $lower = @($filters.LowerFilters | Where-Object { $_ })
    $filterText = (@($upper + $lower) -join ", ")
    if ([string]::IsNullOrWhiteSpace($filterText)) {
        Add-Check "MI_08 libusb filter" "Missing" "No UpperFilters or LowerFilters are registered on the MI_08 device instance."
    }
    elseif ($filterText -match "libusb|libusb0") {
        Add-Check "MI_08 libusb filter" "Ready" $filterText
    }
    else {
        Add-Check "MI_08 libusb filter" "Warn" $filterText
    }

    $device
}

function Test-AmbientDriverTarget {
    $script = Join-Path $PSScriptRoot "Test-StudioXdrAmbientDriverTarget.ps1"
    if (-not (Test-Path -LiteralPath $script)) {
        Add-Check "Ambient WinUSB package target" "Info" "Test-StudioXdrAmbientDriverTarget.ps1 was not found."
        return
    }

    try {
        $json = & $script -Json
        $target = $json | ConvertFrom-Json
        $status = switch ($target.Status) {
            "ConnectorActive" { "Ready" }
            "PackageMismatch" { "Warn" }
            "MissingDevice" { "Warn" }
            default { "Info" }
        }

        $driverNames = @($target.PnpUtilMatchingDriverNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $bestDriverNames = @($target.PnpUtilBestRankedDriverNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $driverSelection = ""
        if ($driverNames.Count -gt 0) {
            $driverSelection = " Windows matching drivers: $($driverNames -join ', ')."
        }
        if ($bestDriverNames.Count -gt 0) {
            $driverSelection = "$driverSelection Best-ranked/installed: $($bestDriverNames -join ', ')."
        }

        $detail = "$($target.Summary) Target=$($target.TargetHardwareId); Driver=$($target.DriverInf); Service=$($target.Service).$driverSelection"
        Add-Check "Ambient WinUSB package target" $status $detail
    }
    catch {
        Add-Check "Ambient WinUSB package target" "Warn" "Could not validate ambient driver target: $($_.Exception.Message)"
    }
}

function Test-StudioHidSensorMap {
    $hidDevices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -like "HID\VID_05AC&PID_1116*" })

    if ($hidDevices.Count -eq 0) {
        Add-Check "Studio HID sensor map" "Info" "No Studio Display XDR HID child collections are visible."
        return
    }

    $withHardwareIds = foreach ($hid in $hidDevices) {
        [pscustomobject]@{
            Device = $hid
            HardwareIds = @(Get-DeviceHardwareIds -InstanceId $hid.InstanceId)
        }
    }

    $ambientCollections = @($withHardwareIds | Where-Object {
        ($_.HardwareIds -join ";") -match "UP:0020_U:0041|UP:0020_U:04D1"
    })
    if ($ambientCollections.Count -gt 0) {
        $details = $ambientCollections |
            ForEach-Object { "$($_.Device.FriendlyName) ($($_.Device.Status)) $($_.Device.InstanceId)" }
        Add-Check "Standard HID ambient collection" "Ready" ($details -join "; ")
    }
    else {
        Add-Check "Standard HID ambient collection" "Info" "No Sensor Page ambient-light collection is exposed as HID UP:0020_U:0041 and no illuminance field UP:0020_U:04D1 is visible."
    }

    $orientationCollections = @($withHardwareIds | Where-Object {
        $_.Device.InstanceId -like "HID\VID_05AC&PID_1116&MI_09*" -or
        ($_.HardwareIds -join ";") -match "UP:0020_U:008A"
    })
    if ($orientationCollections.Count -gt 0) {
        $details = $orientationCollections |
            ForEach-Object { "$($_.Device.FriendlyName) ($($_.Device.Status)) $($_.Device.InstanceId)" }
        Add-Check "MI_09 orientation sensor" "Info" "Present but not an ambient-light path: $($details -join '; ')"
    }
}

function Test-AmbientPacketProbe {
    param(
        [string]$Area,
        [string]$ScriptName
    )

    $script = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path -LiteralPath $script)) {
        Add-Check $Area "Info" "$ScriptName was not found."
        return $false
    }

    try {
        $text = (& $script *>&1 | Out-String -Width 240).Trim()
        if ($text -match "Ambient=\d+") {
            $line = ($text -split "`r?`n" | Where-Object { $_ -match "Ambient=\d+" } | Select-Object -First 1).Trim()
            Add-Check $Area "Ready" $line
            return $true
        }

        $summary = ($text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1).Trim()
        if ([string]::IsNullOrWhiteSpace($summary)) {
            $summary = "No packet returned."
        }
        Add-Check $Area "NotReady" $summary
        return $false
    }
    catch {
        Add-Check $Area "NotReady" $_.Exception.Message
        return $false
    }
}

if (-not $Json) {
    Write-Host "Studio Display XDR ambient preflight"
    Write-Host "Generated: $($generated.ToString("o"))"
    Write-Host ""
}

$hasWindowsSensor = Test-WindowsAmbientSensor
$mi08 = Test-StudioMi08Binding
Test-AmbientDriverTarget
Test-StudioHidSensorMap
$winUsbReady = Test-AmbientPacketProbe -Area "MI_08 WinUSB packet probe" -ScriptName "Test-StudioXdrAmbientConnector.ps1"
$libUsbReady = Test-AmbientPacketProbe -Area "MI_08 libusb packet probe" -ScriptName "Test-StudioXdrLibUsbAmbient.ps1"
$cameraReady = Test-StudioCameraFallback

if ($hasWindowsSensor) {
    $verdict = "Standard Windows ambient-light sensor path is ready."
}
elseif ($winUsbReady) {
    $verdict = "Native Studio Display XDR MI_08 WinUSB sensor path is returning packets."
}
elseif ($libUsbReady) {
    $verdict = "Native Studio Display XDR MI_08 libusb sensor path is returning packets."
}
elseif ($cameraReady) {
    $verdict = "Camera fallback is ready; native MI_08 auto-brightness is not ready yet."
}
else {
    $verdict = "No automatic-brightness source is ready yet."
}

$nextSteps = [System.Collections.Generic.List[string]]::new()
if ($winUsbReady -or $libUsbReady -or $hasWindowsSensor) {
    $nextSteps.Add("Open Studio Display XDR and enable Automatically adjust brightness.")
}
elseif ($mi08 -and ($checks | Where-Object { $_.Area -eq "Native MI_08 interface" -and $_.Status -eq "NeedsBinding" })) {
    $nextSteps.Add("The native sensor interface is still on HidUsb/input.inf. Use the guarded MI_08 WinUSB/libusb experiment only if you are ready to change the exact MI_08 driver/filter binding.")
    $nextSteps.Add("Run Get-StudioXdrAmbientStatus.ps1 for the full driver-store and packet-probe output.")
}
elseif ($mi08) {
    $nextSteps.Add("Review the MI_08 driver/filter status above, then run Get-StudioXdrAmbientStatus.ps1 for full details.")
}
else {
    $nextSteps.Add("Reconnect the Studio Display XDR over Thunderbolt/USB4, then rerun this preflight.")
}

if ($cameraReady -and -not ($hasWindowsSensor -or $winUsbReady -or $libUsbReady)) {
    $nextSteps.Add("Camera fallback can be used today from the app's automatic-brightness toggle.")
}

$exactTarget = $checks |
    Where-Object { $_.Area -eq "Exact filter target" } |
    Select-Object -ExpandProperty Detail -First 1

if ($Json) {
    [pscustomobject]@{
        Generated = $generated.ToString("o")
        Summary = [pscustomobject]@{
            HasWindowsSensor = [bool]$hasWindowsSensor
            WinUsbReady = [bool]$winUsbReady
            LibUsbReady = [bool]$libUsbReady
            CameraReady = [bool]$cameraReady
            HasMi08 = $null -ne $mi08
            ExactFilterTarget = $exactTarget
            Verdict = $verdict
            NextSteps = @($nextSteps)
        }
        Checks = @($checks)
    } | ConvertTo-Json -Depth 6
    return
}

$checks | Format-Table Area,Status,Detail -AutoSize -Wrap

Write-Host ""
Write-Host "Verdict: $verdict"

Write-Host ""
Write-Host "Next steps:"
foreach ($nextStep in $nextSteps) {
    Write-Host "- $nextStep"
}
