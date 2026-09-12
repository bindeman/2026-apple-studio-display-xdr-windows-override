param(
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-DeviceHardwareIds {
    param([string]$InstanceId)

    @(
        Get-PnpDeviceProperty -InstanceId $InstanceId -ErrorAction SilentlyContinue |
            Where-Object { $_.KeyName -eq "DEVPKEY_Device_HardwareIds" } |
            Select-Object -ExpandProperty Data
    )
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$infPath = Join-Path $repoRoot "drivers\StudioXdrAmbientWinUsb.inf"
$interfaceGuid = "6F94F6F0-7B76-4DFB-AD85-905E20C82D9D"
$genericHardwareId = "USB\VID_05AC&PID_1116&MI_08"

$device = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -like "USB\VID_05AC&PID_1116&MI_08\*" } |
    Select-Object -First 1

$hardwareIds = @()
$targetHardwareId = $genericHardwareId
$driver = $null
$problem = $null
$storeMatches = @()
$pnpUtilDriverOutput = @()
$pnpUtilMatchingDriverNames = @()
$pnpUtilBestRankedDriverNames = @()
$pnpUtilExitCode = $null

if ($device) {
    $hardwareIds = @(Get-DeviceHardwareIds -InstanceId $device.InstanceId)
    $targetHardwareId = $hardwareIds |
        Where-Object { $_ -like "USB\VID_05AC&PID_1116&REV_*&MI_08" } |
        Select-Object -First 1
    if (-not $targetHardwareId) {
        $targetHardwareId = $genericHardwareId
    }

    $driver = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceID -eq $device.InstanceId } |
        Select-Object -First 1

    $problem = Get-PnpDeviceProperty -InstanceId $device.InstanceId -ErrorAction SilentlyContinue |
        Where-Object { $_.KeyName -eq "DEVPKEY_Device_DriverProblemDesc" } |
        Select-Object -ExpandProperty Data -First 1

    $currentPnpDriverName = $null
    $pnpUtilDriverOutput = @(& pnputil /enum-devices /instanceid $device.InstanceId /drivers 2>&1 | ForEach-Object { "$_" })
    $pnpUtilExitCode = $LASTEXITCODE
    foreach ($line in $pnpUtilDriverOutput) {
        if ($line -match "^\s*Driver Name:\s*(.+?)\s*$") {
            $currentPnpDriverName = $Matches[1].Trim()
            $pnpUtilMatchingDriverNames += $currentPnpDriverName
            continue
        }

        if ($line -match "^\s*Driver Status:\s*(.+?)\s*$" -and $currentPnpDriverName) {
            $driverStatus = $Matches[1].Trim()
            if ($driverStatus -match "Best Ranked|Installed") {
                $pnpUtilBestRankedDriverNames += $currentPnpDriverName
            }
        }
    }
}

$infExists = Test-Path -LiteralPath $infPath
$infText = if ($infExists) { Get-Content -Raw -LiteralPath $infPath } else { "" }
$infHasTarget = $infText.Contains($targetHardwareId)
$infHasGeneric = $infText.Contains($genericHardwareId)
$infHasGuid = $infText.Contains($interfaceGuid)
$infUsesInboxWinUsbInstall = $infText.Contains("Needs   = WINUSB.NT")
$infUsesInboxWinUsbServices = $infText.Contains("Needs   = WINUSB.NT.Services")
$infHasCustomWinUsbServiceInstall = $infText.Contains("WinUSB_ServiceInstall") -or $infText.Contains("AddService = WinUSB")
$catalogFileName = ""
if ($infText -match "(?im)^\s*CatalogFile\s*=\s*(.+?)\s*$") {
    $catalogFileName = $Matches[1].Trim()
}
$infHasCatalogFile = -not [string]::IsNullOrWhiteSpace($catalogFileName)
$catalogFilePath = if ($infHasCatalogFile) { Join-Path (Split-Path -Parent $infPath) $catalogFileName } else { $null }
$catalogFileExists = $catalogFilePath -and (Test-Path -LiteralPath $catalogFilePath)

if ($device) {
    $storePattern = [regex]::Escape($targetHardwareId)
    $guidPattern = [regex]::Escape($interfaceGuid)
    $storeMatches = @(
        Select-String -Path "C:\Windows\INF\oem*.inf" -Pattern "$storePattern|$guidPattern" -List -ErrorAction SilentlyContinue |
            Select-Object Path,LineNumber,Line
    )
}

$connectorActive = $device -and $device.Service -eq "WinUSB"
$packageMatches = $infExists -and $infHasTarget -and $infHasGeneric -and $infHasGuid
$infUsesDocumentedPattern = $infUsesInboxWinUsbInstall -and $infUsesInboxWinUsbServices -and -not $infHasCustomWinUsbServiceInstall
$driverStoreHasTarget = $storeMatches.Count -gt 0
$pnpUtilMatchingDriverNames = @($pnpUtilMatchingDriverNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$pnpUtilBestRankedDriverNames = @($pnpUtilBestRankedDriverNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

$status = if (-not $device) {
    "MissingDevice"
}
elseif (-not $packageMatches -or -not $infUsesDocumentedPattern) {
    "PackageMismatch"
}
elseif ($connectorActive) {
    "ConnectorActive"
}
elseif ($driverStoreHasTarget) {
    "PackageInstalledNotBound"
}
else {
    "ReadyToInstall"
}

$summary = switch ($status) {
    "MissingDevice" { "Studio Display XDR MI_08 is not present." }
    "PackageMismatch" { "Packaged WinUSB INF does not match the connected MI_08 target or documented WinUSB include pattern." }
    "ConnectorActive" { "MI_08 is bound to WinUSB; native packet probes can run." }
    "PackageInstalledNotBound" { "A matching driver package is in the driver store, but MI_08 is still not bound to WinUSB." }
    default { "Packaged WinUSB INF matches the connected MI_08 target, but it is not installed or bound." }
}

$result = [pscustomobject]@{
    Status = $status
    Summary = $summary
    InstanceId = if ($device) { $device.InstanceId } else { $null }
    DeviceStatus = if ($device) { $device.Status } else { $null }
    Service = if ($device) { $device.Service } else { $null }
    Problem = $problem
    TargetHardwareId = $targetHardwareId
    HardwareIds = @($hardwareIds)
    InfPath = $infPath
    InfExists = $infExists
    InfHasTargetHardwareId = $infHasTarget
    InfHasGenericHardwareId = $infHasGeneric
    InfHasDeviceInterfaceGuid = $infHasGuid
    InfUsesInboxWinUsbInstall = $infUsesInboxWinUsbInstall
    InfUsesInboxWinUsbServices = $infUsesInboxWinUsbServices
    InfHasCustomWinUsbServiceInstall = $infHasCustomWinUsbServiceInstall
    InfUsesDocumentedWinUsbPattern = $infUsesDocumentedPattern
    InfHasCatalogFile = [bool]$infHasCatalogFile
    CatalogFileName = $catalogFileName
    CatalogFilePath = $catalogFilePath
    CatalogFileExists = [bool]$catalogFileExists
    PackageMatchesTarget = $packageMatches
    ConnectorActive = [bool]$connectorActive
    DriverStoreHasTarget = [bool]$driverStoreHasTarget
    DriverProvider = if ($driver) { $driver.DriverProviderName } else { $null }
    DriverInf = if ($driver) { $driver.InfName } else { $null }
    DriverVersion = if ($driver) { $driver.DriverVersion } else { $null }
    DriverStoreMatches = @($storeMatches)
    PnpUtilExitCode = $pnpUtilExitCode
    PnpUtilMatchingDriverNames = @($pnpUtilMatchingDriverNames)
    PnpUtilBestRankedDriverNames = @($pnpUtilBestRankedDriverNames)
    PnpUtilDriverOutput = @($pnpUtilDriverOutput)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 6
    return
}

Write-Host "Studio Display XDR ambient driver target check"
Write-Host ""
$result |
    Select-Object Status,Summary,InstanceId,DeviceStatus,Service,TargetHardwareId,InfExists,InfHasTargetHardwareId,InfHasGenericHardwareId,InfHasDeviceInterfaceGuid,InfUsesInboxWinUsbInstall,InfUsesInboxWinUsbServices,InfHasCustomWinUsbServiceInstall,InfUsesDocumentedWinUsbPattern,InfHasCatalogFile,CatalogFileName,CatalogFileExists,PackageMatchesTarget,ConnectorActive,DriverStoreHasTarget,DriverProvider,DriverInf,DriverVersion |
    Format-List

if ($problem) {
    Write-Host "Driver problem:"
    Write-Host $problem
    Write-Host ""
}

if ($storeMatches.Count -gt 0) {
    Write-Host "Matching driver-store entries:"
    $storeMatches | Format-Table Path,LineNumber,Line -AutoSize -Wrap
}
else {
    Write-Host "No matching driver-store entry for the exact target or package GUID was found."
    if (-not $catalogFileExists) {
        Write-Host "The packaged INF declares a catalog, but no signed catalog is present next to the INF yet. Run Prepare-Ambient-Driver.cmd with WDK signing tools, or use a libwdi/Zadig-generated package for this exact interface."
    }
}

if ($pnpUtilDriverOutput.Count -gt 0) {
    Write-Host ""
    Write-Host "PnPUtil matching-driver view:"
    if ($pnpUtilMatchingDriverNames.Count -gt 0) {
        Write-Host "Matching driver names: $($pnpUtilMatchingDriverNames -join ', ')"
    }
    if ($pnpUtilBestRankedDriverNames.Count -gt 0) {
        Write-Host "Best-ranked / installed: $($pnpUtilBestRankedDriverNames -join ', ')"
    }
    $pnpUtilDriverOutput | ForEach-Object { Write-Host $_ }
}
