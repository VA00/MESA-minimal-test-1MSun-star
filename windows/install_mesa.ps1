<#
.SYNOPSIS
  Native Windows (PowerShell 7) replacement of MESA's ./install script.

.DESCRIPTION
  Builds MESA with MinGW-w64 gfortran (MSYS2 UCRT64) and GNU make (mingw32-make),
  without WSL, Cygwin or bash. Steps:
    1. checks the toolchain,
    2. installs the Windows makefile_header and helper scripts into $MESA_DIR/utils,
    3. patches utils/private/utils_c_system.c for Windows (idempotent, #ifdef _WIN32),
    4. unpacks the input data (chem, colors, eos, kap, ionization, atm),
    5. builds and installs the MESA modules needed by mesa/star.

.EXAMPLE
  . C:\MESA\MESA-minimal-test-1MSun-star\windows\mesa_env.ps1
  C:\MESA\MESA-minimal-test-1MSun-star\windows\install_mesa.ps1

.EXAMPLE
  C:\MESA\MESA-minimal-test-1MSun-star\windows\install_mesa.ps1 -Modules star -Clean   # rebuild star only
#>
[CmdletBinding()]
param(
    [string]$MesaDir = $env:MESA_DIR,
    [string]$Toolchain = $(if ($env:MESA_WIN_TOOLCHAIN) { $env:MESA_WIN_TOOLCHAIN } else { 'C:/msys64/ucrt64' }),
    [int]$Jobs = [Environment]::ProcessorCount,
    [string[]]$Modules,
    [switch]$ForceData,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

# Modules in the order of mesa/install (gyre is built as a stub; adipls, astero, binary skipped)
$allModules = @('const', 'utils', 'math', 'mtx', 'auto_diff', 'forum', 'num', 'interp_1d', 'interp_2d',
                'chem', 'colors', 'eos', 'kap', 'rates', 'neu', 'net', 'star_data', 'turb',
                'ionization', 'atm', 'gyre', 'star')

function Write-Step([string]$msg) { Write-Host "`n=== $msg" -ForegroundColor Cyan }
function Fail([string]$msg) { Write-Host "`nFAILED: $msg" -ForegroundColor Red; exit 1 }

function Invoke-Native {
    param([string]$Exe, [string[]]$ArgList, [string]$What)
    & $Exe @ArgList
    if ($LASTEXITCODE -ne 0) { Fail "$What (exit code $LASTEXITCODE)" }
}

# make, without the harmless noise from bash-only commands in the MESA makefiles
# ($(shell ln -sf ...), $(shell touch -r ...), rm -f) that are replaced by this script
function Invoke-Make {
    param([string[]]$ArgList, [string]$What)
    & mingw32-make @ArgList 2>&1 | ForEach-Object { "$_" } |
        Where-Object { $_ -notmatch '^process_begin: CreateProcess\(NULL, (ln|touch|rm) |^makefile_base:\d+: pipe: |^make \(e=2\)|\[makefile_base:\d+: install\] Error 2 \(ignored\)' }
    if ($LASTEXITCODE -ne 0) { Fail "$What (exit code $LASTEXITCODE)" }
}

# ---------------------------------------------------------------- 1. environment
if (-not $MesaDir) { Fail 'MESA_DIR is not set (dot-source mesa_env.ps1 or use -MesaDir)' }
$MesaDir = (Resolve-Path $MesaDir).Path -replace '\\', '/'
if ($MesaDir -match '\s') { Fail "MESA_DIR can not contain whitespace: $MesaDir" }
$Toolchain = $Toolchain -replace '\\', '/'
$env:MESA_DIR = $MesaDir
$env:MESA_WIN_TOOLCHAIN = $Toolchain
$tcBin = ($Toolchain -replace '/', '\') + '\bin'
if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $tcBin })) { $env:PATH = "$tcBin;$env:PATH" }

Write-Step "MESA_DIR = $MesaDir"
foreach ($exe in 'gfortran', 'gcc', 'ar', 'mingw32-make', 'tar') {
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
        Fail "$exe not found. Install with: C:\msys64\usr\bin\pacman.exe -S mingw-w64-ucrt-x86_64-gcc-fortran mingw-w64-ucrt-x86_64-make mingw-w64-ucrt-x86_64-hdf5"
    }
}
if (-not (Test-Path "$Toolchain/include/hdf5.mod")) { Fail "HDF5 Fortran module not found in $Toolchain/include (pacman -S mingw-w64-ucrt-x86_64-hdf5)" }
& gfortran --version | Select-Object -First 1

# Python 3: "python" (python.org installer with PATH option) or the "py" launcher
# (default of winget/python.org); the Microsoft Store alias "python" is rejected.
$PyExe = $null; $PyArgs = @()
foreach ($cand in 'python', 'py -3') {
    $exe, $a = $cand -split ' '
    $a = @($a | Where-Object { $_ })
    if (Get-Command $exe -CommandType Application -ErrorAction SilentlyContinue) {
        & $exe @a -c 'import lzma, sys' 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $PyExe = $exe; $PyArgs = $a; break }
    }
}
if (-not $PyExe) { Fail 'Python 3 not found (winget install --id Python.Python.3.14 -e, then open a new PowerShell window)' }
Write-Host "Python: $((& $PyExe @PyArgs --version) 2>&1)"

# ---------------------------------------------------------------- 2. header and tools
Write-Step 'Installing Windows makefile_header and helper scripts'
$hdr = "$MesaDir/utils/makefile_header"
if (-not (Test-Path "$hdr.orig")) { Copy-Item $hdr "$hdr.orig" }
Copy-Item "$here/makefile_header" $hdr -Force
New-Item -ItemType Directory -Force "$MesaDir/utils/windows" | Out-Null
Copy-Item "$here/tools/*.ps1" "$MesaDir/utils/windows/" -Force
Copy-Item "$here/forum_makefile" "$MesaDir/utils/windows/" -Force
foreach ($d in 'lib', 'include') { New-Item -ItemType Directory -Force "$MesaDir/$d" | Out-Null }
Copy-Item "$here/tools/mesa_win_locale.c" "$MesaDir/utils/windows/" -Force
Invoke-Native gcc @('-O2', '-c', "$MesaDir/utils/windows/mesa_win_locale.c", '-o', "$MesaDir/lib/mesa_win_locale.o") 'gcc mesa_win_locale.c'

# fypp (Python preprocessor used by forum), installed privately into utils/windows/pylib
$pylib = "$MesaDir/utils/windows/pylib"
if (-not (Test-Path "$pylib/fypp.py")) {
    Write-Step 'Installing fypp (Python) into utils/windows/pylib'
    Invoke-Native $PyExe ($PyArgs + @('-m', 'pip', 'install', '--quiet', '--disable-pip-version-check', '--target', $pylib, 'fypp')) 'pip install fypp'
}

# ---------------------------------------------------------------- 3. patch C helpers
$cfile = "$MesaDir/utils/private/utils_c_system.c"
$c = Get-Content -Raw $cfile
if ($c -notmatch 'MESA_WINDOWS_PATCH') {
    Write-Step 'Patching utils/private/utils_c_system.c for Windows'
    $winBlock = @'
#include "utils_c_system.h"

/* MESA_WINDOWS_PATCH: POSIX compatibility for MinGW-w64 */
#ifdef _WIN32
#include <direct.h>
#include <io.h>
#define mkdir(path, mode) _mkdir(path)
#define realpath(name, resolved) _fullpath((resolved), (name), 4096)
#ifndef S_IRGRP
#define S_IRGRP 0
#endif
#ifndef S_IWGRP
#define S_IWGRP 0
#endif
#ifndef S_IROTH
#define S_IROTH 0
#endif
#else
#define O_BINARY 0
#endif
'@
    $c = $c.Replace('#include "utils_c_system.h"', $winBlock.TrimEnd())
    $c = $c.Replace('open(src, O_RDONLY)', 'open(src, O_RDONLY | O_BINARY)')
    $c = $c.Replace('O_CREAT | O_WRONLY | O_TRUNC,', 'O_CREAT | O_WRONLY | O_TRUNC | O_BINARY,')
    Set-Content -NoNewline -Path $cfile -Value $c
}

# Upstream fix (MESAHub/mesa commit 03ef2a5, Feb 2026, "mtx: fix undefined behaviour in `b` pivot
# swaps"): "!$omp simd" on the pivot-swap loops of my_getrs1* is undefined behaviour; gfortran >= 15
# then produces wrong solutions in star_bcyclic.f90 and net_burn_support.f90 (solver fails: "sizeB").
$incFile = "$MesaDir/mtx/public/mtx_solve_routines.inc"
$inc = Get-Content -Raw $incFile
$incFixed = [regex]::Replace($inc, '(?m)^[ \t]*!\$omp simd private\(temp\)\r?\n(?=[ \t]*do i = 1,n\r?\n[ \t]*temp = b\(i\))', '')
if ($incFixed -ne $inc) {
    Write-Step 'Patching mtx/public/mtx_solve_routines.inc (upstream fix 03ef2a5)'
    Set-Content -NoNewline -Path $incFile -Value $incFixed
}

# "%m" in a recipe is mangled by cmd.exe batch files; the flag is irrelevant for makedepf90.ps1
$chemMk = "$MesaDir/chem/make/makefile_base"
$t = Get-Content -Raw $chemMk
if ($t.Contains('-m %m.mod ')) { Set-Content -NoNewline -Path $chemMk -Value $t.Replace('-m %m.mod ', '') }

# ---------------------------------------------------------------- 4. data
function Expand-Tar([string]$archive, [string]$dest) {
    Invoke-Native tar @('-xf', $archive, '-C', $dest) "tar -xf $archive"
}
function Move-Files([string]$pattern, [string]$dest) {
    New-Item -ItemType Directory -Force $dest | Out-Null
    Get-ChildItem $pattern | Move-Item -Destination $dest -Force
}
function Expand-Xz([string]$src, [string]$dst) {
    Invoke-Native $PyExe ($PyArgs + @('-I', '-c', 'import lzma,shutil,sys; shutil.copyfileobj(lzma.open(sys.argv[1]), open(sys.argv[2], "wb"))', $src, $dst)) "xz $src"
}

$data = "$MesaDir/data"
$dataSteps = [ordered]@{
    chem_data = {
        New-Item -ItemType Directory -Force "$data/chem_data" | Out-Null
        Copy-Item "$MesaDir/chem/data/*" "$data/chem_data/" -Force
    }
    colors_data = {
        New-Item -ItemType Directory -Force "$data/colors_data" | Out-Null
        Copy-Item "$MesaDir/colors/data/lcb98cor.dat", "$MesaDir/colors/data/blackbody_johnson.dat" "$data/colors_data/"
    }
    eosDT_data = {
        Get-ChildItem "$data" -Directory -Filter 'eos*' | Remove-Item -Recurse -Force
        $e = "$MesaDir/eos"
        foreach ($n in 'eosDT', 'eosFreeEOS', 'eosCMS') {
            Remove-Item -Recurse -Force "$e/${n}_data" -ErrorAction SilentlyContinue
            Expand-Tar "$e/${n}_data.tar.xz" $e
            Move-Files "$e/${n}_data/*.data" "$data/${n}_data"
        }
        New-Item -ItemType Directory -Force "$data/eosDT_data/cache", "$data/eosPC_support_data/cache" | Out-Null
        Expand-Xz "$e/helm_table.dat.xz" "$data/eosDT_data/helm_table.dat"
    }
    kap_data = {
        $k = "$MesaDir/kap"
        New-Item -ItemType Directory -Force "$k/data" | Out-Null
        Remove-Item -Recurse -Force "$k/data/kap_data" -ErrorAction SilentlyContinue
        Expand-Tar "$k/kap_data.tar.xz" "$k/data"
        Expand-Tar "$k/kapcn_data.txz" "$k/data"
        Copy-Item "$k/AESOPUS_AGSS09.h5" "$k/data/kap_data/"
        Move-Files "$k/data/kap_data/*.data" "$data/kap_data"
        Move-Files "$k/data/kap_data/*.h5" "$data/kap_data"
        New-Item -ItemType Directory -Force "$data/kap_data/cache" | Out-Null
    }
    ionization_data = {
        $i = "$MesaDir/ionization"
        Remove-Item -Recurse -Force "$i/ionization_data" -ErrorAction SilentlyContinue
        Expand-Tar "$i/test/ionization_data.tar.xz" $i
        Move-Files "$i/ionization_data/*.data" "$data/ionization_data"
        New-Item -ItemType Directory -Force "$data/ionization_data/cache" | Out-Null
    }
    atm_data = {
        New-Item -ItemType Directory -Force "$data/atm_data" | Out-Null
        Copy-Item "$MesaDir/atm/atm_data/*" "$data/atm_data/" -Force
    }
}
foreach ($name in $dataSteps.Keys) {
    if ($ForceData -or -not (Test-Path "$data/$name")) {
        Write-Step "Installing data: $name"
        try { & $dataSteps[$name] } catch { Remove-Item -Recurse -Force "$data/$name" -ErrorAction SilentlyContinue; Fail "data $name : $_" }
    }
}

# ---------------------------------------------------------------- 5. build
function Build-Forum {
    $f = "$MesaDir/forum"
    if (-not (Test-Path "$f/forum/src")) {
        Remove-Item -Recurse -Force "$f/forum" -ErrorAction SilentlyContinue
        Expand-Tar "$f/forum-1.0.3.tar.gz" $f
        Rename-Item "$f/forum-1.0.3" 'forum'
    }
    $b = "$f/forum/build_win"
    New-Item -ItemType Directory -Force $b | Out-Null
    $env:PYTHONPATH = $pylib
    $src = "$f/forum/src"
    foreach ($fy in Get-ChildItem "$src/lib/*.fypp") {
        $out = "$b/$($fy.BaseName).f90"
        if (-not (Test-Path $out) -or $fy.LastWriteTimeUtc -gt (Get-Item $out).LastWriteTimeUtc) {
            Invoke-Native $PyExe ($PyArgs + @('-m', 'fypp', '--line-numbering', "-I$src/lib", "-I$src/include",
                '-DDEBUG=0', '-DOMP=1', '-DFPE=1', '-DRE_EXPORT_MOD_SYMS=0', '-DGFORTRAN_PR_112828',
                "-DLOG_LEVEL='INFO'", $fy.FullName, $out)) "fypp $($fy.Name)"
        }
    }
    Remove-Item Env:PYTHONPATH
    Invoke-Make @('-C', $b, '-f', "$MesaDir/utils/windows/forum_makefile", "-j$Jobs") 'make forum'
    Copy-Item -Path "$b/forum_m.mod", "$src/include/forum.inc" -Destination "$MesaDir/include/" -Force
    Copy-Item "$b/libforum.a" "$MesaDir/lib/" -Force
}

function Build-Module([string]$m) {
    $mk = "$MesaDir/$m/make"
    if ($Clean) {
        Get-ChildItem $mk -File | Where-Object { $_.Name -match '\.(o|mod|smod|a)$|^\.depend$' } | Remove-Item -Force
    }
    if ($m -eq 'net') {
        # replaces "rm -f $(MESA_DIR)/data/net/cache/*.bin" from net/make/makefile_base install target
        Remove-Item -Force "$MesaDir/data/net_data/cache/*.bin", "$MesaDir/data/net/cache/*.bin" -ErrorAction SilentlyContinue
    }
    if ($m -eq 'star') {
        # replaces "ln -sf ../private/pgstar_stub.f90 pgstar.f90" from star/make/makefile_base
        Copy-Item "$MesaDir/star/private/pgstar_stub.f90" "$mk/pgstar.f90" -Force
    }
    Invoke-Make @('-C', $mk, "-j$Jobs") "make $m"
    Invoke-Make @('-C', $mk, 'install') "make install $m"
}

$todo = if ($Modules) { $Modules } else { $allModules }
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($m in $todo) {
    Write-Step "building $m package ($([int]$sw.Elapsed.TotalMinutes) min elapsed)"
    if ($m -eq 'forum') { Build-Forum } else { Build-Module $m }
    Write-Host "mesa/$m has been built and exported." -ForegroundColor Green
}

Write-Host ''
Write-Host '************************************************' -ForegroundColor Green
Write-Host "MESA installation was successful ($([math]::Round($sw.Elapsed.TotalMinutes,1)) min)" -ForegroundColor Green
Write-Host '************************************************' -ForegroundColor Green
