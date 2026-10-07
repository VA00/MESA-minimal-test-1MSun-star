<#
.SYNOPSIS
  Builds and runs the unit tests of MESA modules (module/test) and compares the
  output with test_output (whitespace-insensitive, like "diff -b" in utils/test/ck).

.EXAMPLE
  .\test_mesa.ps1                     # all modules
  .\test_mesa.ps1 -Modules eos,kap -ShowDiff 20
#>
param(
    [string]$MesaDir = $env:MESA_DIR,
    [string[]]$Modules = @('const', 'utils', 'math', 'mtx', 'auto_diff', 'num', 'interp_1d', 'interp_2d',
                           'chem', 'colors', 'eos', 'kap', 'rates', 'neu', 'net', 'turb', 'ionization', 'atm'),
    [int]$ShowDiff = 6,
    [double]$RelTol = 1e-8,
    [int]$TimeoutSec = 900,
    [switch]$CompareOnly   # only compare existing test/tmp_win.txt with test_output
)
$ErrorActionPreference = 'Stop'
if (-not $MesaDir) { throw 'MESA_DIR is not set (dot-source mesa_env.ps1)' }

function Normalize([string[]]$lines) {
    # drop cache messages (they appear only when a cache file is created) and blank lines
    $lines | Where-Object { $_ -notmatch '^\s*(write|read|create rate data for)\s|number not already in cache' } |
        ForEach-Object { ($_ -replace '\s+', ' ').Trim() } | Where-Object { $_ -ne '' }
}

$numRe = [regex]'^[+-]?(\d+\.?\d*|\.\d+)([EeDd]?[+-]?\d+)?$'
function To-Number([string]$t) {
    if (-not $numRe.IsMatch($t)) { return $null }
    $s = $t -replace '[Dd]', 'E'
    if ($s -match '^([+-]?[\d.]+)([+-]\d{3})$') { $s = "$($Matches[1])E$($Matches[2])" }   # 1.23-283
    $v = 0.0
    if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $v }
    return $null
}
# returns the largest relative difference between two lines (or +Inf if they do not match structurally)
function Get-LineDiff([string]$a, [string]$b) {
    if ($a -eq $b) { return 0.0 }
    $ta = $a -split ' '; $tb = $b -split ' '
    if ($ta.Count -ne $tb.Count) { return [double]::PositiveInfinity }
    $worst = 0.0
    for ($k = 0; $k -lt $ta.Count; $k++) {
        if ($ta[$k] -eq $tb[$k]) { continue }
        $x = To-Number $ta[$k]; $y = To-Number $tb[$k]
        if ($null -eq $x -or $null -eq $y) { return [double]::PositiveInfinity }
        $den = [Math]::Max([Math]::Max([Math]::Abs($x), [Math]::Abs($y)), 1e-250)
        $r = [Math]::Abs($x - $y) / $den
        if ($r -gt $worst) { $worst = $r }
    }
    return $worst
}

$summary = foreach ($m in $Modules) {
    $t = "$MesaDir/$m/test"
    if (-not (Test-Path "$t/make")) { [pscustomobject]@{ Module = $m; Result = 'no test' }; continue }
    Write-Host "=== $m" -ForegroundColor Cyan
    if (-not $CompareOnly) {
        & mingw32-make -C "$t/make" 2>&1 | Out-File "$t/build_win.log"
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path "$t/tester.exe")) {
            Get-Content "$t/build_win.log" -Tail 15
            [pscustomobject]@{ Module = $m; Result = 'BUILD FAILED' }; continue
        }
    }
    Push-Location $t
    try {
        if (-not $CompareOnly) {
            $p = Start-Process -FilePath .\tester.exe -NoNewWindow -PassThru -RedirectStandardOutput tmp_win.txt -RedirectStandardError tmp_win_err.txt
            $finished = $p.WaitForExit($TimeoutSec * 1000)
            if (-not $finished) { $p.Kill() }
        }
        if (-not $CompareOnly -and -not $finished) { $res = 'TIMEOUT' }
        elseif (-not $CompareOnly -and $p.ExitCode -ne 0) { $res = "RUN FAILED (exit $($p.ExitCode))"; Get-Content tmp_win_err.txt -Tail 10 }
        else {
            $got = @(Normalize (Get-Content tmp_win.txt))
            $ref = @('test_output', 'test_output.INTRINSIC', 'test_output.CRMATH') | Where-Object { Test-Path $_ } | Select-Object -First 1
            $exp = @(Normalize (Get-Content $ref))
            if ($exp.Count -ne $got.Count) {
                $res = "DIFF (line count $($got.Count) vs $($exp.Count) expected)"
            } else {
                $maxRel = 0.0; $bad = 0; $shown = 0
                for ($i = 0; $i -lt $exp.Count; $i++) {
                    $r = Get-LineDiff $exp[$i] $got[$i]
                    if ($r -gt $maxRel) { $maxRel = $r }
                    if ($r -gt $RelTol) {
                        $bad++
                        if ($shown -lt $ShowDiff) { Write-Host "  exp: $($exp[$i])"; Write-Host "  got: $($got[$i])" -ForegroundColor Yellow; $shown++ }
                    }
                }
                $res = if ($bad -eq 0) { 'OK (max rel. diff {0:E1})' -f $maxRel } else { "DIFF ($bad lines > $RelTol; max rel. diff {0:E1})" -f $maxRel }
            }
        }
    } catch { $res = "ERROR: $_" } finally { Pop-Location }
    [pscustomobject]@{ Module = $m; Result = $res }
}
$summary | Format-Table -AutoSize
