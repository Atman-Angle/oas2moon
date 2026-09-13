<#
.SYNOPSIS
  Run the complete oas2moon feasibility spike in one command.

.DESCRIPTION
  Executes the whole chain and prints a PASS/FAIL summary:

    OpenAPI fixture -> frontend adapter -> normalized Client IR -> generator
    -> generated MoonBit package -> moon fmt/check/test -> real local HTTP
    server -> GET/POST/DELETE -> typed decode -> deterministic regeneration

  Also runs the unsupported-feature negative path, which must fail with a
  stable diagnostic and write no output tree.

.EXAMPLE
  pwsh -File spike/run_spike.ps1
#>

[CmdletBinding()]
param(
  [string]$WorkRoot = 'spike/build',
  [int]$Port = 18080,
  [string]$Token = 'spike-token'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$rootFull = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $WorkRoot))
New-Item -ItemType Directory -Force -Path $rootFull | Out-Null

$script:results = [System.Collections.Generic.List[object]]::new()

function Record([string]$name, [int]$code, [string]$detail) {
  $script:results.Add([pscustomobject]@{ Step = $name; Exit = $code; Detail = $detail })
  $colour = if ($code -eq 0) { 'Green' } else { 'Red' }
  Write-Host ("[{0}] {1} -> exit {2} {3}" -f $(if ($code -eq 0) { 'PASS' } else { 'FAIL' }), $name, $code, $detail) -ForegroundColor $colour
}

function Reset-Tree([string]$name) {
  $path = [System.IO.Path]::GetFullPath((Join-Path $rootFull $name))
  if (-not $path.StartsWith($rootFull)) { throw "refusing to touch outside $rootFull`: $path" }
  if ([System.IO.Directory]::Exists($path)) { [System.IO.Directory]::Delete($path, $true) }
  return $path
}

$fixtureJson = Join-Path $repoRoot 'fixtures/petstore/openapi.json'
$fixtureYaml = Join-Path $repoRoot 'fixtures/petstore/openapi.yaml'
$fixtureOneOf = Join-Path $repoRoot 'fixtures/unsupported/oneof.json'
$normalized = Join-Path $rootFull 'normalized.json'
$normalizedYaml = Join-Path $rootFull 'normalized_yaml.json'
$normalizedOneOf = Join-Path $rootFull 'normalized_oneof.json'
$frontend = Join-Path $repoRoot 'spike/frontend'
$generate = Join-Path $repoRoot 'spike/generator/generate.py'

function Invoke-Frontend([string]$spec, [string]$out) {
  Push-Location -LiteralPath $frontend
  try {
    & moon run . --target native -- $spec $out | Out-Null
    return $LASTEXITCODE
  }
  finally { Pop-Location }
}

# ---------------------------------------------------------------- frontend
$code = Invoke-Frontend $fixtureJson $normalized
$normalizedBytes = if (Test-Path -LiteralPath $normalized) { (Get-Item -LiteralPath $normalized).Length } else { 0 }
Record 'frontend: petstore JSON -> Client IR' $code "$normalizedBytes bytes"

$code = Invoke-Frontend $fixtureYaml $normalizedYaml
$jsonText = Get-Content -LiteralPath $normalized -Raw
$yamlText = Get-Content -LiteralPath $normalizedYaml -Raw
$sameIir = $jsonText -eq $yamlText
Record 'frontend: petstore YAML -> identical Client IR' $(if ($sameIir) { 0 } else { 1 }) "byte-identical=$sameIir"

# ----------------------------------------------------------------- codegen
$gen1 = Reset-Tree 'gen1'
$gen1Report = Join-Path $rootFull 'gen1-report.json'
& python $generate --input $normalized --out $gen1 --module 'oas2moon_spike/petstore' --report $gen1Report | Out-Null
Record 'generator: emit SDK' $LASTEXITCODE "$((Get-ChildItem -LiteralPath $gen1 -Recurse -File).Count) files"

# ------------------------------------------------------------- compile gate
Push-Location -LiteralPath $gen1
try {
  $fmt = moon fmt --check 2>&1
  Record 'generated: moon fmt --check' $LASTEXITCODE ''
  $check = moon check --target native --deny-warn 2>&1
  Record 'generated: moon check --target native --deny-warn' $LASTEXITCODE ''
  $test = moon test --target native --deny-warn 2>&1
  $testCode = $LASTEXITCODE
  $totals = ($test | Select-String -Pattern 'Total tests:.*' | Select-Object -Last 1).Line
  Record 'generated: moon test --target native --deny-warn' $testCode "$totals"
}
finally { Pop-Location }

# ------------------------------------------------------------- determinism
& pwsh -NoProfile -File (Join-Path $repoRoot 'spike/verify_determinism.ps1') -WorkRoot $WorkRoot
Record 'determinism: two runs byte-identical' $LASTEXITCODE ''

# ------------------------------------------------------------- integration
$genInt = Reset-Tree 'gen1-int'
& python $generate --input $normalized --out $genInt --module 'oas2moon_spike/petstore' --report (Join-Path $rootFull 'gen1-int-report.json') | Out-Null
$integrationOut = Join-Path $rootFull 'gen1-integration'
& pwsh -NoProfile -File (Join-Path $repoRoot 'spike/run_integration.ps1') -ModuleDir $genInt -OutDir $integrationOut -Port $Port -Token $Token | Out-Host
$integrationCode = $LASTEXITCODE
$snapshot = Get-Content -LiteralPath (Join-Path $integrationOut 'capture.json') -Raw | ConvertFrom-Json
Record 'integration: real local HTTP GET/POST/DELETE' $integrationCode "$($snapshot.requests.Count) requests, $($snapshot.checks.Count) checks, $($snapshot.errors.Count) errors"

# ------------------------------------------------------------ negative path
$code = Invoke-Frontend $fixtureOneOf $normalizedOneOf
$oneOfReport = Join-Path $rootFull 'oneof-report.json'
$oneOfOut = Join-Path $rootFull 'oneof_out'
if ([System.IO.Directory]::Exists($oneOfOut)) { [System.IO.Directory]::Delete($oneOfOut, $true) }
$errors = & python $generate --input $normalizedOneOf --out $oneOfOut --module 'oas2moon_spike/oneof' --report $oneOfReport 2>&1
$oneOfCode = $LASTEXITCODE
$wroteOutput = [System.IO.Directory]::Exists($oneOfOut)
Record 'negative: unsupported oneOf is rejected' $(if ($oneOfCode -eq 1 -and -not $wroteOutput) { 0 } else { 1 }) "exit=$oneOfCode wroteOutput=$wroteOutput"

Write-Host ''
Write-Host '================ spike summary ================'
$script:results | Format-Table -AutoSize | Out-String | Write-Host
$failed = @($script:results | Where-Object { $_.Exit -ne 0 })
if ($failed.Count -gt 0) {
  Write-Host "== SPIKE FAILED: $($failed.Count) step(s)" -ForegroundColor Red
  exit 1
}
Write-Host '== SPIKE OK: every step passed' -ForegroundColor Green
exit 0
