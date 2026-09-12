param(
    [string]$AppPath = "",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes

function Get-RepoRoot {
    Split-Path -Parent $PSScriptRoot
}

function Resolve-AppPath {
    param([string]$Candidate)

    if (-not [string]::IsNullOrWhiteSpace($Candidate)) {
        return (Resolve-Path -LiteralPath $Candidate).Path
    }

    $root = Get-RepoRoot
    $candidates = @(
        (Join-Path $root "StudioDisplayXdr.App\StudioDisplayXdr.exe"),
        (Join-Path $root "dist\StudioDisplayXdr.App\StudioDisplayXdr.exe")
    )

    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    throw "StudioDisplayXdr.exe was not found. Build the package first."
}

function Resolve-PackageRootFromApp {
    param([string]$ResolvedAppPath)

    $directory = Get-Item -LiteralPath (Split-Path -Parent $ResolvedAppPath)
    while ($null -ne $directory) {
        if ((Test-Path -LiteralPath (Join-Path $directory.FullName "scripts\Get-StudioXdrSupportReport.ps1")) -and
            (Test-Path -LiteralPath (Join-Path $directory.FullName "README.md"))) {
            return $directory.FullName
        }

        $directory = $directory.Parent
    }

    throw "Package root could not be resolved from app path: $ResolvedAppPath"
}

function Stop-TestProcesses {
    Get-Process StudioDisplayXdr -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

function Wait-ForMainWindow {
    param([int]$ProcessId)

    $deadline = (Get-Date).AddSeconds(20)
    do {
        $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($process -and $process.MainWindowHandle -ne 0) {
            return $process.MainWindowHandle
        }

        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)

    throw "StudioDisplayXdr window did not appear."
}

function Find-ElementByAutomationId {
    param(
        [System.Windows.Automation.AutomationElement]$Root,
        [string]$AutomationId
    )

    $condition = New-Object System.Windows.Automation.PropertyCondition `
        ([System.Windows.Automation.AutomationElement]::AutomationIdProperty), $AutomationId
    $element = $Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
    if ($null -eq $element) {
        throw "Automation element not found: $AutomationId"
    }

    $element
}

function Invoke-Button {
    param([System.Windows.Automation.AutomationElement]$Element)

    $pattern = $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $pattern.Invoke()
}

function Resolve-ReportPath {
    param(
        [string]$PackageRoot,
        [string]$Text
    )

    if ($Text -notmatch "Report saved:\s*(.+)$") {
        return $null
    }

    $path = $matches[1].Trim()
    if ([System.IO.Path]::IsPathRooted($path)) {
        return $path
    }

    Join-Path $PackageRoot $path
}

function Wait-ForTextMatch {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [string]$Pattern,
        [int]$TimeoutSeconds = 45
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $text = $Element.Current.Name
        if ($text -match $Pattern) {
            return $text
        }

        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for '$Pattern'. Last text: $($Element.Current.Name)"
}

$app = Resolve-AppPath -Candidate $AppPath
$packageRoot = Resolve-PackageRootFromApp -ResolvedAppPath $app
$results = New-Object System.Collections.Generic.List[object]

Stop-TestProcesses

try {
    $process = Start-Process -FilePath $app -PassThru
    $handle = Wait-ForMainWindow -ProcessId $process.Id
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($handle)

    $colorButton = Find-ElementByAutomationId -Root $root -AutomationId "ColorProfileCheckButton"
    $colorText = Find-ElementByAutomationId -Root $root -AutomationId "ColorProfileText"
    Invoke-Button -Element $colorButton
    $colorResult = Wait-ForTextMatch -Element $colorText -Pattern "Color check found|Could not check color profiles"
    $results.Add([pscustomobject]@{
        Check = "Color profile check button"
        OK = $colorResult -match "Color check found"
        Detail = $colorResult
    })

    $ambientButton = Find-ElementByAutomationId -Root $root -AutomationId "AmbientCheckButton"
    $ambientText = Find-ElementByAutomationId -Root $root -AutomationId "AutoBrightnessText"
    Invoke-Button -Element $ambientButton
    $ambientResult = Wait-ForTextMatch -Element $ambientText -Pattern "Ambient check:|Could not run ambient check"
    $results.Add([pscustomobject]@{
        Check = "Ambient preflight button"
        OK = $ambientResult -match "Ambient check:" -and
            ($ambientResult -match "WinUSB package|WinUSB connector|package target") -and
            ($ambientResult -match "Prepare Ambient|WDK|catalog")
        Detail = $ambientResult
    })

    $readinessButton = Find-ElementByAutomationId -Root $root -AutomationId "DiagnosticsCheckButton"
    $readinessText = Find-ElementByAutomationId -Root $root -AutomationId "DiagnosticsText"
    Invoke-Button -Element $readinessButton
    $readinessResult = Wait-ForTextMatch -Element $readinessText -Pattern "Readiness check:|Could not run readiness check"
    $results.Add([pscustomobject]@{
        Check = "Diagnostics readiness button"
        OK = $readinessResult -match "Readiness check:"
        Detail = $readinessResult
    })

    $reportButton = Find-ElementByAutomationId -Root $root -AutomationId "DiagnosticsReportButton"
    Invoke-Button -Element $reportButton
    $reportResult = Wait-ForTextMatch -Element $readinessText -Pattern "Report saved:|Could not generate report" -TimeoutSeconds 120
    $reportPath = Resolve-ReportPath -PackageRoot $packageRoot -Text $reportResult
    $reportContent = if ($reportPath -and (Test-Path -LiteralPath $reportPath)) {
        Get-Content -Raw -LiteralPath $reportPath
    }
    else {
        ""
    }

    $results.Add([pscustomobject]@{
        Check = "Diagnostics support report button"
        OK = $reportResult -match "Report saved:" -and
            $reportPath -and
            (Test-Path -LiteralPath $reportPath) -and
            $reportContent.Contains("== App Configuration ==") -and
            $reportContent.Contains("OpenAtLoginEnabled")
        Detail = if ($reportPath) { $reportPath } else { $reportResult }
    })

    $aboutText = Find-ElementByAutomationId -Root $root -AutomationId "AboutText"
    $aboutResult = Wait-ForTextMatch -Element $aboutText -Pattern "Package (v\S+ )?built|Development build|Package metadata unavailable" -TimeoutSeconds 10
    $results.Add([pscustomobject]@{
        Check = "Package metadata visible"
        OK = $aboutResult -match "Package (v\S+ )?built|Development build"
        Detail = $aboutResult
    })
}
finally {
    Stop-TestProcesses
}

$failed = @($results | Where-Object { -not $_.OK })

if (-not $Quiet) {
    $results | Format-Table Check, OK, Detail -AutoSize -Wrap
}

if ($failed.Count -gt 0) {
    throw "Studio Display XDR app UI smoke test failed."
}

if (-not $Quiet) {
    Write-Host "Studio Display XDR app UI smoke test passed."
}
