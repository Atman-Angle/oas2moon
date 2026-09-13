<#
.SYNOPSIS
  Run one generated MoonBit SDK package against the spike fixture server.

.DESCRIPTION
  Starts tools/fixture_server.py on 127.0.0.1, runs the given MoonBit
  package with `moon run`, stops the server and prints both the client report
  and the server-side capture. Exits non-zero when the server recorded any
  wire-level mismatch.

.EXAMPLE
  pwsh -File spike/run_integration.ps1 -ModuleDir spike/prototype -OutDir spike/build/prototype
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ModuleDir,
  [Parameter(Mandatory = $true)][string]$OutDir,
  [string]$Package = 'smoke',
  [string]$SmokeSource = 'spike/generator/templates/smoke',
  [int]$Port = 18080,
  [string]$Token = 'spike-token'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = (Resolve-Path -LiteralPath $ModuleDir).Path
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$outPath = (Resolve-Path -LiteralPath $OutDir).Path

# A generated module contains only the SDK. The spike driver lives outside the
# generator so that the generated tree stays exactly what the generator emitted;
# it is copied in here when the package is absent.
$packagePath = Join-Path $modulePath $Package
if (-not (Test-Path -LiteralPath $packagePath)) {
  $smokePath = Join-Path $repoRoot $SmokeSource
  if (-not (Test-Path -LiteralPath $smokePath)) {
    throw "package '$Package' is missing from '$modulePath' and no driver template exists at '$smokePath'"
  }
  Write-Host "== copying spike driver '$Package' from $smokePath"
  New-Item -ItemType Directory -Force -Path $packagePath | Out-Null
  Copy-Item -Path (Join-Path $smokePath '*') -Destination $packagePath -Recurse -Force
}

$capture = Join-Path $outPath 'capture.json'
$clientReport = Join-Path $outPath 'client_report.json'
$serverOut = Join-Path $outPath 'server_stdout.log'
$serverErr = Join-Path $outPath 'server_stderr.log'
$serverScript = Join-Path $repoRoot 'tools/fixture_server.py'

foreach ($path in @($capture, $clientReport, $serverOut, $serverErr)) {
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Force
  }
}

$baseUrl = "http://127.0.0.1:$Port"
$serverArgs = @(
  $serverScript,
  '--port', "$Port",
  '--token', $Token,
  '--capture', $capture
)

Write-Host "== starting fixture server on $baseUrl"
$server = Start-Process -FilePath 'python' -ArgumentList $serverArgs `
  -PassThru -WindowStyle Hidden `
  -RedirectStandardOutput $serverOut -RedirectStandardError $serverErr

try {
  $deadline = (Get-Date).AddSeconds(20)
  $ready = $false
  while ((Get-Date) -lt $deadline) {
    try {
      $probe = [System.Net.Sockets.TcpClient]::new()
      $probe.Connect('127.0.0.1', $Port)
      $probe.Close()
      $ready = $true
      break
    } catch {
      Start-Sleep -Milliseconds 200
    }
  }
  if (-not $ready) {
    throw "fixture server did not become ready on port $Port"
  }
  Write-Host "== fixture server ready (pid=$($server.Id))"

  Write-Host "== running moon run $Package --target native"
  Push-Location -LiteralPath $modulePath
  try {
    $clientOutput = & moon run $Package --target native -- $baseUrl $Token 2>&1
    $clientExit = $LASTEXITCODE
  }
  finally {
    Pop-Location
  }
  $clientOutput | Tee-Object -FilePath $clientReport
  if ($clientExit -ne 0) {
    throw "generated client exited with code $clientExit"
  }
}
finally {
  if ($server -and -not $server.HasExited) {
    Stop-Process -Id $server.Id -Force
  }
  Start-Sleep -Milliseconds 300
}

Write-Host "== server capture"
if (-not (Test-Path -LiteralPath $capture)) {
  throw "fixture server wrote no capture file: $capture"
}
$snapshot = Get-Content -LiteralPath $capture -Raw | ConvertFrom-Json
$snapshot | ConvertTo-Json -Depth 12 | Write-Host

if ($snapshot.errors.Count -gt 0) {
  Write-Host "== INTEGRATION FAILED: server recorded wire-level mismatches" -ForegroundColor Red
  exit 1
}

Write-Host "== INTEGRATION OK: $($snapshot.requests.Count) requests, $($snapshot.checks.Count) checks" -ForegroundColor Green
exit 0
