<#
.SYNOPSIS
  Sets up the environment for native Windows MESA (equivalent of the
  "export MESA_DIR=...; source mesasdk_init.sh" lines on Linux).

.DESCRIPTION
  MESA is looked for (unless -MesaDir or $env:MESA_DIR is given) next to this repository,
  i.e. C:\MESA\mesa-24.08.1 for the repository in C:\MESA\MESA-minimal-test-1MSun-star.

.EXAMPLE
  . C:\MESA\MESA-minimal-test-1MSun-star\windows\mesa_env.ps1
  . C:\MESA\MESA-minimal-test-1MSun-star\windows\mesa_env.ps1 -MesaDir D:\MESA\mesa-24.08.1 -Threads 8
#>
param(
    [string]$MesaDir,
    [string]$Toolchain = 'C:/msys64/ucrt64',
    [int]$Threads = $(if ($env:OMP_NUM_THREADS) { [int]$env:OMP_NUM_THREADS } else { [Environment]::ProcessorCount / 2 })
)

if (-not $MesaDir) {
    if ($env:MESA_DIR) {
        $MesaDir = $env:MESA_DIR
    } else {
        # newest mesa-<version> directory next to the repository (or in C:\MESA)
        $repo = Split-Path $PSScriptRoot
        $places = @((Split-Path $repo), 'C:\MESA') | Select-Object -Unique
        $MesaDir = Get-ChildItem $places -Directory -Filter 'mesa-*' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^mesa-(\d+\.\d+\.\d+)$' -and (Test-Path (Join-Path $_.FullName 'star')) } |
            Sort-Object { [version]($_.Name -replace '^mesa-', '') } | Select-Object -Last 1 -ExpandProperty FullName
        if (-not $MesaDir) {
            Write-Host "MESA (mesa-<version>) not found in: $($places -join ', ')" -ForegroundColor Red
            Write-Host 'Give the path explicitly: . <...>\windows\mesa_env.ps1 -MesaDir <path to mesa>'
            return
        }
    }
}

$env:MESA_DIR = (Resolve-Path $MesaDir).Path -replace '\\', '/'
$env:MESA_WIN_TOOLCHAIN = $Toolchain -replace '\\', '/'
$env:OMP_NUM_THREADS = $Threads
if (-not $env:OMP_STACKSIZE) { $env:OMP_STACKSIZE = '512M' }   # stack of OpenMP worker threads
$env:MESA_WIN_SCRIPTS = $PSScriptRoot
$tcBin = ($Toolchain -replace '/', '\') + '\bin'
if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $tcBin })) { $env:PATH = "$tcBin;$env:PATH" }

Write-Host "MESA_DIR        = $env:MESA_DIR"
Write-Host "OMP_NUM_THREADS = $env:OMP_NUM_THREADS"
Write-Host "toolchain       = $tcBin"
