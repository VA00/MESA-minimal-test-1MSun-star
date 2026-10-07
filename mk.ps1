# mk.ps1 -- compile a MESA star work directory on Windows (equivalent of ./mk)
$ErrorActionPreference = 'Stop'
if (-not $env:MESA_DIR) { Write-Host 'MESA_DIR is not set; first run:  . C:\MESA\MESA-minimal-test-1MSun-star\windows\mesa_env.ps1'; exit 1 }

Push-Location (Join-Path $PSScriptRoot 'make')
try {
    mingw32-make
    if ($LASTEXITCODE -ne 0) { Write-Host "`nFAILED`n" -ForegroundColor Red; exit 1 }
} finally { Pop-Location }
