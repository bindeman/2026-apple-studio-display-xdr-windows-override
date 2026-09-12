param(
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-RegistryValue {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        $item.$Name
    }
    catch {
        $null
    }
}

function Get-RegistryProperties {
    param([string]$Path)

    try {
        $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
        $item.PSObject.Properties |
            Where-Object { $_.Name -notmatch "^PS" } |
            ForEach-Object {
                [pscustomobject]@{
                    Path = $Path
                    Name = $_.Name
                    Value = "$($_.Value)"
                }
            }
    }
    catch {
        @()
    }
}

function Convert-HagsValue {
    param($Value)

    switch ("$Value") {
        "1" { "Disabled" }
        "2" { "Enabled" }
        default {
            if ($null -eq $Value) { "Default / not set" } else { "Unknown ($Value)" }
        }
    }
}

function Get-StudioDisplayTarget {
    $script = Join-Path $PSScriptRoot "Get-StudioXdrColorStatus.ps1"
    if (-not (Test-Path -LiteralPath $script)) {
        return $null
    }

    $text = & $script *>&1 | Out-String
    $refresh = [regex]::Match($text, "TargetRefreshHz\s*:\s*([0-9.]+)")
    $width = [regex]::Match($text, "SourceWidth\s*:\s*([0-9]+)")
    $height = [regex]::Match($text, "SourceHeight\s*:\s*([0-9]+)")
    $advancedColorEnabled = [regex]::Match($text, "AdvancedColorEnabled\s*:\s*(True|False)")
    $bits = [regex]::Match($text, "BitsPerColorChannel\s*:\s*([0-9]+)")
    $pixelClock = [regex]::Match($text, "PixelClockMHz\s*:\s*([0-9.]+)")

    [pscustomobject]@{
        Raw = $text.Trim()
        SourceWidth = if ($width.Success) { [int]$width.Groups[1].Value } else { $null }
        SourceHeight = if ($height.Success) { [int]$height.Groups[1].Value } else { $null }
        RefreshHz = if ($refresh.Success) { [double]$refresh.Groups[1].Value } else { $null }
        AdvancedColorEnabled = if ($advancedColorEnabled.Success) { [bool]::Parse($advancedColorEnabled.Groups[1].Value) } else { $null }
        BitsPerColorChannel = if ($bits.Success) { [int]$bits.Groups[1].Value } else { $null }
        PixelClockMHz = if ($pixelClock.Success) { [double]$pixelClock.Groups[1].Value } else { $null }
    }
}

function Get-FrameCapRecommendation {
    param($RefreshHz)

    if ($null -eq $RefreshHz -or -not ($RefreshHz -is [double] -or $RefreshHz -is [int] -or $RefreshHz -is [decimal]) -or [double]$RefreshHz -le 0) {
        return "Unknown refresh. First confirm the active Studio Display XDR mode."
    }

    $refreshValue = [double]$RefreshHz
    $cap = [math]::Max(30, [math]::Floor($refreshValue - 2))
    if ($refreshValue -ge 119.9 -and $refreshValue -lt 120.2) {
        $cap = if ($refreshValue -gt 120.02) { 118 } else { 117 }
    }

    "$cap FPS initial cap for $([math]::Round($refreshValue, 3)) Hz while testing V-Sync/VRR."
}

function Get-ModeTest {
    $script = Join-Path $PSScriptRoot "Set-StudioXdrDisplayMode.ps1"
    if (-not (Test-Path -LiteralPath $script)) {
        return "Set-StudioXdrDisplayMode.ps1 not found."
    }

    (& $script -RefreshRate 120 -TestOnly 2>&1 | Out-String).Trim()
}

$target = Get-StudioDisplayTarget
$hagsValue = Get-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode"
$globalDirectX = Get-RegistryProperties -Path "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences" |
    Where-Object { $_.Name -eq "DirectXUserGlobalSettings" }
$gameConfig = Get-RegistryProperties -Path "HKCU:\System\GameConfigStore" |
    Where-Object { $_.Name -match "GameDVR|FSE|Fullscreen|Swap|VRR" }
$gameBar = Get-RegistryProperties -Path "HKCU:\Software\Microsoft\GameBar" |
    Where-Object { $_.Name -match "AutoGame|GameMode|GamePanel" }
$videoControllers = @(Get-CimInstance Win32_VideoController |
    Select-Object Name,AdapterCompatibility,VideoModeDescription,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate,CurrentBitsPerPixel,DriverVersion,DriverDate)
$modeTest = Get-ModeTest

$nvidiaSmi = $null
$nvidiaSmiCommand = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
if ($nvidiaSmiCommand) {
    try {
        $nvidiaSmi = (& $nvidiaSmiCommand.Source --query-gpu=name,driver_version,pci.bus_id,display_active --format=csv,noheader 2>&1 | Out-String).Trim()
    }
    catch {
        $nvidiaSmi = "nvidia-smi failed: $($_.Exception.Message)"
    }
}

$result = [pscustomobject]@{
    Generated = (Get-Date -Format o)
    StudioDisplay = $target
    FrameCapRecommendation = Get-FrameCapRecommendation -RefreshHz $target.RefreshHz
    FiveK120Test = $modeTest
    Hags = [pscustomobject]@{
        RegistryValue = $hagsValue
        State = Convert-HagsValue -Value $hagsValue
    }
    DirectXUserGlobalSettings = @($globalDirectX)
    GameConfigStore = @($gameConfig)
    GameBar = @($gameBar)
    VideoControllers = @($videoControllers)
    NvidiaSmi = $nvidiaSmi
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
    return
}

Write-Host "Studio Display XDR gaming / tearing diagnostic"
Write-Host "Generated: $($result.Generated)"
Write-Host ""

Write-Host "== Studio Display XDR signal =="
if ($target) {
    [pscustomobject]@{
        Resolution = if ($target.SourceWidth -and $target.SourceHeight) { "$($target.SourceWidth) x $($target.SourceHeight)" } else { "unknown" }
        RefreshHz = $target.RefreshHz
        HdrAdvancedColor = $target.AdvancedColorEnabled
        BitsPerColorChannel = $target.BitsPerColorChannel
        PixelClockMHz = $target.PixelClockMHz
        FrameCapRecommendation = $result.FrameCapRecommendation
    } | Format-List
}
else {
    Write-Host "No Studio Display XDR DisplayConfig target was parsed."
}

Write-Host ""
Write-Host "== 5K120 mode test =="
Write-Host $modeTest

Write-Host ""
Write-Host "== GPU / driver =="
$videoControllers | Format-List
if ($nvidiaSmi) {
    Write-Host "nvidia-smi:"
    Write-Host $nvidiaSmi
}

Write-Host ""
Write-Host "== Windows graphics toggles =="
[pscustomobject]@{
    HardwareAcceleratedGpuScheduling = $result.Hags.State
    HwSchMode = $hagsValue
} | Format-List

if ($globalDirectX.Count -gt 0) {
    Write-Host "DirectX user global settings:"
    $globalDirectX | Format-Table Name,Value -AutoSize -Wrap
}
else {
    Write-Host "DirectX user global settings: not found."
}

if ($gameConfig.Count -gt 0) {
    Write-Host ""
    Write-Host "GameConfigStore:"
    $gameConfig | Format-Table Name,Value -AutoSize -Wrap
}

if ($gameBar.Count -gt 0) {
    Write-Host ""
    Write-Host "GameBar:"
    $gameBar | Format-Table Name,Value -AutoSize -Wrap
}

Write-Host ""
Write-Host "== Recommended first test matrix =="
Write-Host "- Fixed refresh: use 120 Hz or 120.04 Hz; avoid Dynamic Refresh Rate while diagnosing."
Write-Host "- Frame cap: $($result.FrameCapRecommendation)"
Write-Host "- V-Sync: try NVIDIA Control Panel V-Sync On plus the frame cap; avoid double limiting in game and driver."
Write-Host "- HDR: test once with HDR off, then once with HDR on, using the same refresh and cap."
Write-Host "- If tearing is only on one side/tile, switch to 60 Hz and back to 120 Hz to force link retraining."
