$ErrorActionPreference = "Stop"

$enableScript = Join-Path $PSScriptRoot "Enable-StudioXdrHdr.ps1"
$source = Get-Content -Raw -LiteralPath $enableScript
$source = $source -replace '\[StudioXdrHdr\]::Set\(\$true\)', '[StudioXdrHdr]::Set($false)'
Invoke-Expression $source
