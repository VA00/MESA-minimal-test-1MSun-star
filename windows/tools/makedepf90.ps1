# makedepf90.ps1 -- minimal PowerShell replacement for makedepf90
#
#   makedepf90.ps1 [-I dir1:dir2...] [-m fmt] [-X] [-u mod] ... file1.f90 file2.f ...
#
# Writes make dependency rules to stdout:
#
#   foo.o : ../private/foo.inc bar.o baz.o
#
# where bar.o/baz.o are the objects (from the same file list) that define the
# Fortran modules USEd by foo (also through INCLUDEd files). Modules defined
# elsewhere (other MESA packages, intrinsic modules, HDF5, ...) are ignored:
# MESA packages are built one after another, so they already exist.
#
# Sources and include files are searched in the current directory and then in
# the -I directories (':'-separated, as in the MESA makefiles).

$ErrorActionPreference = 'Stop'

$searchDirs = [System.Collections.Generic.List[string]]::new()
$searchDirs.Add('.')
$sources = [System.Collections.Generic.List[string]]::new()

function Split-PathList([string]$s) {
    # split on ':' but keep Windows drive letters ("C:/x:../y" -> "C:/x", "../y")
    $parts = $s -split ':'
    $out = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $p = $parts[$i]
        if ($p -match '^[A-Za-z]$' -and $i + 1 -lt $parts.Count -and $parts[$i + 1] -match '^[\\/]') {
            $p = $p + ':' + $parts[$i + 1]; $i++
        }
        if ($p -ne '') { $out.Add($p) }
    }
    $out
}

# PowerShell splits "-I../public:../private" as "-Name:Value", so take the raw
# command line arguments following the script path when run with pwsh -File.
$raw = [Environment]::GetCommandLineArgs()
$fileIdx = [Array]::FindIndex($raw, [Predicate[string]] { param($x) $x -ieq '-File' })
$argv = if ($fileIdx -ge 0) { @($raw | Select-Object -Skip ($fileIdx + 2)) } else { @($args) }

$takesArg = @('-m', '-u', '-o', '-r', '-d', '-R', '-b', '-l')
for ($i = 0; $i -lt $argv.Count; $i++) {
    $a = [string]$argv[$i]
    if ($a -eq '-I') { $i++; foreach ($d in Split-PathList ([string]$argv[$i])) { $searchDirs.Add($d) } }
    elseif ($a.StartsWith('-I')) { foreach ($d in Split-PathList $a.Substring(2)) { $searchDirs.Add($d) } }
    elseif ($takesArg -contains $a) { $i++ }
    elseif ($a.StartsWith('-')) { }  # other flags (-X, -W, -free, -fixed, -u<mod>, ...) ignored
    else { $sources.Add($a) }
}

$intrinsic = @('iso_c_binding', 'iso_fortran_env', 'ieee_arithmetic', 'ieee_exceptions',
               'ieee_features', 'omp_lib', 'omp_lib_kinds', 'openacc')

function Find-File([string]$name, [string]$extraDir) {
    if ([System.IO.Path]::IsPathRooted($name)) {
        if (Test-Path -LiteralPath $name -PathType Leaf) { return $name } else { return $null }
    }
    $dirs = @()
    if ($extraDir) { $dirs += $extraDir }
    $dirs += $searchDirs
    foreach ($d in $dirs) {
        $p = if ($d -eq '.') { $name } else { "$d/$name" }
        if (Test-Path -LiteralPath $p -PathType Leaf) { return ($p -replace '\\', '/') }
    }
    return $null
}

$reModule    = [regex]'(?i)^\s*module\s+(\w+)\s*(!.*)?$'
$reSubmodule = [regex]'(?i)^\s*submodule\s*\(\s*(\w+)'
$reUse       = [regex]'(?i)^\s*use\b(\s*,\s*(non_intrinsic|intrinsic)\s*::|\s*::)?\s*(\w+)'
$reInclude   = [regex]'(?i)^\s*#?\s*include\s*[''"]([^''"]+)[''"]'

# Parse one file (recursively following includes). Collects into $info.
function Read-FortranFile([string]$path, $info, [bool]$fixed) {
    if ($info.Seen.Contains($path)) { return }
    [void]$info.Seen.Add($path)
    $dir = Split-Path -Parent $path
    foreach ($line in [System.IO.File]::ReadLines((Resolve-Path -LiteralPath $path).Path)) {
        if ($fixed -and $line.Length -gt 0 -and 'cC*!'.Contains($line[0])) { continue }
        $m = $reModule.Match($line)
        if ($m.Success) {
            $name = $m.Groups[1].Value.ToLower()
            if ($name -ne 'procedure') { [void]$info.Defines.Add($name) }
            continue
        }
        $m = $reSubmodule.Match($line)
        if ($m.Success) { [void]$info.Uses.Add($m.Groups[1].Value.ToLower()); continue }
        $m = $reUse.Match($line)
        if ($m.Success) {
            if ($m.Groups[2].Value.ToLower() -ne 'intrinsic') {
                $name = $m.Groups[3].Value.ToLower()
                if ($intrinsic -notcontains $name) { [void]$info.Uses.Add($name) }
            }
            continue
        }
        $m = $reInclude.Match($line)
        if ($m.Success) {
            $inc = Find-File $m.Groups[1].Value $dir
            if ($inc) {
                if (-not $info.Includes.Contains($inc)) { $info.Includes.Add($inc) }
                Read-FortranFile $inc $info $fixed
            }
        }
    }
}

$infos = [ordered]@{}
$modOwner = @{}
foreach ($s in $sources) {
    $path = Find-File $s $null
    if (-not $path) { [Console]::Error.WriteLine("makedepf90.ps1: cannot find $s"); continue }
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($s)
    $fixed = $s -match '\.(f|F|for|FOR|f77)$'
    $info = @{
        Obj      = "$stem.o"
        Defines  = [System.Collections.Generic.HashSet[string]]::new()
        Uses     = [System.Collections.Generic.HashSet[string]]::new()
        Includes = [System.Collections.Generic.List[string]]::new()
        Seen     = [System.Collections.Generic.HashSet[string]]::new()
    }
    Read-FortranFile $path $info $fixed
    $infos[$s] = $info
    foreach ($d in $info.Defines) { $modOwner[$d] = $info.Obj }
}

foreach ($s in $infos.Keys) {
    $info = $infos[$s]
    $deps = [System.Collections.Generic.List[string]]::new()
    foreach ($inc in $info.Includes) { $deps.Add($inc) }
    foreach ($u in ($info.Uses | Sort-Object)) {
        if ($info.Defines.Contains($u)) { continue }
        $o = $modOwner[$u]
        if ($o -and $o -ne $info.Obj -and -not $deps.Contains($o)) { $deps.Add($o) }
    }
    "$($info.Obj) : $($deps -join ' ')"
}
exit 0
