<#
.SYNOPSIS
  Prove two generator runs over one input are byte-identical.

.DESCRIPTION
  Generates the same normalized Client IR twice into two fresh trees, runs the
  real toolchain formatter in both, then compares file lists, per-file SHA-256
  digests and the aggregate digest reported by the generator. Also compares the
  two `--report` files byte for byte.

  Generated trees are wiped first so a stale file can never masquerade as
  deterministic output.

.EXAMPLE
  pwsh -File spike/verify_determinism.ps1
#>

[CmdletBinding()]
param(
  [string]$NormalizedInput = 'spike/build/normalized.json',
  [string]$WorkRoot = 'spike/build',
  [string]$Module = 'oas2moon_spike/petstore',
  [string]$Left = 'gen1',
  [string]$Right = 'gen2'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$rootFull = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $WorkRoot))

function Reset-Tree([string]$name) {
  $path = [System.IO.Path]::GetFullPath((Join-Path $rootFull $name))
  if (-not $path.StartsWith($rootFull)) { throw "refusing to touch outside $rootFull`: $path" }
  if ([System.IO.Directory]::Exists($path)) { [System.IO.Directory]::Delete($path, $true) }
  return $path
}

$ignored = '\\(_build|smoke|\.mooncakes|target)\\'

function Get-TreeDigest([string]$path) {
  $prefix = $path.Length + 1
  $map = [ordered]@{}
  Get-ChildItem -Path $path -Recurse -File |
    Where-Object { $_.FullName -notmatch $ignored } |
    ForEach-Object {
      $relative = $_.FullName.Substring($prefix).Replace('\', '/')
      $map[$relative] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
  return $map
}

function Compare-Map($left, $right, [string]$label) {
  $problems = @()
  $leftKeys = @($left.Keys) | Sort-Object
  $rightKeys = @($right.Keys) | Sort-Object
  if (Compare-Object $leftKeys $rightKeys) {
    $problems += "file list differs between $label"
  }
  foreach ($key in $left.Keys) {
    if (-not $right.Contains($key)) { $problems += "missing on the right: $key"; continue }
    if ($left[$key] -ne $right[$key]) { $problems += "content differs: $key" }
  }
  return $problems
}

$leftPath = Reset-Tree $Left
$rightPath = Reset-Tree $Right
$leftReport = Join-Path $rootFull "$Left-report.json"
$rightReport = Join-Path $rootFull "$Right-report.json"
foreach ($report in @($leftReport, $rightReport)) {
  if (Test-Path -LiteralPath $report) { [System.IO.File]::Delete($report) }
}

$generate = Join-Path $repoRoot 'spike/generator/generate.py'
$normalized = Join-Path $repoRoot $NormalizedInput

foreach ($pair in @(@($Left, $leftPath, $leftReport), @($Right, $rightPath, $rightReport))) {
  Write-Host "== generating $($pair[0])"
  & python $generate --input $normalized --out $pair[1] --module $Module --report $pair[2] | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "generator failed for $($pair[0])" }
}

Write-Host '== running `moon fmt` in both trees'
foreach ($path in @($leftPath, $rightPath)) {
  Push-Location -LiteralPath $path
  try {
    & moon fmt | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "moon fmt failed in $path" }
  }
  finally { Pop-Location }
}

$leftDigest = Get-TreeDigest $leftPath
$rightDigest = Get-TreeDigest $rightPath
$problems = Compare-Map $leftDigest $rightDigest 'the two generated trees'

$leftReportBytes = [System.IO.File]::ReadAllBytes($leftReport)
$rightReportBytes = [System.IO.File]::ReadAllBytes($rightReport)
$reportsMatch = [System.Linq.Enumerable]::SequenceEqual([byte[]]$leftReportBytes, [byte[]]$rightReportBytes)
if (-not $reportsMatch) { $problems += 'the two --report files differ' }

Write-Host ''
Write-Host "file count: $($leftDigest.Count)"
foreach ($key in ($leftDigest.Keys | Sort-Object)) {
  Write-Host ("  {0}  {1}" -f $leftDigest[$key], $key)
}
$leftAggregate = (Get-Content -LiteralPath $leftReport -Raw | ConvertFrom-Json).aggregate_sha256
Write-Host "aggregate_sha256: $leftAggregate"
Write-Host "reports byte-identical: $reportsMatch"

if ($problems.Count -gt 0) {
  Write-Host '== NOT DETERMINISTIC' -ForegroundColor Red
  $problems | ForEach-Object { Write-Host "  - $_" }
  exit 1
}
Write-Host '== DETERMINISM OK: two runs are byte-identical' -ForegroundColor Green
exit 0
