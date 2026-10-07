# cp_if_newer.ps1 -- PowerShell replacement for $MESA_DIR/utils/cp_if_newer
#
#   cp_if_newer.ps1 [-v] source [source...] dest_file|dest_dir
#
# Sources may contain wildcards (cmd.exe does not expand them).
# A file is copied only if the target is missing or older than the source.

$ErrorActionPreference = 'Stop'

# take raw arguments (PowerShell would split "-x:y" style tokens)
$raw = [Environment]::GetCommandLineArgs()
$fileIdx = [Array]::FindIndex($raw, [Predicate[string]] { param($x) $x -ieq '-File' })
$argv = if ($fileIdx -ge 0) { @($raw | Select-Object -Skip ($fileIdx + 2)) } else { @($args) }

$verbose = $false
$list = [System.Collections.Generic.List[string]]::new()
foreach ($a in $argv) {
    if ($a -eq '-v') { $verbose = $true } else { $list.Add([string]$a) }
}
if ($list.Count -lt 2) {
    Write-Error 'Syntax: cp_if_newer [-v] source_file [source_file...] dest_file|dest_dir'
    exit 1
}

$dst = $list[$list.Count - 1]
$srcPatterns = $list.GetRange(0, $list.Count - 1)

$srcs = foreach ($p in $srcPatterns) {
    $found = @(Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue)
    if ($found.Count -eq 0) {
        Write-Error "cp_if_newer: no such file: $p"
        exit 1
    }
    $found
}

$dstIsDir = Test-Path -LiteralPath $dst -PathType Container
if (@($srcs).Count -gt 1 -and -not $dstIsDir) {
    Write-Error "cp_if_newer: destination is not a directory: $dst"
    exit 1
}

foreach ($s in $srcs) {
    $targ = if ($dstIsDir) { Join-Path $dst $s.Name } else { $dst }
    $t = Get-Item -LiteralPath $targ -ErrorAction SilentlyContinue
    if (-not $t -or $s.LastWriteTimeUtc -gt $t.LastWriteTimeUtc) {
        Copy-Item -LiteralPath $s.FullName -Destination $targ -Force
        if ($verbose) { Write-Output "'$($s.FullName)' -> '$targ'" }
    }
}
exit 0
