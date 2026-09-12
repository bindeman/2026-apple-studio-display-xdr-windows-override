param(
    [switch]$SkipBuild,
    [switch]$SkipInteractiveApp,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$results = New-Object System.Collections.Generic.List[object]

function Invoke-ReleaseStep {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    $started = Get-Date
    if (-not $Quiet) {
        Write-Host "== $Name =="
    }

    try {
        & $Action
        $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        $script:results.Add([pscustomobject]@{
            Step = $Name
            Status = "Pass"
            Seconds = $elapsed
        })
        if (-not $Quiet) {
            Write-Host "PASS $Name ($elapsed s)"
            Write-Host ""
        }
    }
    catch {
        $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        $script:results.Add([pscustomobject]@{
            Step = $Name
            Status = "Fail"
            Seconds = $elapsed
        })
        if (-not $Quiet) {
            Write-Host "FAIL $Name ($elapsed s)" -ForegroundColor Red
        }
        throw
    }
}

Push-Location $repoRoot
try {
    if (-not $SkipBuild) {
        Invoke-ReleaseStep "Build package" {
            & (Join-Path $PSScriptRoot "Build-StudioDisplayXdrPackage.ps1") | Out-Host
        }
    }

    $fullZip = Join-Path $repoRoot "dist\studio-display-xdr-windows.zip"
    $scriptsZip = Join-Path $repoRoot "dist\studio-display-xdr-windows-scripts.zip"

    Invoke-ReleaseStep "Verify full package ZIP (GUI)" {
        & (Join-Path $PSScriptRoot "Test-StudioDisplayXdrPackage.ps1") -ZipPath $fullZip -Flavor Full -Quiet
    }

    Invoke-ReleaseStep "Verify scripts-only package ZIP (no GUI)" {
        & (Join-Path $PSScriptRoot "Test-StudioDisplayXdrPackage.ps1") -ZipPath $scriptsZip -Flavor Scripts -Quiet
    }

    Invoke-ReleaseStep "Smoke test extracted full package" {
        & (Join-Path $PSScriptRoot "Test-StudioDisplayXdrExtractedPackage.ps1") -ZipPath $fullZip -Flavor Full -Quiet
    }

    Invoke-ReleaseStep "Smoke test extracted scripts-only package" {
        & (Join-Path $PSScriptRoot "Test-StudioDisplayXdrExtractedPackage.ps1") -ZipPath $scriptsZip -Flavor Scripts -Quiet
    }

    if (-not $SkipInteractiveApp) {
        Invoke-ReleaseStep "Smoke test app runtime" {
            & (Join-Path $PSScriptRoot "Test-StudioDisplayXdrAppRuntime.ps1") -Quiet
        }

        Invoke-ReleaseStep "Smoke test app UI" {
            & (Join-Path $PSScriptRoot "Test-StudioDisplayXdrAppUi.ps1") -Quiet
        }
    }
    elseif (-not $Quiet) {
        Write-Host "Skipping interactive app runtime/UI smoke tests."
        Write-Host ""
    }
}
finally {
    Pop-Location
}

if (-not $Quiet) {
    $results | Format-Table Step, Status, Seconds -AutoSize
    Write-Host ""
    Write-Host "Studio Display XDR release gate passed."
}
