param(
    [string]$AppPath = "",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

Add-Type -Name WindowProbe -Namespace StudioXdrRuntimeTest -MemberDefinition @"
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool IsWindowVisible(System.IntPtr hWnd);
"@

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

function Get-ProcessSnapshot {
    @(Get-Process StudioDisplayXdr -ErrorAction SilentlyContinue)
}

function Stop-TestProcesses {
    Get-ProcessSnapshot | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

function Wait-ForProcess {
    param([int]$ProcessId)

    $deadline = (Get-Date).AddSeconds(8)
    do {
        $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($process) {
            return $process
        }

        Start-Sleep -Milliseconds 150
    } while ((Get-Date) -lt $deadline)

    throw "StudioDisplayXdr process did not remain running."
}

function Test-WindowVisible {
    param([int]$ProcessId)

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if (-not $process -or $process.MainWindowHandle -eq 0) {
        return $false
    }

    [StudioXdrRuntimeTest.WindowProbe]::IsWindowVisible($process.MainWindowHandle)
}

function Wait-ForWindowVisibility {
    param(
        [int]$ProcessId,
        [bool]$Visible
    )

    $deadline = (Get-Date).AddSeconds(10)
    do {
        $actual = Test-WindowVisible -ProcessId $ProcessId
        if ($actual -eq $Visible) {
            return $true
        }

        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)

    return $false
}

function Wait-ForSingleProcess {
    param([int]$ExpectedProcessId)

    $deadline = (Get-Date).AddSeconds(10)
    do {
        $processes = Get-ProcessSnapshot
        if ($processes.Count -eq 1 -and $processes[0].Id -eq $ExpectedProcessId) {
            return $processes
        }

        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)

    Get-ProcessSnapshot
}

$app = Resolve-AppPath -Candidate $AppPath
$results = New-Object System.Collections.Generic.List[object]

Stop-TestProcesses

try {
    $first = Start-Process -FilePath $app -ArgumentList "--minimized" -PassThru
    $firstProcess = Wait-ForProcess -ProcessId $first.Id

    # Give WPF startup, device enumeration, and the named single-instance listener time to settle.
    Start-Sleep -Seconds 3

    $hiddenAtStartup = Wait-ForWindowVisibility -ProcessId $firstProcess.Id -Visible $false
    $firstProcess = Get-Process -Id $firstProcess.Id -ErrorAction Stop

    $results.Add([pscustomobject]@{
        Check = "--minimized starts hidden"
        OK = [bool]$hiddenAtStartup
        Detail = "Pid=$($firstProcess.Id), MainWindowHandle=$($firstProcess.MainWindowHandle)"
    })

    $second = Start-Process -FilePath $app -PassThru
    $processes = Wait-ForSingleProcess -ExpectedProcessId $firstProcess.Id
    $singleInstance = $processes.Count -eq 1 -and $processes[0].Id -eq $firstProcess.Id

    $results.Add([pscustomobject]@{
        Check = "Second launch reuses existing instance"
        OK = [bool]$singleInstance
        Detail = "Pids=$(@($processes | ForEach-Object Id) -join ',')"
    })

    $visibleAfterSecondLaunch = Wait-ForWindowVisibility -ProcessId $firstProcess.Id -Visible $true
    $existing = Get-Process -Id $firstProcess.Id -ErrorAction SilentlyContinue

    $results.Add([pscustomobject]@{
        Check = "Second launch shows control panel"
        OK = [bool]$visibleAfterSecondLaunch
        Detail = "MainWindowHandle=$($existing.MainWindowHandle)"
    })
}
finally {
    Stop-TestProcesses
}

$failed = @($results | Where-Object { -not $_.OK })

if (-not $Quiet) {
    $results | Format-Table Check, OK, Detail -AutoSize
}

if ($failed.Count -gt 0) {
    throw "Studio Display XDR app runtime smoke test failed."
}

if (-not $Quiet) {
    Write-Host "Studio Display XDR app runtime smoke test passed."
}
