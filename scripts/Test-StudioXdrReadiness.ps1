param(
    [switch]$Detailed,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$generated = Get-Date
$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [string]$Area,
        [ValidateSet("Pass", "Warn", "Fail", "Info")]
        [string]$Status,
        [string]$Detail
    )

    $script:checks.Add([pscustomobject]@{
        Area = $Area
        Status = $Status
        Detail = $Detail
    })
}

function Get-FieldValue {
    param(
        [string]$Text,
        [string]$Name
    )

    $match = [regex]::Match($Text, "(?m)^\s*$([regex]::Escape($Name))\s*:\s*(.+?)\s*$")
    if ($match.Success) {
        return $match.Groups[1].Value.Trim()
    }

    return $null
}

if (-not $Json) {
    Write-Host "Studio Display XDR readiness check"
    Write-Host "Generated: $($generated.ToString("o"))"
    Write-Host ""
}

$colorStatusText = ""
try {
    $colorStatusText = (& (Join-Path $PSScriptRoot "Get-StudioXdrColorStatus.ps1") *>&1 | Out-String -Width 220)
    $monitorName = Get-FieldValue -Text $colorStatusText -Name "MonitorName"
    $sourceWidth = [int](Get-FieldValue -Text $colorStatusText -Name "SourceWidth")
    $sourceHeight = [int](Get-FieldValue -Text $colorStatusText -Name "SourceHeight")
    $targetWidth = [int](Get-FieldValue -Text $colorStatusText -Name "TargetActiveWidth")
    $targetHeight = [int](Get-FieldValue -Text $colorStatusText -Name "TargetActiveHeight")
    $refresh = [double](Get-FieldValue -Text $colorStatusText -Name "TargetRefreshHz")
    $advancedColorSupported = Get-FieldValue -Text $colorStatusText -Name "AdvancedColorSupported"
    $advancedColorEnabled = Get-FieldValue -Text $colorStatusText -Name "AdvancedColorEnabled"
    $bitsPerChannel = Get-FieldValue -Text $colorStatusText -Name "BitsPerColorChannel"

    if ($monitorName) {
        Add-Check "Display target" "Pass" "$monitorName on $((Get-FieldValue -Text $colorStatusText -Name "GdiDeviceName"))"
    }
    else {
        Add-Check "Display target" "Fail" "No active Studio Display XDR DisplayConfig target found."
    }

    $width = if ($sourceWidth -gt 0) { $sourceWidth } else { $targetWidth }
    $height = if ($sourceHeight -gt 0) { $sourceHeight } else { $targetHeight }
    if ($width -eq 5120 -and $height -eq 2880) {
        Add-Check "Native resolution" "Pass" "$width x $height active."
    }
    elseif ($width -gt 0 -and $height -gt 0) {
        Add-Check "Native resolution" "Warn" "$width x $height active; expected 5120 x 2880."
    }
    else {
        Add-Check "Native resolution" "Fail" "Could not determine active resolution."
    }

    if ($refresh -ge 119) {
        Add-Check "Refresh rate" "Pass" "$refresh Hz active."
    }
    elseif ($refresh -gt 0) {
        Add-Check "Refresh rate" "Warn" "$refresh Hz active; 120 Hz may be available but is not active."
    }
    else {
        Add-Check "Refresh rate" "Warn" "Could not determine active refresh rate."
    }

    if ($advancedColorSupported -eq "True") {
        $hdrState = if ($advancedColorEnabled -eq "True") { "on" } else { "off" }
        Add-Check "HDR / Advanced Color" "Info" "Supported, currently $hdrState; Windows reports $bitsPerChannel bits per channel."
    }
    else {
        Add-Check "HDR / Advanced Color" "Warn" "Advanced Color is not reported as supported by the active signal."
    }
}
catch {
    Add-Check "Display target" "Fail" "Could not read DisplayConfig status: $($_.Exception.Message)"
}

try {
    $modeTest = & (Join-Path $PSScriptRoot "Set-StudioXdrDisplayMode.ps1") -RefreshRate 120 -TestOnly
    if ($modeTest -match "test success; result=0") {
        Add-Check "5K120 mode test" "Pass" $modeTest
    }
    else {
        Add-Check "5K120 mode test" "Warn" $modeTest
    }
}
catch {
    Add-Check "5K120 mode test" "Warn" "Could not run mode test: $($_.Exception.Message)"
}

try {
    . (Join-Path $PSScriptRoot "AppleDisplayBrightnessCore.ps1")
    $brightnessDevice = @(Get-AppleDisplayBrightnessDevice | Where-Object { $_.ProductId -eq "1116" } | Select-Object -First 1)
    if ($brightnessDevice.Count -gt 0) {
        Add-Check "Brightness HID" "Pass" "Studio Display XDR brightness endpoint found at $($brightnessDevice[0].Percent)%."
    }
    else {
        Add-Check "Brightness HID" "Warn" "Studio Display XDR brightness endpoint was not found. Use Thunderbolt/USB4, not video-only adapters."
    }
}
catch {
    Add-Check "Brightness HID" "Warn" "Could not read brightness HID: $($_.Exception.Message)"
}

try {
    $camera = Get-PnpDevice -PresentOnly -Class Camera -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match "Studio Display" -or $_.InstanceId -match "VID_05AC&PID_1116" } |
        Select-Object -First 1
    $audio = Get-PnpDevice -PresentOnly -Class AudioEndpoint,MEDIA -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match "Studio Display" -or $_.InstanceId -match "VID_05AC&PID_1116" }

    if ($camera) {
        Add-Check "Camera" "Pass" "$($camera.FriendlyName) is present."
    }
    else {
        Add-Check "Camera" "Warn" "Studio Display Camera was not found."
    }

    $speaker = $audio | Where-Object { $_.FriendlyName -match "Speaker|Studio Display Audio" } | Select-Object -First 1
    $microphone = $audio | Where-Object { $_.FriendlyName -match "Microphone|Studio Display Audio" } | Select-Object -First 1
    Add-Check "Audio" ($(if ($speaker -and $microphone) { "Pass" } else { "Warn" })) ($(if ($speaker -and $microphone) { "Studio Display speaker/microphone endpoints are present." } else { "Studio Display speaker or microphone endpoint was not found." }))
}
catch {
    Add-Check "Camera/audio" "Warn" "Could not query camera/audio devices: $($_.Exception.Message)"
}

try {
    . (Join-Path $PSScriptRoot "WindowsLightSensorTools.ps1")
    $lightStatus = Get-WindowsLightSensorStatus
    if ($lightStatus.HasSensor) {
        $name = if ($lightStatus.Selected -and -not [string]::IsNullOrWhiteSpace($lightStatus.Selected.Name)) { $lightStatus.Selected.Name } else { "Windows ambient light sensor" }
        Add-Check "Windows ambient sensor" "Pass" "$name is available. Candidate count: $($lightStatus.CandidateCount)."
    }
    else {
        Add-Check "Windows ambient sensor" "Info" "No Windows ambient-light sensor is exposed. Candidate count: $($lightStatus.CandidateCount)."
    }
}
catch {
    Add-Check "Windows ambient sensor" "Info" "Could not query Windows LightSensor API: $($_.Exception.Message)"
}

try {
    $mi08 = Get-PnpDevice -PresentOnly |
        Where-Object { $_.InstanceId -like "USB\VID_05AC&PID_1116&MI_08\*" } |
        Select-Object -First 1

    if ($mi08) {
        $driver = Get-CimInstance Win32_PnPSignedDriver |
            Where-Object { $_.DeviceID -eq $mi08.InstanceId } |
            Select-Object -First 1
        $deviceKey = Join-Path "HKLM:\SYSTEM\CurrentControlSet\Enum" $mi08.InstanceId
        $filters = Get-ItemProperty -Path $deviceKey -ErrorAction SilentlyContinue
        $hasFilter = [bool]($filters.UpperFilters -or $filters.LowerFilters)
        $status = if ($mi08.Status -eq "OK" -or $mi08.Service -eq "WinUSB" -or $hasFilter) { "Info" } else { "Warn" }
        $filterText = if ($hasFilter) { "filters are registered" } else { "no filters are registered" }
        Add-Check "Native ambient sensor MI_08" $status "$($mi08.Status), service=$($mi08.Service), driver=$($driver.InfName), $filterText."
    }
    else {
        Add-Check "Native ambient sensor MI_08" "Warn" "USB\VID_05AC&PID_1116&MI_08 was not found."
    }
}
catch {
    Add-Check "Native ambient sensor MI_08" "Warn" "Could not query MI_08: $($_.Exception.Message)"
}

try {
    $profilePath = Join-Path (Split-Path -Parent $PSScriptRoot) "profiles\StudioDisplayXDR-DisplayP3.icm"
    $installedPath = Join-Path $env:WINDIR "System32\spool\drivers\color\StudioDisplayXDR-DisplayP3.icm"
    if (Test-Path -LiteralPath $installedPath) {
        Add-Check "Color profile" "Pass" "Generated Display P3 profile is installed."
    }
    elseif (Test-Path -LiteralPath $profilePath) {
        Add-Check "Color profile" "Info" "Generated Display P3 profile is bundled but not installed."
    }
    else {
        Add-Check "Color profile" "Warn" "Bundled generated Display P3 profile was not found."
    }
}
catch {
    Add-Check "Color profile" "Info" "Could not check color profile: $($_.Exception.Message)"
}

$failCount = @($checks | Where-Object { $_.Status -eq "Fail" }).Count
$warnCount = @($checks | Where-Object { $_.Status -eq "Warn" }).Count
$passCount = @($checks | Where-Object { $_.Status -eq "Pass" }).Count
$infoCount = @($checks | Where-Object { $_.Status -eq "Info" }).Count

$result = if ($failCount -gt 0) {
    "action required"
}
elseif ($warnCount -gt 0) {
    "usable with warnings"
}
else {
    "ready"
}

$summary = [pscustomobject]@{
    Pass = $passCount
    Warn = $warnCount
    Fail = $failCount
    Info = $infoCount
    Result = $result
}

if ($Json) {
    [pscustomobject]@{
        Generated = $generated.ToString("o")
        Summary = $summary
        Checks = @($checks)
    } | ConvertTo-Json -Depth 6
    return
}

$checks | Format-Table Area,Status,Detail -AutoSize -Wrap

Write-Host ""
Write-Host "Summary: $passCount pass, $warnCount warning, $failCount fail, $infoCount info."

if ($failCount -gt 0) {
    Write-Host "Result: action required." -ForegroundColor Red
}
elseif ($warnCount -gt 0) {
    Write-Host "Result: usable with warnings." -ForegroundColor Yellow
}
else {
    Write-Host "Result: ready." -ForegroundColor Green
}

$warnings = @($checks | Where-Object { $_.Status -eq "Warn" -or $_.Status -eq "Fail" })
if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Next steps:"
    foreach ($warning in $warnings) {
        switch -Wildcard ($warning.Area) {
            "Refresh rate" {
                Write-Host "- Use the control panel 120 Hz button, Windows Advanced Display, or run Set-StudioXdrDisplayMode.ps1 after confirming the display is stable."
                break
            }
            "Native ambient sensor MI_08" {
                Write-Host "- Native automatic brightness still needs the guarded MI_08 WinUSB/libusb experiment. Camera fallback remains available when the Studio Display Camera works."
                break
            }
            "Brightness HID" {
                Write-Host "- Reconnect over Thunderbolt/USB4. Video-only adapters usually cannot expose Apple HID brightness control."
                break
            }
            "Native resolution" {
                Write-Host "- Reboot after installing the EDID override, then select 5120 x 2880 in Windows Display Settings."
                break
            }
            "5K120 mode test" {
                Write-Host "- Reboot after the EDID override and check GPU/Thunderbolt link state before applying 120 Hz."
                break
            }
            "Camera" {
                Write-Host "- Check USB4/Thunderbolt enumeration and Device Manager for the Studio Display Camera."
                break
            }
            "Audio" {
                Write-Host "- Check Windows Sound settings and Device Manager for Studio Display Audio endpoints."
                break
            }
        }
    }
}

if ($Detailed) {
    Write-Host ""
    Write-Host "== DisplayConfig detail =="
    if ([string]::IsNullOrWhiteSpace($colorStatusText)) {
        & (Join-Path $PSScriptRoot "Get-StudioXdrColorStatus.ps1")
    }
    else {
        Write-Host $colorStatusText.TrimEnd()
    }
}
