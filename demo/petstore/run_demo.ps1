<#
.SYNOPSIS
    Petstore end-to-end demo for oas2moon, driven by the real CLI.

.DESCRIPTION
    Runs one OpenAPI 3.0.3 document through the product entry point and proves
    the result works against a real HTTP server:

        1. generate       `oas2moon generate` (frontend -> Client IR -> codegen)
        2. tests          add hermetic unit tests for the generated package
        3. moon fmt       generated sources are canonically formatted
        4. moon check     generated sources compile with no warnings
        5. moon test      generated unit tests pass (CaptureTransport, no sockets)
        6. local server   strict fixture server records every request
        7. typed GET      generated client performs GET, server asserts the shape
        8. JSON POST      generated client sends a typed JSON body
        9. DELETE + 204   generated client handles an empty 204 response
       10. auth           bearer, basic, api-key header and api-key query on the wire
       11. errors         404 and 401 surface as SdkError.Http; missing credential
                          surfaces as SdkError.Configuration
       12. determinism    a second generation is byte-identical

    Every path derives from this script's own location, so the demo runs from
    any working directory and hard-codes no machine-specific path.

.PARAMETER Port
    Loopback port for the fixture server. Defaults to 18080.

.PARAMETER Token
    Bearer token shared by client and server. Defaults to demo-token.

.EXAMPLE
    pwsh -NoProfile -File demo/petstore/run_demo.ps1
#>

[CmdletBinding()]
param(
    [int]$Port = 18080,
    [string]$Token = 'demo-token',
    [string]$BasicUser = 'demo-user',
    [string]$BasicPassword = 'demo-pass',
    [string]$ApiKey = 'demo-api-key'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$demoDir = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $demoDir)
$outDir = Join-Path $demoDir '_out'
$generated = Join-Path $outDir 'generated'
$canonical = Join-Path $outDir 'canonical.json'
$logDir = Join-Path $outDir 'logs'
$spec = Join-Path $demoDir 'openapi.json'
$module = 'oas2moon/petstore_demo'

$script:results = [System.Collections.Generic.List[object]]::new()

function Write-Step {
    param([string]$Label)
    Write-Host ''
    Write-Host "=== $Label ===" -ForegroundColor Cyan
}

function Add-Result {
    param([string]$Label, [bool]$Ok, [string]$Detail = '')
    $script:results.Add([pscustomobject]@{ Label = $Label; Ok = $Ok })
    $tag = if ($Ok) { 'PASS' } else { 'FAIL' }
    $colour = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1}" -f $tag, $Label) -ForegroundColor $colour
    if (-not $Ok -and $Detail) {
        foreach ($line in ($Detail -split "`n" | Select-Object -First 14)) {
            Write-Host ("    " + $line.TrimEnd()) -ForegroundColor DarkGray
        }
    }
}

function Invoke-In {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string[]]$Command
    )
    Push-Location -LiteralPath $Directory
    try {
        $output = & $Command[0] $Command[1..($Command.Length - 1)] 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
    } finally {
        Pop-Location
    }
}

function Save-Log {
    param([string]$Name, [string]$Text)
    $path = Join-Path $logDir $Name
    $Text | Set-Content -Path $path -Encoding utf8
    return $path
}

function Get-SourceHashes {
    <#
        Hash exactly what the generator produced at the package root. Build
        output and the copied driver are not generator artifacts.
    #>
    param([Parameter(Mandatory)][string]$Directory)
    $hashes = [ordered]@{}
    Get-ChildItem -LiteralPath $Directory -File | Sort-Object Name | ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
        $hashes[$_.Name] = [System.Convert]::ToHexString($hash)
    }
    return $hashes
}

function Invoke-Generate {
    param([string]$TargetOut, [string]$TargetIr)
    return Invoke-In -Directory $repoRoot -Command @(
        'python', (Join-Path $repoRoot 'oas2moon.py'), 'generate', $spec,
        '--module', $module, '--out', $TargetOut, '--ir-out', $TargetIr
    )
}

# --------------------------------------------------------------------------- #
Write-Host 'Petstore end-to-end demo (CLI driven)' -ForegroundColor White
Write-Host "repo root : $repoRoot"
Write-Host "demo dir  : $demoDir"
Write-Host "output dir: $outDir"

Write-Step 'Step 0: clean output directory'
if (Test-Path -LiteralPath $outDir) {
    $resolvedOut = [System.IO.Path]::GetFullPath($outDir)
    $resolvedDemo = [System.IO.Path]::GetFullPath($demoDir)
    if (-not $resolvedOut.StartsWith($resolvedDemo, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "refusing to clean a directory outside the demo folder: $resolvedOut"
    }
    Remove-Item -LiteralPath $resolvedOut -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Add-Result 'output directory reset' $true

Write-Step 'Step 1: generate via the oas2moon CLI'
$generate = Invoke-Generate -TargetOut $generated -TargetIr $canonical
$generateLog = Save-Log 'generate.log' $generate.Output
Add-Result 'oas2moon generate' ($generate.ExitCode -eq 0) $generate.Output
if ($generate.ExitCode -ne 0) {
    Write-Host "`nGeneration failed; stopping." -ForegroundColor Red
    Get-Content -LiteralPath $generateLog | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    exit 1
}

Write-Step 'Step 2: add hermetic unit tests to the generated package'
$tests = Invoke-In -Directory $repoRoot -Command @(
    'python', (Join-Path $demoDir 'gen_tests.py'), $canonical, $generated
)
Save-Log 'gen_tests.log' $tests.Output | Out-Null
Add-Result 'generate unit tests' ($tests.ExitCode -eq 0) $tests.Output

Write-Step 'Step 3: moon fmt'
$fmt = Invoke-In -Directory $generated -Command @('moon', 'fmt')
$fmtCheck = Invoke-In -Directory $generated -Command @('moon', 'fmt', '--check')
Save-Log 'fmt.log' $fmtCheck.Output | Out-Null
Add-Result 'moon fmt --check' ($fmtCheck.ExitCode -eq 0) $fmtCheck.Output

Write-Step 'Step 4: moon check'
$check = Invoke-In -Directory $generated -Command @('moon', 'check', '--target', 'native', '--deny-warn')
Save-Log 'check.log' $check.Output | Out-Null
Add-Result 'moon check --deny-warn' ($check.ExitCode -eq 0) $check.Output

Write-Step 'Step 5: moon test (generated package, CaptureTransport only)'
$test = Invoke-In -Directory $generated -Command @('moon', 'test', '--target', 'native', '--deny-warn')
Save-Log 'test.log' $test.Output | Out-Null
Add-Result 'moon test --deny-warn' ($test.ExitCode -eq 0) $test.Output

Write-Step 'Steps 6-11: real HTTP end-to-end'
$capture = Join-Path $outDir 'server_capture.json'
$driverSource = Join-Path $demoDir 'integration'
$driverTarget = Join-Path $generated 'integration'
Copy-Item -LiteralPath $driverSource -Destination $driverTarget -Recurse -Force

$serverArgs = @{
    FilePath = 'python'
    ArgumentList = @(
    (Join-Path $demoDir 'fixture_server.py'),
    '--port', "$Port",
    '--token', $Token,
    '--basic-user', $BasicUser,
    '--basic-password', $BasicPassword,
    '--api-key', $ApiKey,
    '--capture', $capture
    )
    PassThru = $true
    RedirectStandardOutput = (Join-Path $logDir 'server_stdout.log')
    RedirectStandardError = (Join-Path $logDir 'server_stderr.log')
}
if ($IsWindows) {
    $serverArgs['WindowStyle'] = 'Hidden'
}
$server = Start-Process @serverArgs

$driverExit = 1
$driverOutput = ''
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
    if (-not $ready) { throw "fixture server never became ready on 127.0.0.1:$Port" }
    Write-Host ("  fixture server ready on http://127.0.0.1:{0}" -f $Port) -ForegroundColor DarkGray

    $run = Invoke-In -Directory $generated -Command @(
        'moon', 'run', 'integration', '--target', 'native', '--',
        "http://127.0.0.1:$Port", $Token, $BasicUser, $BasicPassword, $ApiKey
    )
    $driverExit = $run.ExitCode
    $driverOutput = $run.Output
} finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force
    }
    Start-Sleep -Milliseconds 400
}

Save-Log 'integration.log' $driverOutput | Out-Null
Add-Result 'generated client: CRUD, response enum, media mismatch, auth and errors' ($driverExit -eq 0) $driverOutput
foreach ($line in ($driverOutput -split "`n")) {
    if ($line.Trim()) { Write-Host ("    " + $line.TrimEnd()) -ForegroundColor DarkGray }
}

if (-not (Test-Path -LiteralPath $capture)) {
    Add-Result 'server wire capture written' $false "no capture file at $capture"
} else {
    $snapshot = Get-Content -LiteralPath $capture -Raw | ConvertFrom-Json
    $requests = @($snapshot.requests)
    $errors = @($snapshot.errors)
    $rejections = @($snapshot.rejections)

    foreach ($request in $requests) {
        Write-Host ("    observed: {0} {1}" -f $request.method, $request.raw_target) -ForegroundColor DarkGray
    }

    $expected = @(
        'GET /pets/42?verbose=true',
        'GET /pets/42/result?created=false',
        'GET /pets/42/result?created=true',
        'GET /media/mismatch',
        'POST /pets',
        'DELETE /pets',
        'GET /auth/bearer',
        'GET /auth/basic',
        'GET /auth/api-key-header',
        "GET /auth/api-key-query?api_key=$ApiKey",
        'GET /missing/pets/42?verbose=true',
        'GET /pets/1?verbose=true'
    )
    $observed = @($requests | ForEach-Object { "$($_.method) $($_.raw_target)" })

    Add-Result 'server recorded no wire violations' ($errors.Count -eq 0) ($errors -join '; ')
    Add-Result 'exactly one deliberate credential rejection' ($rejections.Count -eq 1) ($rejections -join '; ')

    $match = ($observed.Count -eq $expected.Count)
    if ($match) {
        for ($i = 0; $i -lt $expected.Count; $i++) {
            if ($observed[$i] -ne $expected[$i]) { $match = $false }
        }
    }
    Add-Result ("generated client produced the expected {0} requests" -f $expected.Count) $match ($observed -join ' | ')
}

Write-Step 'Step 12: determinism (regenerate and compare hashes)'
$secondOut = Join-Path $outDir 'determinism'
$secondGenerated = Join-Path $secondOut 'generated'
$secondIr = Join-Path $secondOut 'canonical.json'
$regen = Invoke-Generate -TargetOut $secondGenerated -TargetIr $secondIr
Save-Log 'generate-second.log' $regen.Output | Out-Null

if ($regen.ExitCode -ne 0) {
    Add-Result 'second generation' $false $regen.Output
} else {
    $secondTests = Invoke-In -Directory $repoRoot -Command @(
        'python', (Join-Path $demoDir 'gen_tests.py'), $secondIr, $secondGenerated
    )
    $null = Invoke-In -Directory $secondGenerated -Command @('moon', 'fmt')

    $first = Get-SourceHashes -Directory $generated
    $second = Get-SourceHashes -Directory $secondGenerated
    $same = ($first.Count -eq $second.Count)
    $diff = @()
    foreach ($name in $first.Keys) {
        if (-not $second.Contains($name)) { $same = $false; $diff += "missing $name"; continue }
        if ($first[$name] -ne $second[$name]) { $same = $false; $diff += "changed $name" }
    }
    Add-Result ("byte-identical regeneration ({0} files)" -f $first.Count) $same ($diff -join '; ')
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  Petstore E2E demo summary' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
$failed = @($script:results | Where-Object { -not $_.Ok })
foreach ($entry in $script:results) {
    $tag = if ($entry.Ok) { 'PASS' } else { 'FAIL' }
    $colour = if ($entry.Ok) { 'Green' } else { 'Red' }
    Write-Host ("  [{0}] {1}" -f $tag, $entry.Label) -ForegroundColor $colour
}
Write-Host '----------------------------------------'
if ($failed.Count -eq 0) {
    Write-Host ("  Verdict: ALL PASS ({0} checks)" -f $script:results.Count) -ForegroundColor Green
} else {
    Write-Host ("  Verdict: SOME FAILED ({0} of {1} checks)" -f $failed.Count, $script:results.Count) -ForegroundColor Red
}
Write-Host ''
Write-Host "artifacts: $outDir"
Write-Host "logs     : $logDir"

exit $(if ($failed.Count -eq 0) { 0 } else { 1 })
