param(
    [string]$DriverDirectory = "",
    [string]$CertificateSubject = "CN=Studio Display XDR Ambient Test Signing",
    [string]$OsList = "10_X64,10_GE_X64",
    [switch]$InstallCertificate,
    [switch]$SkipSigning,
    [switch]$CheckOnly,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Find-Tool {
    param(
        [string]$Name,
        [string[]]$PreferredArchitectures = @("x64", "x86")
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $roots = @()
    if (-not [string]::IsNullOrWhiteSpace($env:WindowsSdkDir)) {
        $roots += $env:WindowsSdkDir
    }

    $roots += @(
        "${env:ProgramFiles(x86)}\Windows Kits\10",
        "$env:ProgramFiles\Windows Kits\10",
        "${env:ProgramFiles(x86)}\Windows Kits\11",
        "$env:ProgramFiles\Windows Kits\11"
    )

    foreach ($root in $roots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        $matches = @(Get-ChildItem -LiteralPath $root -Recurse -Filter $Name -File -ErrorAction SilentlyContinue)
        foreach ($architecture in $PreferredArchitectures) {
            $match = $matches |
                Where-Object { $_.FullName -match "\\$([regex]::Escape($architecture))\\$([regex]::Escape($Name))$" } |
                Sort-Object FullName -Descending |
                Select-Object -First 1
            if ($match) {
                return $match.FullName
            }
        }

        $match = $matches | Sort-Object FullName -Descending | Select-Object -First 1
        if ($match) {
            return $match.FullName
        }
    }

    return $null
}

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "InstallCertificate requires an elevated PowerShell session."
    }
}

function Invoke-Tool {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        FilePath = $FilePath
        Arguments = @($Arguments)
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { "$_" })
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
if ([string]::IsNullOrWhiteSpace($DriverDirectory)) {
    $DriverDirectory = Join-Path $repoRoot "drivers"
}
$DriverDirectory = (Resolve-Path -LiteralPath $DriverDirectory).Path
$infPath = Join-Path $DriverDirectory "StudioXdrAmbientWinUsb.inf"
$catPath = Join-Path $DriverDirectory "StudioXdrAmbientWinUsb.cat"

if (-not (Test-Path -LiteralPath $infPath)) {
    throw "Ambient WinUSB INF was not found: $infPath"
}

$infText = Get-Content -Raw -LiteralPath $infPath
if ($infText -notmatch "(?im)^\s*CatalogFile\s*=\s*StudioXdrAmbientWinUsb\.cat\s*$") {
    throw "The INF must declare CatalogFile = StudioXdrAmbientWinUsb.cat before Inf2Cat can generate the catalog."
}

$inf2cat = Find-Tool -Name "inf2cat.exe" -PreferredArchitectures @("x86", "x64")
$signtool = Find-Tool -Name "signtool.exe" -PreferredArchitectures @("x64", "x86")

$steps = New-Object System.Collections.Generic.List[object]
$createdCertificate = $null
$existingCertificate = $null
$inf2catResult = $null
$signResult = $null
$verifyResult = $null

if (-not $inf2cat) {
    $steps.Add([pscustomobject]@{
        Step = "Find Inf2Cat"
        Status = "Missing"
        Detail = "Install the Windows Driver Kit. Inf2Cat is required to generate StudioXdrAmbientWinUsb.cat."
    })
}
else {
    $steps.Add([pscustomobject]@{
        Step = "Find Inf2Cat"
        Status = "Ready"
        Detail = $inf2cat
    })
}

if (-not $signtool) {
    $steps.Add([pscustomobject]@{
        Step = "Find SignTool"
        Status = if ($SkipSigning) { "Skipped" } else { "Missing" }
        Detail = "Install the Windows SDK/WDK. SignTool is required to test-sign StudioXdrAmbientWinUsb.cat."
    })
}
else {
    $steps.Add([pscustomobject]@{
        Step = "Find SignTool"
        Status = "Ready"
        Detail = $signtool
    })
}

if ($CheckOnly) {
    $steps.Add([pscustomobject]@{
        Step = "Check catalog"
        Status = if (Test-Path -LiteralPath $catPath) { "Ready" } else { "Missing" }
        Detail = if (Test-Path -LiteralPath $catPath) { "Catalog exists." } else { "Catalog has not been generated yet." }
    })

    $existingCertificate = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq $CertificateSubject } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1

    $steps.Add([pscustomobject]@{
        Step = "Check test certificate"
        Status = if ($existingCertificate) { "Ready" } else { "Missing" }
        Detail = if ($existingCertificate) { "$($existingCertificate.Subject) thumbprint $($existingCertificate.Thumbprint)" } else { "No matching current-user code-signing certificate was found." }
    })
}
elseif ($inf2cat) {
    $inf2catResult = Invoke-Tool -FilePath $inf2cat -Arguments @("/driver:$DriverDirectory", "/os:$OsList", "/uselocaltime", "/verbose")
    $steps.Add([pscustomobject]@{
        Step = "Generate catalog"
        Status = if ($inf2catResult.ExitCode -eq 0 -and (Test-Path -LiteralPath $catPath)) { "Ready" } else { "Failed" }
        Detail = ($inf2catResult.Output -join "`n").Trim()
    })
}

if (-not $CheckOnly -and -not $SkipSigning -and $signtool -and (Test-Path -LiteralPath $catPath)) {
    $existingCertificate = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq $CertificateSubject } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1

    if (-not $existingCertificate) {
        $createdCertificate = New-SelfSignedCertificate `
            -Type CodeSigningCert `
            -Subject $CertificateSubject `
            -CertStoreLocation Cert:\CurrentUser\My `
            -KeyUsage DigitalSignature `
            -KeyAlgorithm RSA `
            -KeyLength 2048 `
            -HashAlgorithm SHA256
        $existingCertificate = $createdCertificate
    }

    $steps.Add([pscustomobject]@{
        Step = "Find test certificate"
        Status = "Ready"
        Detail = "$($existingCertificate.Subject) thumbprint $($existingCertificate.Thumbprint)"
    })

    if ($InstallCertificate) {
        Assert-Admin
        $rootStore = [System.Security.Cryptography.X509Certificates.X509Store]::new("Root", "LocalMachine")
        $publisherStore = [System.Security.Cryptography.X509Certificates.X509Store]::new("TrustedPublisher", "LocalMachine")
        try {
            $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
            $rootStore.Add($existingCertificate)
        }
        finally {
            $rootStore.Close()
        }
        try {
            $publisherStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
            $publisherStore.Add($existingCertificate)
        }
        finally {
            $publisherStore.Close()
        }

        $steps.Add([pscustomobject]@{
            Step = "Trust test certificate"
            Status = "Ready"
            Detail = "Installed into LocalMachine Root and TrustedPublisher stores."
        })
    }
    else {
        $steps.Add([pscustomobject]@{
            Step = "Trust test certificate"
            Status = "Skipped"
            Detail = "Pass -InstallCertificate from an elevated PowerShell to trust this test certificate locally."
        })
    }

    $signResult = Invoke-Tool -FilePath $signtool -Arguments @(
        "sign",
        "/v",
        "/fd", "SHA256",
        "/sha1", $existingCertificate.Thumbprint,
        "/tr", "http://timestamp.digicert.com",
        "/td", "SHA256",
        $catPath
    )
    $steps.Add([pscustomobject]@{
        Step = "Sign catalog"
        Status = if ($signResult.ExitCode -eq 0) { "Ready" } else { "Failed" }
        Detail = ($signResult.Output -join "`n").Trim()
    })

    $verifyResult = Invoke-Tool -FilePath $signtool -Arguments @("verify", "/v", "/pa", $catPath)
    $steps.Add([pscustomobject]@{
        Step = "Verify catalog"
        Status = if ($verifyResult.ExitCode -eq 0) { "Ready" } else { "Warn" }
        Detail = ($verifyResult.Output -join "`n").Trim()
    })
}
elseif ($SkipSigning) {
    $steps.Add([pscustomobject]@{
        Step = "Sign catalog"
        Status = "Skipped"
        Detail = "Catalog signing was skipped by request."
    })
}

$catalogExists = Test-Path -LiteralPath $catPath
$ready = $catalogExists -and ($SkipSigning -or $CheckOnly -or ($signResult -and $signResult.ExitCode -eq 0))
$certificateThumbprint = $null
if ($existingCertificate) {
    $certificateThumbprint = $existingCertificate.Thumbprint
}
$stepArray = @($steps.ToArray())
$result = [pscustomobject][ordered]@{
    Ready = [bool]$ready
    CheckOnly = [bool]$CheckOnly
    DriverDirectory = [string]$DriverDirectory
    InfPath = [string]$infPath
    CatalogPath = [string]$catPath
    CatalogExists = [bool]$catalogExists
    Inf2CatPath = [string]$inf2cat
    SignToolPath = [string]$signtool
    CertificateSubject = [string]$CertificateSubject
    CertificateThumbprint = [string]$certificateThumbprint
    CertificateCreated = [bool]$createdCertificate
    CertificateTrusted = [bool]$InstallCertificate
    Steps = $stepArray
}

if ($Json) {
    $result | ConvertTo-Json -Depth 8
    return
}

Write-Host "Studio Display XDR ambient driver package preparation"
Write-Host ""
$result | Select-Object Ready,DriverDirectory,InfPath,CatalogPath,CatalogExists,Inf2CatPath,SignToolPath,CertificateSubject,CertificateThumbprint,CertificateCreated,CertificateTrusted | Format-List
Write-Host ""
$steps | Format-Table Step,Status,Detail -AutoSize -Wrap

if (-not $ready) {
    Write-Host ""
    Write-Host "Next steps:"
    if (-not $inf2cat -or -not $signtool) {
        Write-Host "- Install the Windows Driver Kit so inf2cat.exe and signtool.exe are available."
    }
    if ($catalogExists -and -not $SkipSigning -and -not $InstallCertificate) {
        Write-Host "- Re-run from elevated PowerShell with -InstallCertificate if you want Windows to trust the local test certificate."
    }
    Write-Host "- After the catalog is signed/trusted, run Install-Ambient-Connector.cmd and then Check-Ambient.cmd."
}
