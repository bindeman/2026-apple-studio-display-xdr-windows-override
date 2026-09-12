param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script as administrator."
    }
}

function Invoke-PnpUtil {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    $output = & pnputil @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "pnputil failed with exit code $exitCode."
    }

    return $exitCode
}

Assert-Admin

$root = Split-Path -Parent $PSScriptRoot
$inf = Join-Path $root "drivers\StudioXdrAmbientWinUsb.inf"
$catalog = Join-Path $root "drivers\StudioXdrAmbientWinUsb.cat"
$targetCheck = Join-Path $PSScriptRoot "Test-StudioXdrAmbientDriverTarget.ps1"

if (-not (Test-Path $inf)) {
    throw "Missing driver INF: $inf"
}

$device = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like "USB\VID_05AC&PID_1116&MI_08\*" } | Select-Object -First 1
if (-not $device) {
    throw "Studio Display XDR ambient interface USB\VID_05AC&PID_1116&MI_08 is not present."
}

$instanceId = $device.InstanceId
Write-Host "Target device: $instanceId"
Write-Host "Current state: $($device.Status) / $($device.Class) / $($device.FriendlyName)"

$hardwareIds = @(
    Get-PnpDeviceProperty -InstanceId $instanceId -ErrorAction SilentlyContinue |
        Where-Object { $_.KeyName -eq "DEVPKEY_Device_HardwareIds" } |
        Select-Object -ExpandProperty Data
)
$targetHardwareId = $hardwareIds | Where-Object { $_ -like "USB\VID_05AC&PID_1116&REV_*&MI_08" } | Select-Object -First 1
if (-not $targetHardwareId) {
    $targetHardwareId = "USB\VID_05AC&PID_1116&MI_08"
}

Write-Host "Target hardware ID: $targetHardwareId"
$infText = Get-Content -Raw -LiteralPath $inf
if ($infText -notmatch [regex]::Escape($targetHardwareId)) {
    throw "Driver INF does not contain the connected target hardware ID: $targetHardwareId"
}

if (Test-Path -LiteralPath $targetCheck) {
    Write-Host ""
    Write-Host "Preflight target check:"
    & $targetCheck
    Write-Host ""
}

if ($infText -notmatch "(?im)^\s*CatalogFile\s*=") {
    Write-Warning "The packaged INF has no signed catalog. Normal Windows installs may reject it; a signed/test-signed catalog or a libwdi/Zadig-generated package may be required for this exact interface."
}
elseif (-not (Test-Path -LiteralPath $catalog)) {
    Write-Warning "The INF declares StudioXdrAmbientWinUsb.cat, but that catalog is not present yet. Run Prepare-Ambient-Driver.cmd first on a machine with WDK signing tools, or use a libwdi/Zadig-generated WinUSB package for this exact interface."
}

Write-Host "Adding experimental WinUSB driver package..."
$addExitCode = Invoke-PnpUtil -Arguments @("/add-driver", $inf) -AllowFailure
if ($addExitCode -ne 0) {
    Write-Warning "pnputil could not add the driver package. If this was not an elevation problem, Windows probably rejected the unsigned experimental package."
}

Write-Host "Binding WinUSB driver to Studio Display XDR ambient interface..."
$installExitCode = Invoke-PnpUtil -Arguments @("/add-driver", $inf, "/install") -AllowFailure
if ($installExitCode -ne 0) {
    Write-Warning "pnputil could not install/bind the driver package. The target will likely remain on Microsoft's HID driver."
}

$driverStoreMatch = Select-String -Path "C:\Windows\INF\oem*.inf" -Pattern ([regex]::Escape($targetHardwareId)) -List -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($driverStoreMatch) {
    Write-Host "Driver-store package with exact target: $($driverStoreMatch.Path)"
}
else {
    Write-Warning "No driver-store package containing '$targetHardwareId' was found. Windows may have rejected the unsigned experimental INF."
}

$infName = Get-CimInstance Win32_PnPSignedDriver |
    Where-Object { $_.DeviceID -eq $instanceId -or $_.DeviceID -like "USB\VID_05AC&PID_1116&MI_08\*" } |
    Select-Object -First 1 -ExpandProperty InfName

if ($infName -and $infName -ne "StudioXdrAmbientWinUsb.inf") {
    Invoke-PnpUtil -Arguments @("/enum-devices", "/instanceid", $instanceId) -AllowFailure | Out-Null
}

Write-Host "Restarting target interface..."
try {
    Disable-PnpDevice -InstanceId $instanceId -Confirm:$false -ErrorAction Stop
    Start-Sleep -Milliseconds 600
    Enable-PnpDevice -InstanceId $instanceId -Confirm:$false -ErrorAction Stop
}
catch {
    if (-not $Force) {
        throw
    }
    Write-Warning $_
}

Start-Sleep -Seconds 1
$after = Get-PnpDevice -InstanceId $instanceId
$driver = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceID -eq $instanceId } | Select-Object -First 1

$isActive = $after.Service -eq "WinUSB"
if (-not $isActive) {
    Write-Warning "The Studio Display XDR ambient interface is still bound to '$($after.Service)' using '$($driver.InfName)'."
    Write-Warning "Windows did not activate the experimental connector. For the next native-sensor test, bind only '$targetHardwareId' / HID Relay / Interface 8 to WinUSB with Zadig/libwdi or a signed driver package, then run Get-StudioXdrAmbientStatus.ps1 again."
}

if (Test-Path -LiteralPath $targetCheck) {
    Write-Host ""
    Write-Host "Post-install target check:"
    & $targetCheck
    Write-Host ""
}

[pscustomobject]@{
    InstanceId = $after.InstanceId
    TargetHardwareId = $targetHardwareId
    Status = $after.Status
    Class = $after.Class
    FriendlyName = $after.FriendlyName
    ConnectorActive = $isActive
    AddDriverExitCode = $addExitCode
    InstallDriverExitCode = $installExitCode
    DriverProvider = $driver.DriverProviderName
    DriverInf = $driver.InfName
    DriverVersion = $driver.DriverVersion
}
