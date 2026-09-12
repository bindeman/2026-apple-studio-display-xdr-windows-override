$ErrorActionPreference = "Stop"

function Invoke-WinRtAsyncOperation {
    param(
        [Parameter(Mandatory = $true)]
        $Operation,
        [Parameter(Mandatory = $true)]
        [type]$ResultType
    )

    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object { $_.ToString() -eq "System.Threading.Tasks.Task``1[TResult] AsTask[TResult](Windows.Foundation.IAsyncOperation``1[TResult])" } |
        Select-Object -First 1

    if (-not $method) {
        throw "Could not find WindowsRuntimeSystemExtensions.AsTask<TResult>(IAsyncOperation<TResult>)."
    }

    $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    $task.Wait()
    $task.Result
}

function Get-WindowsLightSensorScore {
    param(
        [string]$Name,
        [string]$Id
    )

    $text = "$Name $Id".ToLowerInvariant()
    $score = 0

    if ($text.Contains("apple")) { $score += 80 }
    if ($text.Contains("studio")) { $score += 70 }
    if ($text.Contains("xdr")) { $score += 70 }
    if ($text.Contains("pro display")) { $score += 70 }
    if ($text.Contains("display")) { $score += 30 }
    if ($text.Contains("ambient")) { $score += 15 }
    if ($text.Contains("light")) { $score += 10 }
    if ($text.Contains("05ac")) { $score += 40 }

    $score
}

function Get-WindowsLightSensorStatus {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction SilentlyContinue
    [Windows.Devices.Sensors.LightSensor,Windows.Devices.Sensors,ContentType=WindowsRuntime] > $null
    [Windows.Devices.Enumeration.DeviceInformation,Windows.Devices.Enumeration,ContentType=WindowsRuntime] > $null
    [Windows.Devices.Enumeration.DeviceInformationCollection,Windows.Devices.Enumeration,ContentType=WindowsRuntime] > $null

    $candidates = [System.Collections.Generic.List[object]]::new()
    $sensor = $null
    $selected = $null
    $selector = $null
    $enumerationError = $null

    try {
        $selector = [Windows.Devices.Sensors.LightSensor]::GetDeviceSelector()
        $operation = [Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($selector)
        $devices = @(Invoke-WinRtAsyncOperation -Operation $operation -ResultType ([Windows.Devices.Enumeration.DeviceInformationCollection]))

        foreach ($device in $devices) {
            $score = Get-WindowsLightSensorScore -Name $device.Name -Id $device.Id
            $candidates.Add([pscustomobject]@{
                Name = $device.Name
                Id = $device.Id
                Kind = "$($device.Kind)"
                IsEnabled = $device.IsEnabled
                Score = $score
                Opened = $false
                Error = $null
            })
        }

        foreach ($candidate in ($candidates | Sort-Object Score -Descending)) {
            try {
                $operation = [Windows.Devices.Sensors.LightSensor]::FromIdAsync($candidate.Id)
                $opened = Invoke-WinRtAsyncOperation -Operation $operation -ResultType ([Windows.Devices.Sensors.LightSensor])
                if ($opened) {
                    $sensor = $opened
                    $selected = $candidate
                    $candidate.Opened = $true
                    break
                }
            }
            catch {
                $candidate.Error = $_.Exception.Message
            }
        }
    }
    catch {
        $enumerationError = $_.Exception.Message
    }

    if (-not $sensor) {
        try {
            $sensor = [Windows.Devices.Sensors.LightSensor]::GetDefault()
            if ($sensor) {
                $selected = [pscustomobject]@{
                    Name = "Windows default ambient light sensor"
                    Id = $sensor.DeviceId
                    Kind = "Default"
                    IsEnabled = $true
                    Score = 0
                    Opened = $true
                    Error = $null
                }
            }
        }
        catch {
            if (-not $enumerationError) {
                $enumerationError = $_.Exception.Message
            }
        }
    }

    $reading = $null
    if ($sensor) {
        try {
            $current = $sensor.GetCurrentReading()
            if ($current) {
                $reading = [pscustomobject]@{
                    IlluminanceInLux = $current.IlluminanceInLux
                    Timestamp = $current.Timestamp
                }
            }
        }
        catch {
            $reading = [pscustomobject]@{
                IlluminanceInLux = $null
                Timestamp = $null
                Error = $_.Exception.Message
            }
        }
    }

    [pscustomobject]@{
        HasSensor = $null -ne $sensor
        Selector = $selector
        CandidateCount = $candidates.Count
        Candidates = @($candidates)
        Selected = $selected
        DeviceId = if ($sensor) { $sensor.DeviceId } else { $null }
        MinimumReportInterval = if ($sensor) { $sensor.MinimumReportInterval } else { $null }
        ReportInterval = if ($sensor) { $sensor.ReportInterval } else { $null }
        CurrentReading = $reading
        Error = $enumerationError
    }
}
