<#
.SYNOPSIS
    Generate, compile, and run the Amap weather SDK against the real API.
#>
[CmdletBinding()]
param(
    [string]$City = '110101'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($env:AMAP_KEY)) {
    throw 'Set $env:AMAP_KEY to your Amap Web Service Key before running this script.'
}

$exampleDir = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $exampleDir)
$outDir = Join-Path $repoRoot 'local/amap-weather-generated'
$spec = Join-Path $exampleDir 'openapi.json'

python (Join-Path $repoRoot 'oas2moon.py') generate $spec `
    --module oas2moon/amap_weather_example `
    --out $outDir
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$integrationOut = Join-Path $outDir 'integration'
if (Test-Path -LiteralPath $integrationOut) {
    Remove-Item -LiteralPath $integrationOut -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $exampleDir 'integration') `
    -Destination $outDir -Recurse -Force

Push-Location -LiteralPath $outDir
try {
    moon fmt
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    moon fmt --check
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    moon check --target native --deny-warn
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    moon run integration --target native -- $env:AMAP_KEY $City
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
