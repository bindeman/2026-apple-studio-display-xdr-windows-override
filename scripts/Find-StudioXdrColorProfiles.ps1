param(
    [string[]]$SearchRoot = @(),
    [switch]$IncludeUserFolders,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    Split-Path -Parent $PSScriptRoot
}

function Read-UInt32BE {
    param(
        [byte[]]$Bytes,
        [int]$Offset
    )

    if ($Bytes.Length -lt $Offset + 4) {
        return 0
    }

    ([uint32]$Bytes[$Offset] -shl 24) -bor
        ([uint32]$Bytes[$Offset + 1] -shl 16) -bor
        ([uint32]$Bytes[$Offset + 2] -shl 8) -bor
        [uint32]$Bytes[$Offset + 3]
}

function Read-Ascii {
    param(
        [byte[]]$Bytes,
        [int]$Offset,
        [int]$Length
    )

    if ($Bytes.Length -lt $Offset + $Length) {
        return ""
    }

    [System.Text.Encoding]::ASCII.GetString($Bytes, $Offset, $Length).Trim([char]0)
}

function Read-ProfileDescription {
    param([string]$Path)

    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -lt 132 -or (Read-Ascii -Bytes $bytes -Offset 36 -Length 4) -ne "acsp") {
            return ""
        }

        $tagCount = [int](Read-UInt32BE -Bytes $bytes -Offset 128)
        for ($i = 0; $i -lt $tagCount; $i++) {
            $entry = 132 + ($i * 12)
            if ($bytes.Length -lt $entry + 12) {
                break
            }

            $signature = Read-Ascii -Bytes $bytes -Offset $entry -Length 4
            if ($signature -notin @("desc", "dmnd", "dmdd", "cprt")) {
                continue
            }

            $offset = [int](Read-UInt32BE -Bytes $bytes -Offset ($entry + 4))
            $size = [int](Read-UInt32BE -Bytes $bytes -Offset ($entry + 8))
            if ($offset -lt 0 -or $size -le 12 -or $bytes.Length -lt $offset + $size) {
                continue
            }

            $tagType = Read-Ascii -Bytes $bytes -Offset $offset -Length 4
            if ($tagType -eq "desc") {
                $length = [int](Read-UInt32BE -Bytes $bytes -Offset ($offset + 8))
                if ($length -gt 1 -and $bytes.Length -ge $offset + 12 + $length) {
                    return (Read-Ascii -Bytes $bytes -Offset ($offset + 12) -Length ($length - 1))
                }
            }
            elseif ($tagType -eq "mluc") {
                $recordCount = [int](Read-UInt32BE -Bytes $bytes -Offset ($offset + 8))
                $recordSize = [int](Read-UInt32BE -Bytes $bytes -Offset ($offset + 12))
                if ($recordCount -gt 0 -and $recordSize -ge 12) {
                    $record = $offset + 16
                    $length = [int](Read-UInt32BE -Bytes $bytes -Offset ($record + 4))
                    $textOffset = [int](Read-UInt32BE -Bytes $bytes -Offset ($record + 8))
                    $absoluteTextOffset = $offset + $textOffset
                    if ($length -gt 1 -and $bytes.Length -ge $absoluteTextOffset + $length) {
                        return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, $absoluteTextOffset, $length).Trim([char]0)
                    }
                }
            }
        }

        return ""
    }
    catch {
        return ""
    }
}

function Get-IccHeader {
    param([string]$Path)

    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            if ($stream.Length -lt 128) {
                return $null
            }

            $header = New-Object byte[] 128
            $read = $stream.Read($header, 0, 128)
            if ($read -lt 128 -or (Read-Ascii -Bytes $header -Offset 36 -Length 4) -ne "acsp") {
                return $null
            }

            [pscustomobject]@{
                Size = Read-UInt32BE -Bytes $header -Offset 0
                PreferredCmm = Read-Ascii -Bytes $header -Offset 4 -Length 4
                Version = ("{0}.{1}.{2}" -f ($header[8] -shr 4), ($header[8] -band 0x0F), $header[9])
                DeviceClass = Read-Ascii -Bytes $header -Offset 12 -Length 4
                ColorSpace = Read-Ascii -Bytes $header -Offset 16 -Length 4
                Pcs = Read-Ascii -Bytes $header -Offset 20 -Length 4
                Manufacturer = Read-Ascii -Bytes $header -Offset 48 -Length 4
                Model = Read-Ascii -Bytes $header -Offset 52 -Length 4
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        return $null
    }
}

function Add-SearchRoot {
    param(
        [System.Collections.Generic.List[string]]$Roots,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return
    }

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (-not ($Roots | Where-Object { $_.Equals($resolved, [System.StringComparison]::OrdinalIgnoreCase) })) {
        $Roots.Add($resolved)
    }
}

$repoRoot = Get-RepoRoot
$roots = [System.Collections.Generic.List[string]]::new()
Add-SearchRoot -Roots $roots -Path (Join-Path $repoRoot "profiles")
Add-SearchRoot -Roots $roots -Path (Join-Path $env:WINDIR "System32\spool\drivers\color")

if ($env:ProgramFiles) {
    Add-SearchRoot -Roots $roots -Path (Join-Path $env:ProgramFiles "Common Files\Apple")
    Add-SearchRoot -Roots $roots -Path (Join-Path $env:ProgramFiles "Apple")
}

if (${env:ProgramFiles(x86)}) {
    Add-SearchRoot -Roots $roots -Path (Join-Path ${env:ProgramFiles(x86)} "Common Files\Apple")
    Add-SearchRoot -Roots $roots -Path (Join-Path ${env:ProgramFiles(x86)} "Apple")
}

if ($IncludeUserFolders) {
    Add-SearchRoot -Roots $roots -Path (Join-Path $env:USERPROFILE "Downloads")
    Add-SearchRoot -Roots $roots -Path (Join-Path $env:USERPROFILE "Documents\Dev")
}

foreach ($root in $SearchRoot) {
    Add-SearchRoot -Roots $roots -Path $root
}

if (-not $Json) {
    Write-Host "Studio Display XDR color-profile discovery"
    Write-Host "Search roots:"
    $roots | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
}

$files = foreach ($root in $roots) {
    Get-ChildItem -LiteralPath $root -File -Recurse -Include *.icc,*.icm -ErrorAction SilentlyContinue
}

$profiles = foreach ($file in ($files | Sort-Object FullName -Unique)) {
    $header = Get-IccHeader -Path $file.FullName
    if (-not $header) {
        continue
    }

    $description = Read-ProfileDescription -Path $file.FullName
    $haystack = "$($file.Name) $description"
    $relevance = @()
    if ($haystack -match "Apple") { $relevance += "Apple" }
    if ($haystack -match "Studio") { $relevance += "Studio" }
    if ($haystack -match "XDR") { $relevance += "XDR" }
    if ($haystack -match "Pro Display") { $relevance += "ProDisplay" }
    if ($haystack -match "P3|Display P3") { $relevance += "P3" }
    if ($haystack -match "Adobe") { $relevance += "Adobe" }
    if ($haystack -match "BT\.?2020|Rec\.?2020|HDR|ST.?2084") { $relevance += "HDR" }
    if ($haystack -match "Generated") { $relevance += "Generated" }
    if ($file.FullName.StartsWith((Join-Path $repoRoot "profiles"), [System.StringComparison]::OrdinalIgnoreCase)) { $relevance += "Bundled" }

    [pscustomobject]@{
        Name = $file.Name
        Description = $description
        Relevance = if ($relevance.Count -gt 0) { ($relevance | Select-Object -Unique) -join "," } else { "" }
        DeviceClass = $header.DeviceClass
        ColorSpace = $header.ColorSpace
        Pcs = $header.Pcs
        Manufacturer = $header.Manufacturer
        Model = $header.Model
        Length = $file.Length
        Path = $file.FullName
    }
}

if (-not $profiles) {
    if ($Json) {
        "[]"
        return
    }

    Write-Host "No valid ICC/ICM profiles were found in the searched roots."
    return
}

if ($Json) {
    ConvertTo-Json -InputObject @($profiles) -Depth 4
    return
}

$profiles |
    Sort-Object @{ Expression = { if ([string]::IsNullOrWhiteSpace($_.Relevance)) { 1 } else { 0 } } }, Name |
    Format-Table Name,Description,Relevance,DeviceClass,ColorSpace,Manufacturer,Model,Length,Path -AutoSize -Wrap

Write-Host ""
Write-Host "Notes:"
Write-Host "- A relevant Apple/Pro Display profile can be installed manually with Install-StudioXdrColorProfile.ps1 -ProfilePath <path>."
Write-Host "- Do not assume Pro Display XDR profiles are correct for Studio Display XDR without measurement."
Write-Host "- The bundled StudioDisplayXDR-DisplayP3.icm is generated, not Apple-authored."
