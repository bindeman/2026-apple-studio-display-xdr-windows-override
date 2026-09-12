param(
    [string]$ZipPath = "",
    # "Full" = control panel + setup launcher + scripts. "Scripts" = PowerShell-only package (no GUI).
    # Empty = infer from the ZIP file name ("-scripts.zip" => Scripts).
    [ValidateSet("", "Full", "Scripts")]
    [string]$Flavor = "",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    Split-Path -Parent $PSScriptRoot
}

function Normalize-ZipPath([string]$path) {
    ($path -replace "\\", "/").TrimStart("/")
}

function Test-ZipEntry {
    param(
        [hashtable]$Entries,
        [string]$Path,
        [long]$MinBytes = 1
    )

    $normalized = Normalize-ZipPath $Path
    $entry = $Entries[$normalized]
    $ok = $null -ne $entry -and $entry.Length -ge $MinBytes

    [pscustomobject]@{
        Path = $normalized
        Present = $null -ne $entry
        Size = if ($entry) { $entry.Length } else { 0 }
        RequiredSize = $MinBytes
        OK = $ok
    }
}

function Read-ZipEntryBytes {
    param(
        [hashtable]$Entries,
        [string]$Path
    )

    $normalized = Normalize-ZipPath $Path
    $entry = $Entries[$normalized]
    if (-not $entry) {
        return $null
    }

    $stream = $entry.Open()
    try {
        $memory = [System.IO.MemoryStream]::new()
        try {
            $stream.CopyTo($memory)
            $memory.ToArray()
        }
        finally {
            $memory.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function Read-ZipEntryText {
    param(
        [hashtable]$Entries,
        [string]$Path
    )

    $bytes = Read-ZipEntryBytes -Entries $Entries -Path $Path
    if (-not $bytes) {
        return $null
    }

    [System.Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
}

$repoRoot = Get-RepoRoot
if ([string]::IsNullOrWhiteSpace($ZipPath)) {
    $ZipPath = Join-Path $repoRoot "dist\studio-display-xdr-windows.zip"
}

if (-not (Test-Path -LiteralPath $ZipPath)) {
    throw "Package ZIP not found: $ZipPath"
}

if ([string]::IsNullOrWhiteSpace($Flavor)) {
    $Flavor = if ([System.IO.Path]::GetFileName($ZipPath) -match "-scripts\.zip$") { "Scripts" } else { "Full" }
}
$isFull = $Flavor -eq "Full"

Add-Type -AssemblyName System.IO.Compression.FileSystem

$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ZipPath).Path)
try {
    $entries = @{}
    foreach ($entry in $zip.Entries) {
        $entries[(Normalize-ZipPath $entry.FullName)] = $entry
    }

    $requiredFiles = @(
        "README.md",
        "LICENSE",
        "THIRD_PARTY_NOTICES.md",
        "PACKAGE.json",
        "CONTINUE.md",
        "RELEASE_NOTES.md",
        "Install-StudioDisplayXdrSupport.cmd",
        "Uninstall-StudioDisplayXdrSupport.cmd",
        "Prepare-Ambient-Driver.cmd",
        "Install-Color-Profile.cmd",
        "Install-Ambient-Connector.cmd",
        "Install-LibUsb-Ambient-Filter.cmd",
        "Studio-Display-XDR.cmd",
        "Support-Report.cmd",
        "Uninstall-LibUsb-Ambient-Filter.cmd",
        "Check-Status.cmd",
        "Check-Ambient.cmd",
        "Check-Gaming.cmd",
        "Check-Color.cmd",
        "Enable-HDR.cmd",
        "Disable-HDR.cmd",
        "Brightness-Up.cmd",
        "Brightness-Down.cmd",
        "Brightness-Status.cmd",
        "Uninstall-Override.cmd",
        "edid/studio-display-xdr-ae42.bin",
        "profiles/StudioDisplayXDR-DisplayP3.icm",
        "drivers/StudioXdrAmbientWinUsb.inf",
        "docs/auto-brightness.md",
        "docs/brightness.md",
        "docs/color-management.md",
        "docs/gaming-tearing.md",
        "docs/hid-research.md",
        "docs/parity-audit.md",
        "docs/recovery.md",
        "docs/release-checklist.md",
        "docs/roadmap.md",
        "docs/support-matrix.md",
        "docs/screenshots.md",
        "docs/screenshots/control-panel.png",
        "docs/screenshots/control-panel-about.png",
        "docs/screenshots/setup-launcher.png",
        "scripts/AppleDisplayBrightnessCore.ps1",
        "scripts/Build-StudioDisplayXdrPackage.ps1",
        "scripts/Capture-StudioXdrSetupScreenshot.ps1",
        "scripts/New-StudioXdrIcon.ps1",
        "scripts/Test-StudioDisplayXdrAppRuntime.ps1",
        "scripts/Test-StudioDisplayXdrAppUi.ps1",
        "scripts/Test-StudioDisplayXdrExtractedPackage.ps1",
        "scripts/Test-StudioDisplayXdrPackage.ps1",
        "scripts/Test-StudioDisplayXdrRelease.ps1",
        "scripts/Get-StudioXdrStatus.ps1",
        "scripts/Test-StudioXdrReadiness.ps1",
        "scripts/Test-StudioXdrAmbientPreflight.ps1",
        "scripts/Test-StudioXdrAmbientDriverTarget.ps1",
        "scripts/New-StudioXdrAmbientDriverPackage.ps1",
        "scripts/Get-StudioXdrAmbientStatus.ps1",
        "scripts/Get-StudioXdrGamingStatus.ps1",
        "scripts/Get-AppleDisplayUsbTopology.ps1",
        "scripts/Get-AppleDisplaySensorCorrelation.ps1",
        "scripts/Get-StudioXdrColorStatus.ps1",
        "scripts/Find-StudioXdrColorProfiles.ps1",
        "scripts/Get-StudioXdrSupportReport.ps1",
        "scripts/Dump-StudioXdrHidCollections.ps1",
        "scripts/WindowsLightSensorTools.ps1",
        "scripts/Install-StudioDisplayXdrSupport.ps1",
        "scripts/Install-StudioXdrLibUsbFilter.ps1",
        "scripts/Uninstall-StudioDisplayXdrSupport.ps1",
        "scripts/Uninstall-StudioXdrLibUsbFilter.ps1",
        "scripts/Install-StudioXdrEdidOverride.ps1",
        "scripts/Uninstall-StudioXdrEdidOverride.ps1",
        "scripts/Install-StudioXdrColorProfile.ps1",
        "scripts/Set-StudioXdrDisplayMode.ps1",
        "scripts/StudioXdrBrightness.ps1",
        "scripts/Test-StudioXdrLibUsbAmbient.ps1"
    )

    # GUI/runtime artifacts ship only in the full package.
    $guiFiles = @(
        "StudioDisplayXdrSetup.exe",
        "assets/StudioDisplayXdr.ico",
        "tools/LibUsbDotNet.LibUsbDotNet.net45.dll",
        "StudioDisplayXdr.App/StudioDisplayXdr.exe",
        "StudioDisplayXdr.App/StudioDisplayXdr.dll",
        "StudioDisplayXdr.App/PresentationFramework.dll",
        "StudioDisplayXdr.App/WindowsBase.dll",
        "StudioDisplayXdr.App/LibUsbDotNet.LibUsbDotNet.dll",
        "StudioDisplayXdr.App/wpfgfx_cor3.dll",
        "StudioDisplayXdr.App/Microsoft.Windows.SDK.NET.dll",
        "StudioDisplayXdr.App/WinRT.Runtime.dll"
    )
    if ($isFull) {
        $requiredFiles += $guiFiles
    }

    $results = @()
    foreach ($file in $requiredFiles) {
        $minBytes = switch -Wildcard ($file) {
            "*.cmd" { 20; break }
            "*.ps1" { 80; break }
            "*.md" { 20; break }
            "*.png" { 1024; break }
            "*.exe" { 1024; break }
            "*.dll" { 1024; break }
            "*.icm" { 128; break }
            "*.bin" { 128; break }
            default { 1 }
        }
        $results += Test-ZipEntry -Entries $entries -Path $file -MinBytes $minBytes
    }

    $edid = Read-ZipEntryBytes -Entries $entries -Path "edid/studio-display-xdr-ae42.bin"
    $edidLooksValid = $edid -and $edid.Length -ge 128 -and
        $edid[0] -eq 0x00 -and $edid[1] -eq 0xFF -and $edid[2] -eq 0xFF -and $edid[3] -eq 0xFF

    $profile = Read-ZipEntryBytes -Entries $entries -Path "profiles/StudioDisplayXDR-DisplayP3.icm"
    $profileLooksValid = $profile -and $profile.Length -ge 128 -and
        [System.Text.Encoding]::ASCII.GetString($profile, 36, 4) -eq "acsp"

    $ambientInfText = Read-ZipEntryText -Entries $entries -Path "drivers/StudioXdrAmbientWinUsb.inf"
    $ambientCatBytes = Read-ZipEntryBytes -Entries $entries -Path "drivers/StudioXdrAmbientWinUsb.cat"
    $ambientInfTargetsExactMi08 =
        $ambientInfText -and
        $ambientInfText.Contains("USB\VID_05AC&PID_1116&REV_1801&MI_08") -and
        $ambientInfText.Contains("USB\VID_05AC&PID_1116&MI_08") -and
        $ambientInfText.Contains("6F94F6F0-7B76-4DFB-AD85-905E20C82D9D") -and
        $ambientInfText.Contains("CatalogFile = StudioXdrAmbientWinUsb.cat")
    $ambientSignedCatalogNotBundled = -not $ambientCatBytes
    $ambientInfUsesDocumentedWinUsbPattern =
        $ambientInfText -and
        $ambientInfText.Contains("Needs   = WINUSB.NT") -and
        $ambientInfText.Contains("Needs   = WINUSB.NT.Services") -and
        -not $ambientInfText.Contains("WinUSB_ServiceInstall") -and
        -not $ambientInfText.Contains("AddService = WinUSB")

    $ambientTargetCheckText = Read-ZipEntryText -Entries $entries -Path "scripts/Test-StudioXdrAmbientDriverTarget.ps1"
    $ambientTargetIncludesPnpDriverView =
        $ambientTargetCheckText -and
        $ambientTargetCheckText.Contains("pnputil /enum-devices") -and
        $ambientTargetCheckText.Contains("PnpUtilMatchingDriverNames") -and
        $ambientTargetCheckText.Contains("PnPUtil matching-driver view")
    $ambientInstallScriptText = Read-ZipEntryText -Entries $entries -Path "scripts/Install-StudioXdrAmbientConnector.ps1"
    $ambientInstallShowsTargetChecks =
        $ambientInstallScriptText -and
        $ambientInstallScriptText.Contains("Preflight target check") -and
        $ambientInstallScriptText.Contains("Post-install target check") -and
        $ambientInstallScriptText.Contains("signed catalog") -and
        $ambientInstallScriptText.Contains("AddDriverExitCode") -and
        $ambientInstallScriptText.Contains("InstallDriverExitCode")
    $ambientPackageScriptText = Read-ZipEntryText -Entries $entries -Path "scripts/New-StudioXdrAmbientDriverPackage.ps1"
    $ambientPackageScriptSupported =
        $ambientPackageScriptText -and
        $ambientPackageScriptText.Contains("inf2cat.exe") -and
        $ambientPackageScriptText.Contains("signtool.exe") -and
        $ambientPackageScriptText.Contains("New-SelfSignedCertificate") -and
        $ambientPackageScriptText.Contains("StudioXdrAmbientWinUsb.cat") -and
        $ambientPackageScriptText.Contains("CheckOnly")

    $setup = Read-ZipEntryBytes -Entries $entries -Path "StudioDisplayXdrSetup.exe"
    $setupLooksValid = $setup -and $setup.Length -ge 4096 -and
        $setup[0] -eq [byte][char]"M" -and $setup[1] -eq [byte][char]"Z"

    $icon = Read-ZipEntryBytes -Entries $entries -Path "assets/StudioDisplayXdr.ico"
    $iconLooksValid = $icon -and $icon.Length -ge 512 -and
        $icon[0] -eq 0x00 -and $icon[1] -eq 0x00 -and
        $icon[2] -eq 0x01 -and $icon[3] -eq 0x00

    $packageJsonText = Read-ZipEntryText -Entries $entries -Path "PACKAGE.json"
    $packageJsonLooksValid = $false
    if (-not [string]::IsNullOrWhiteSpace($packageJsonText)) {
        try {
            $packageJson = $packageJsonText | ConvertFrom-Json
            $expectedFlavor = if ($isFull) { "full" } else { "scripts" }
            $packageJsonLooksValid =
                $packageJson.name -eq "studio-display-xdr-windows" -and
                $packageJson.flavor -eq $expectedFlavor -and
                -not [string]::IsNullOrWhiteSpace($packageJson.version) -and
                -not [string]::IsNullOrWhiteSpace($packageJson.builtAt)
            if ($isFull) {
                $packageJsonLooksValid = $packageJsonLooksValid -and
                    $packageJson.setupPath -eq "StudioDisplayXdrSetup.exe" -and
                    $packageJson.appPath -eq "StudioDisplayXdr.App/StudioDisplayXdr.exe"
            }
            else {
                $packageJsonLooksValid = $packageJsonLooksValid -and
                    [string]::IsNullOrWhiteSpace($packageJson.setupPath) -and
                    [string]::IsNullOrWhiteSpace($packageJson.appPath)
            }
        }
        catch {
            $packageJsonLooksValid = $false
        }
    }

    $forbiddenPrefixes = @(
        "tools/SDBC/",
        "tools/asdcontrol/",
        "tools/studi/",
        "tools/BetterDisplay/",
        "downloads/",
        "backups/",
        ".git/"
    )
    if (-not $isFull) {
        # The scripts-only package must not carry any GUI or runtime payload.
        $forbiddenPrefixes += @(
            "StudioDisplayXdr.App/",
            "StudioDisplayXdrSetup.exe",
            "tools/",
            "assets/"
        )
    }

    $forbiddenEntries = @(
        foreach ($entryPath in $entries.Keys) {
            foreach ($prefix in $forbiddenPrefixes) {
                if ($entryPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
                    $entryPath
                    break
                }
            }
        }
    )
    $noForbiddenEntries = $forbiddenEntries.Count -eq 0

    $unexpectedToolEntries = @(
        $entries.Keys |
            Where-Object { $_.StartsWith("tools/", [StringComparison]::OrdinalIgnoreCase) -and $_ -ne "tools/LibUsbDotNet.LibUsbDotNet.net45.dll" }
    )
    $toolsFolderLooksClean = $unexpectedToolEntries.Count -eq 0

    $contentChecks = @(
        [pscustomobject]@{ Check = "EDID header"; OK = [bool]$edidLooksValid },
        [pscustomobject]@{ Check = "ICC acsp signature"; OK = [bool]$profileLooksValid },
        [pscustomobject]@{ Check = "Ambient WinUSB INF exact MI_08 target"; OK = [bool]$ambientInfTargetsExactMi08 },
        [pscustomobject]@{ Check = "Ambient test-signed catalog not bundled"; OK = [bool]$ambientSignedCatalogNotBundled },
        [pscustomobject]@{ Check = "Ambient WinUSB INF documented include pattern"; OK = [bool]$ambientInfUsesDocumentedWinUsbPattern },
        [pscustomobject]@{ Check = "Ambient target PnP driver-ranking view"; OK = [bool]$ambientTargetIncludesPnpDriverView },
        [pscustomobject]@{ Check = "Ambient installer reports before/after target state"; OK = [bool]$ambientInstallShowsTargetChecks },
        [pscustomobject]@{ Check = "Ambient driver package signing helper"; OK = [bool]$ambientPackageScriptSupported },
        [pscustomobject]@{ Check = "PACKAGE.json metadata ($Flavor flavor)"; OK = [bool]$packageJsonLooksValid },
        [pscustomobject]@{ Check = "No forbidden research/build/GUI folders"; OK = [bool]$noForbiddenEntries }
    )
    if ($isFull) {
        $contentChecks += @(
            [pscustomobject]@{ Check = "Setup launcher MZ header"; OK = [bool]$setupLooksValid },
            [pscustomobject]@{ Check = "App icon ICO header"; OK = [bool]$iconLooksValid },
            [pscustomobject]@{ Check = "Tools folder allowlist"; OK = [bool]$toolsFolderLooksClean }
        )
    }

    $missing = @($results | Where-Object { -not $_.OK })
    $failedContent = @($contentChecks | Where-Object { -not $_.OK })

    if (-not $Quiet) {
        Write-Host "Package: $ZipPath"
        Write-Host "Flavor:  $Flavor"
        Write-Host "Entries: $($entries.Count)"
        Write-Host ""
        $results | Format-Table Path, Present, Size, RequiredSize, OK -AutoSize
        Write-Host ""
        $contentChecks | Format-Table Check, OK -AutoSize
        if ($forbiddenEntries.Count -gt 0) {
            Write-Host ""
            Write-Host "Forbidden entries:"
            $forbiddenEntries | Sort-Object | Format-Table -AutoSize
        }
        if ($unexpectedToolEntries.Count -gt 0) {
            Write-Host ""
            Write-Host "Unexpected tools entries:"
            $unexpectedToolEntries | Sort-Object | Format-Table -AutoSize
        }
    }

    if ($missing.Count -gt 0 -or $failedContent.Count -gt 0) {
        throw "Package verification failed: $($missing.Count) missing/undersized file(s), $($failedContent.Count) content check failure(s)."
    }

    Write-Host "Package verification passed ($Flavor flavor): $([System.IO.Path]::GetFileName($ZipPath))"
}
finally {
    $zip.Dispose()
}
