param(
    [string]$ZipPath = "",
    [string]$ExtractRoot = "",
    # "Full" = control panel + setup launcher + scripts. "Scripts" = PowerShell-only package (no GUI).
    # Empty = infer from the ZIP file name ("-scripts.zip" => Scripts).
    [ValidateSet("", "Full", "Scripts")]
    [string]$Flavor = "",
    [switch]$KeepExtracted,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    Split-Path -Parent $PSScriptRoot
}

function Test-RequiredFile {
    param(
        [string]$Root,
        [string]$RelativePath,
        [long]$MinBytes = 1
    )

    $path = Join-Path $Root $RelativePath
    $item = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
    [pscustomobject]@{
        RelativePath = $RelativePath
        Present = $null -ne $item
        Size = if ($item) { $item.Length } else { 0 }
        RequiredSize = $MinBytes
        OK = $null -ne $item -and $item.Length -ge $MinBytes
    }
}

function Read-Bytes {
    param(
        [string]$Path,
        [int]$Count
    )

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $buffer = New-Object byte[] $Count
        $read = $stream.Read($buffer, 0, $Count)
        if ($read -lt $Count) {
            return $null
        }

        return $buffer
    }
    finally {
        $stream.Dispose()
    }
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

$createdExtractRoot = $false
if ([string]::IsNullOrWhiteSpace($ExtractRoot)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $ExtractRoot = Join-Path ([System.IO.Path]::GetTempPath()) "StudioXdrPackageSmoke-$stamp"
    $createdExtractRoot = $true
}

if (Test-Path -LiteralPath $ExtractRoot) {
    Remove-Item -LiteralPath $ExtractRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $ExtractRoot | Out-Null

try {
    Expand-Archive -LiteralPath (Resolve-Path -LiteralPath $ZipPath).Path -DestinationPath $ExtractRoot -Force

    $requiredFiles = @(
        @{ Path = "scripts\Get-StudioXdrSupportReport.ps1"; MinBytes = 80 },
        @{ Path = "scripts\Install-StudioDisplayXdrSupport.ps1"; MinBytes = 80 },
        @{ Path = "scripts\Uninstall-StudioDisplayXdrSupport.ps1"; MinBytes = 80 },
        @{ Path = "scripts\Test-StudioDisplayXdrPackage.ps1"; MinBytes = 80 },
        @{ Path = "Studio-Display-XDR.cmd"; MinBytes = 20 },
        @{ Path = "Apple-Brightness-Tray.cmd"; MinBytes = 20 },
        @{ Path = "Check-Status.cmd"; MinBytes = 20 },
        @{ Path = "Check-Ambient.cmd"; MinBytes = 20 },
        @{ Path = "Prepare-Ambient-Driver.cmd"; MinBytes = 20 },
        @{ Path = "Check-Gaming.cmd"; MinBytes = 20 },
        @{ Path = "Check-Color.cmd"; MinBytes = 20 },
        @{ Path = "Install-StudioDisplayXdrSupport.cmd"; MinBytes = 20 },
        @{ Path = "scripts\Test-StudioXdrReadiness.ps1"; MinBytes = 80 },
        @{ Path = "scripts\Test-StudioDisplayXdrAppRuntime.ps1"; MinBytes = 80 },
        @{ Path = "scripts\Test-StudioDisplayXdrAppUi.ps1"; MinBytes = 80 },
        @{ Path = "scripts\Test-StudioDisplayXdrRelease.ps1"; MinBytes = 80 },
        @{ Path = "scripts\Test-StudioXdrAmbientPreflight.ps1"; MinBytes = 80 },
        @{ Path = "scripts\Test-StudioXdrAmbientDriverTarget.ps1"; MinBytes = 80 },
        @{ Path = "scripts\New-StudioXdrAmbientDriverPackage.ps1"; MinBytes = 80 },
        @{ Path = "scripts\Get-StudioXdrGamingStatus.ps1"; MinBytes = 80 },
        @{ Path = "scripts\Get-AppleDisplaySensorCorrelation.ps1"; MinBytes = 80 },
        @{ Path = "scripts\Find-StudioXdrColorProfiles.ps1"; MinBytes = 80 },
        @{ Path = "scripts\Dump-StudioXdrHidCollections.ps1"; MinBytes = 80 },
        @{ Path = "scripts\WindowsLightSensorTools.ps1"; MinBytes = 80 },
        @{ Path = "PACKAGE.json"; MinBytes = 20 },
        @{ Path = "README.md"; MinBytes = 20 },
        @{ Path = "RELEASE_NOTES.md"; MinBytes = 20 }
    )
    if ($isFull) {
        $requiredFiles += @(
            @{ Path = "StudioDisplayXdrSetup.exe"; MinBytes = 4096 },
            @{ Path = "assets\StudioDisplayXdr.ico"; MinBytes = 512 },
            @{ Path = "StudioDisplayXdr.App\StudioDisplayXdr.exe"; MinBytes = 4096 },
            @{ Path = "StudioDisplayXdr.App\StudioDisplayXdr.dll"; MinBytes = 4096 },
            @{ Path = "tools\LibUsbDotNet.LibUsbDotNet.net45.dll"; MinBytes = 1024 }
        )
    }

    $results = foreach ($file in $requiredFiles) {
        Test-RequiredFile -Root $ExtractRoot -RelativePath $file.Path -MinBytes $file.MinBytes
    }

    $setupPath = Join-Path $ExtractRoot "StudioDisplayXdrSetup.exe"
    $appPath = Join-Path $ExtractRoot "StudioDisplayXdr.App\StudioDisplayXdr.exe"
    $setupLooksValid = $false
    $appLooksValid = $false
    if ($isFull) {
        $setupHeader = Read-Bytes -Path $setupPath -Count 2
        $appHeader = Read-Bytes -Path $appPath -Count 2
        $setupLooksValid = $setupHeader -and $setupHeader[0] -eq [byte][char]"M" -and $setupHeader[1] -eq [byte][char]"Z"
        $appLooksValid = $appHeader -and $appHeader[0] -eq [byte][char]"M" -and $appHeader[1] -eq [byte][char]"Z"
    }
    $guiArtifactsAbsent =
        -not (Test-Path -LiteralPath $setupPath) -and
        -not (Test-Path -LiteralPath (Join-Path $ExtractRoot "StudioDisplayXdr.App")) -and
        -not (Test-Path -LiteralPath (Join-Path $ExtractRoot "tools")) -and
        -not (Test-Path -LiteralPath (Join-Path $ExtractRoot "assets"))

    $packageJson = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "PACKAGE.json") |
        ForEach-Object { $_.TrimStart([char]0xFEFF) } |
        ConvertFrom-Json
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

    $studioLauncherText = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "Studio-Display-XDR.cmd")
    $brightnessLauncherText = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "Apple-Brightness-Tray.cmd")
    $checkStatusLauncherText = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "Check-Status.cmd")
    $checkAmbientLauncherText = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "Check-Ambient.cmd")
    $prepareAmbientLauncherText = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "Prepare-Ambient-Driver.cmd")
    $checkGamingLauncherText = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "Check-Gaming.cmd")
    $checkColorLauncherText = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "Check-Color.cmd")
    $supportReportLauncherText = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "Support-Report.cmd")
    $installScriptText = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "scripts\Install-StudioDisplayXdrSupport.ps1")
    $uninstallScriptText = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "scripts\Uninstall-StudioDisplayXdrSupport.ps1")
    $ambientInstallScriptText = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "scripts\Install-StudioXdrAmbientConnector.ps1")
    $ambientPackageScriptText = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "scripts\New-StudioXdrAmbientDriverPackage.ps1")
    $ambientTargetCheckText = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "scripts\Test-StudioXdrAmbientDriverTarget.ps1")
    $ambientInfText = Get-Content -Raw -LiteralPath (Join-Path $ExtractRoot "drivers\StudioXdrAmbientWinUsb.inf")
    $ambientCatPath = Join-Path $ExtractRoot "drivers\StudioXdrAmbientWinUsb.cat"
    $launchersPreferStableInstalledApp =
        $studioLauncherText.Contains("%LOCALAPPDATA%\StudioDisplayXdr\Support\StudioDisplayXdr.App\StudioDisplayXdr.exe") -and
        $studioLauncherText.Contains("if exist ""%~dp0.git"" goto local_app") -and
        $studioLauncherText.Contains(":local_app") -and
        $studioLauncherText.Contains("%~dp0StudioDisplayXdr.App\StudioDisplayXdr.exe") -and
        $brightnessLauncherText.Contains("%LOCALAPPDATA%\StudioDisplayXdr\Support\StudioDisplayXdr.App\StudioDisplayXdr.exe") -and
        $brightnessLauncherText.Contains("if exist ""%~dp0.git"" goto local_app") -and
        $brightnessLauncherText.Contains(":local_app") -and
        $brightnessLauncherText.Contains("%~dp0StudioDisplayXdr.App\StudioDisplayXdr.exe")
    $consoleLaunchersPause =
        $checkStatusLauncherText.Contains("pause") -and
        $checkAmbientLauncherText.Contains("pause") -and
        $prepareAmbientLauncherText.Contains("pause") -and
        $checkGamingLauncherText.Contains("pause") -and
        $checkColorLauncherText.Contains("pause") -and
        $supportReportLauncherText.Contains("pause")
    $stableInstallSupported =
        $installScriptText.Contains("Install-AppPackage") -and
        $installScriptText.Contains("SkipAppInstall") -and
        $installScriptText.Contains("StudioDisplayXdr") -and
        $installScriptText.Contains("Support")
    $stableUninstallSupported =
        $uninstallScriptText.Contains("Remove-InstalledAppPackage") -and
        $uninstallScriptText.Contains("KeepInstalledApp") -and
        $uninstallScriptText.Contains("Assert-SafeInstallRoot")
    $ambientShortcutSupported =
        $installScriptText.Contains("Studio Display XDR Check Ambient.lnk") -and
        $uninstallScriptText.Contains("Studio Display XDR Check Ambient.lnk")
    $colorShortcutSupported =
        $installScriptText.Contains("Studio Display XDR Check Color.lnk") -and
        $uninstallScriptText.Contains("Studio Display XDR Check Color.lnk")
    $ambientInfTargetsExactMi08 =
        $ambientInfText.Contains("USB\VID_05AC&PID_1116&REV_1801&MI_08") -and
        $ambientInfText.Contains("USB\VID_05AC&PID_1116&MI_08") -and
        $ambientInfText.Contains("6F94F6F0-7B76-4DFB-AD85-905E20C82D9D") -and
        $ambientInfText.Contains("CatalogFile = StudioXdrAmbientWinUsb.cat")
    $ambientSignedCatalogNotBundled = -not (Test-Path -LiteralPath $ambientCatPath)
    $ambientInfUsesDocumentedWinUsbPattern =
        $ambientInfText.Contains("Needs   = WINUSB.NT") -and
        $ambientInfText.Contains("Needs   = WINUSB.NT.Services") -and
        -not $ambientInfText.Contains("WinUSB_ServiceInstall") -and
        -not $ambientInfText.Contains("AddService = WinUSB")
    $ambientTargetIncludesPnpDriverView =
        $ambientTargetCheckText.Contains("pnputil /enum-devices") -and
        $ambientTargetCheckText.Contains("PnpUtilMatchingDriverNames") -and
        $ambientTargetCheckText.Contains("PnPUtil matching-driver view")
    $ambientInstallShowsTargetChecks =
        $ambientInstallScriptText.Contains("Preflight target check") -and
        $ambientInstallScriptText.Contains("Post-install target check") -and
        $ambientInstallScriptText.Contains("signed catalog") -and
        $ambientInstallScriptText.Contains("AddDriverExitCode") -and
        $ambientInstallScriptText.Contains("InstallDriverExitCode")
    $ambientPackageScriptSupported =
        $ambientPackageScriptText.Contains("inf2cat.exe") -and
        $ambientPackageScriptText.Contains("signtool.exe") -and
        $ambientPackageScriptText.Contains("New-SelfSignedCertificate") -and
        $ambientPackageScriptText.Contains("StudioXdrAmbientWinUsb.cat") -and
        $ambientPackageScriptText.Contains("CheckOnly")

    $reportPath = Join-Path $ExtractRoot "smoke-support.txt"
    $supportScript = Join-Path $ExtractRoot "scripts\Get-StudioXdrSupportReport.ps1"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $supportScript -OutputPath $reportPath | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Extracted support report failed with exit code $LASTEXITCODE."
    }
    if (-not (Test-Path -LiteralPath $reportPath)) {
        throw "Extracted support report did not write the expected file: $reportPath"
    }

    $reportText = Get-Content -Raw -LiteralPath $reportPath
    $reportLooksValid =
        $reportText.Contains("== Package Artifacts ==") -and
        $reportText.Contains("== App Configuration ==") -and
        $reportText.Contains("== Ambient Driver Target ==") -and
        $reportText.Contains("== Ambient Driver Package Signing ==") -and
        $reportText.Contains("== Gaming And Tearing Diagnostic ==") -and
        $reportText.Contains("== Studio Display XDR HID Collections ==") -and
        $reportText.Contains("== Apple Display Sensor Correlation ==") -and
        $reportText.Contains("SettingsPath") -and
        $reportText.Contains("OpenAtLoginEnabled") -and
        $reportText.Contains("StableInstallRoot") -and
        $reportText.Contains("drivers\StudioXdrAmbientWinUsb.inf") -and
        $reportText.Contains("PACKAGE.json")
    if ($isFull) {
        $reportLooksValid = $reportLooksValid -and
            $reportText.Contains("StudioDisplayXdrSetup.exe") -and
            $reportText.Contains("StudioDisplayXdr.App\StudioDisplayXdr.exe") -and
            $reportText.Contains("assets\StudioDisplayXdr.ico") -and
            $reportText.Contains("tools\LibUsbDotNet.LibUsbDotNet.net45.dll")
    }
    else {
        # Root GUI artifacts must not be listed for the scripts-only package. Rows from a stable
        # per-user install on this machine are prefixed with "installed\" and are allowed.
        $reportLooksValid = $reportLooksValid -and
            -not ($reportText -match "(?m)^StudioDisplayXdrSetup\.exe\s") -and
            -not ($reportText -match "(?m)^StudioDisplayXdr\.App\\StudioDisplayXdr\.exe\s")
    }

    $contentChecks = @(
        [pscustomobject]@{ Check = "PACKAGE.json metadata ($Flavor flavor)"; OK = [bool]$packageJsonLooksValid },
        [pscustomobject]@{ Check = "Launchers prefer stable installed app"; OK = [bool]$launchersPreferStableInstalledApp },
        [pscustomobject]@{ Check = "Console launchers pause"; OK = [bool]$consoleLaunchersPause },
        [pscustomobject]@{ Check = "Installer stages stable app copy"; OK = [bool]$stableInstallSupported },
        [pscustomobject]@{ Check = "Uninstaller removes stable app copy"; OK = [bool]$stableUninstallSupported },
        [pscustomobject]@{ Check = "Installer manages ambient shortcut"; OK = [bool]$ambientShortcutSupported },
        [pscustomobject]@{ Check = "Installer manages color shortcut"; OK = [bool]$colorShortcutSupported },
        [pscustomobject]@{ Check = "Ambient WinUSB INF exact MI_08 target"; OK = [bool]$ambientInfTargetsExactMi08 },
        [pscustomobject]@{ Check = "Ambient test-signed catalog not bundled"; OK = [bool]$ambientSignedCatalogNotBundled },
        [pscustomobject]@{ Check = "Ambient WinUSB INF documented include pattern"; OK = [bool]$ambientInfUsesDocumentedWinUsbPattern },
        [pscustomobject]@{ Check = "Ambient target PnP driver-ranking view"; OK = [bool]$ambientTargetIncludesPnpDriverView },
        [pscustomobject]@{ Check = "Ambient installer reports before/after target state"; OK = [bool]$ambientInstallShowsTargetChecks },
        [pscustomobject]@{ Check = "Ambient driver package signing helper"; OK = [bool]$ambientPackageScriptSupported },
        [pscustomobject]@{ Check = "Extracted support report artifacts"; OK = [bool]$reportLooksValid }
    )
    if ($isFull) {
        $contentChecks += @(
            [pscustomobject]@{ Check = "Setup launcher MZ header"; OK = [bool]$setupLooksValid },
            [pscustomobject]@{ Check = "Control panel MZ header"; OK = [bool]$appLooksValid }
        )
    }
    else {
        $contentChecks += @(
            [pscustomobject]@{ Check = "No GUI artifacts in scripts-only package"; OK = [bool]$guiArtifactsAbsent }
        )
    }

    $missing = @($results | Where-Object { -not $_.OK })
    $failedContent = @($contentChecks | Where-Object { -not $_.OK })

    if (-not $Quiet) {
        Write-Host "Extracted package: $ExtractRoot"
        Write-Host "Flavor: $Flavor"
        Write-Host ""
        $results | Format-Table RelativePath, Present, Size, RequiredSize, OK -AutoSize
        Write-Host ""
        $contentChecks | Format-Table Check, OK -AutoSize
        Write-Host ""
        Write-Host "Support report: $reportPath"
    }

    if ($missing.Count -gt 0 -or $failedContent.Count -gt 0) {
        throw "Extracted package smoke test failed: $($missing.Count) missing/undersized file(s), $($failedContent.Count) content check failure(s)."
    }

    Write-Host "Extracted package smoke test passed ($Flavor flavor): $([System.IO.Path]::GetFileName($ZipPath))"
}
finally {
    if ($createdExtractRoot -and -not $KeepExtracted -and (Test-Path -LiteralPath $ExtractRoot)) {
        Remove-Item -LiteralPath $ExtractRoot -Recurse -Force
    }
}
