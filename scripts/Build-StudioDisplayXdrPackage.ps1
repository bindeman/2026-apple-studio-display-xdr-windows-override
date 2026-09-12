param(
    # Package version stamped into PACKAGE.json. Defaults to the repo-root VERSION file.
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$appProject = Join-Path $repoRoot "src\StudioDisplayXdr.App\StudioDisplayXdr.App.csproj"
$setupSource = Join-Path $repoRoot "src\StudioDisplayXdr.Setup\StudioDisplayXdrSetup.cs"
$publishOutput = Join-Path $repoRoot "src\StudioDisplayXdr.App\bin\Release\net8.0-windows10.0.19041.0\win-x64\publish"
$appDist = Join-Path $repoRoot "dist\StudioDisplayXdr.App"
$zipPath = Join-Path $repoRoot "dist\studio-display-xdr-windows.zip"
$scriptsZipPath = Join-Path $repoRoot "dist\studio-display-xdr-windows-scripts.zip"
$packageMetadataPath = Join-Path $repoRoot "PACKAGE.json"
$packageMetadataRoot = Join-Path $repoRoot "dist\PackageMetadata"
$scriptsPackageMetadataPath = Join-Path $packageMetadataRoot "scripts\PACKAGE.json"
$iconPath = Join-Path $repoRoot "assets\StudioDisplayXdr.ico"
$packageToolsRoot = Join-Path $repoRoot "dist\PackageTools"
$packageToolsDir = Join-Path $packageToolsRoot "tools"
$packageSetupRoot = Join-Path $repoRoot "dist\PackageSetup"
$packageSetupExe = Join-Path $packageSetupRoot "StudioDisplayXdrSetup.exe"
$versionFile = Join-Path $repoRoot "VERSION"

if ([string]::IsNullOrWhiteSpace($Version)) {
    if (Test-Path -LiteralPath $versionFile) {
        $Version = (Get-Content -LiteralPath $versionFile -Raw).Trim()
    }
    else {
        $Version = "0.0.0-dev"
    }
}

Get-Process StudioDisplayXdr -ErrorAction SilentlyContinue | Stop-Process -Force

if (-not (Test-Path -LiteralPath $iconPath)) {
    & (Join-Path $PSScriptRoot "New-StudioXdrIcon.ps1") -OutputPath $iconPath | Out-Null
}

dotnet publish $appProject -c Release -r win-x64 --self-contained true -p:PublishSingleFile=false
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE."
}

New-Item -ItemType Directory -Force -Path (Join-Path $repoRoot "dist") | Out-Null
foreach ($stagingDir in @($appDist, $packageToolsRoot, $packageSetupRoot, $packageMetadataRoot)) {
    if (Test-Path -LiteralPath $stagingDir) {
        Remove-Item -LiteralPath $stagingDir -Recurse -Force
    }
}
New-Item -ItemType Directory -Force -Path $appDist | Out-Null
New-Item -ItemType Directory -Force -Path $packageSetupRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $scriptsPackageMetadataPath) | Out-Null
Copy-Item -Path (Join-Path $publishOutput "*") -Destination $appDist -Recurse -Force

$csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path -LiteralPath $csc)) {
    throw "Could not find .NET Framework C# compiler: $csc"
}
$cscArgs = @(
    "/nologo",
    "/target:winexe",
    "/optimize+",
    "/out:$packageSetupExe",
    "/reference:System.Windows.Forms.dll",
    "/reference:System.Drawing.dll",
    "/reference:System.Core.dll"
)
if (Test-Path -LiteralPath $iconPath) {
    $cscArgs += "/win32icon:$iconPath"
}
$cscArgs += $setupSource
& $csc @cscArgs
if ($LASTEXITCODE -ne 0) {
    throw "Failed to build StudioDisplayXdrSetup.exe."
}

$libUsbNet45 = Join-Path $env:USERPROFILE ".nuget\packages\libusbdotnet\2.2.29\lib\net45\LibUsbDotNet.LibUsbDotNet.dll"
if (Test-Path -LiteralPath $libUsbNet45) {
    New-Item -ItemType Directory -Force -Path $packageToolsDir | Out-Null
    Copy-Item -LiteralPath $libUsbNet45 -Destination (Join-Path $packageToolsDir "LibUsbDotNet.LibUsbDotNet.net45.dll") -Force
}

$gitCommit = ""
$gitBranch = ""
$gitDirty = $false
if (Get-Command git -ErrorAction SilentlyContinue) {
    try { $gitCommit = (git -C $repoRoot rev-parse HEAD 2>$null) } catch { }
    try { $gitBranch = (git -C $repoRoot branch --show-current 2>$null) } catch { }
    try { $gitDirty = [bool](git -C $repoRoot status --porcelain 2>$null) } catch { }
}

$builtAt = (Get-Date).ToUniversalTime().ToString("o")

function Write-PackageMetadata {
    param(
        [string]$Flavor,
        [string]$OutputPath,
        [string]$ZipRelativePath,
        [string]$AppRuntime,
        [string]$AppPath,
        [string]$SetupPath
    )

    [ordered]@{
        name = "studio-display-xdr-windows"
        description = "Windows support package for 2026 Apple Studio Display XDR"
        version = $Version
        flavor = $Flavor
        builtAt = $builtAt
        appRuntime = $AppRuntime
        appPath = $AppPath
        setupPath = $SetupPath
        zipPath = $ZipRelativePath
        gitCommit = $gitCommit
        gitBranch = $gitBranch
        gitDirty = $gitDirty
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

# Full package (GUI): control panel + setup launcher + scripts. Its PACKAGE.json also
# stays at the repo root so development checkouts and the app's About row can read it.
Write-PackageMetadata -Flavor "full" -OutputPath $packageMetadataPath -ZipRelativePath "dist/studio-display-xdr-windows.zip" `
    -AppRuntime "win-x64 self-contained" -AppPath "StudioDisplayXdr.App/StudioDisplayXdr.exe" -SetupPath "StudioDisplayXdrSetup.exe"

# Scripts-only package (no GUI): PowerShell scripts, launchers, EDID, profile, docs.
Write-PackageMetadata -Flavor "scripts" -OutputPath $scriptsPackageMetadataPath -ZipRelativePath "dist/studio-display-xdr-windows-scripts.zip" `
    -AppRuntime "none (Windows PowerShell 5.1 scripts only)" -AppPath "" -SetupPath ""

foreach ($existingZip in @($zipPath, $scriptsZipPath)) {
    if (Test-Path -LiteralPath $existingZip) {
        Remove-Item -LiteralPath $existingZip -Force
    }
}

$commonItems = @(
    "README.md",
    "LICENSE",
    "THIRD_PARTY_NOTICES.md",
    "CONTINUE.md",
    "RELEASE_NOTES.md",
    "Install-StudioDisplayXdrSupport.cmd",
    "Prepare-Ambient-Driver.cmd",
    "Install-Ambient-Connector.cmd",
    "Install-LibUsb-Ambient-Filter.cmd",
    "Install-Color-Profile.cmd",
    "Install-StudioXdr.cmd",
    "Uninstall-StudioDisplayXdrSupport.cmd",
    "Uninstall-LibUsb-Ambient-Filter.cmd",
    "Check-Status.cmd",
    "Check-Ambient.cmd",
    "Check-Gaming.cmd",
    "Check-Color.cmd",
    "Enable-HDR.cmd",
    "Disable-HDR.cmd",
    "Studio-Display-XDR.cmd",
    "Support-Report.cmd",
    "Apple-Brightness-Tray.cmd",
    "Brightness-Up.cmd",
    "Brightness-Down.cmd",
    "Brightness-Status.cmd",
    "Uninstall-Override.cmd",
    "drivers",
    "edid",
    "profiles",
    "scripts",
    "docs"
)

$fullItems = @(
    "PACKAGE.json",
    "dist\PackageSetup\StudioDisplayXdrSetup.exe",
    "assets",
    "dist\PackageTools\tools",
    "dist\StudioDisplayXdr.App"
) + $commonItems

$scriptsItems = @(
    "dist\PackageMetadata\scripts\PACKAGE.json"
) + $commonItems

Compress-Archive -Path ($fullItems | ForEach-Object { Join-Path $repoRoot $_ }) -DestinationPath $zipPath -Force
Compress-Archive -Path ($scriptsItems | ForEach-Object { Join-Path $repoRoot $_ }) -DestinationPath $scriptsZipPath -Force

& (Join-Path $PSScriptRoot "Test-StudioDisplayXdrPackage.ps1") -ZipPath $zipPath -Flavor Full -Quiet
& (Join-Path $PSScriptRoot "Test-StudioDisplayXdrPackage.ps1") -ZipPath $scriptsZipPath -Flavor Scripts -Quiet

Get-Item -LiteralPath $zipPath
Get-Item -LiteralPath $scriptsZipPath
