# rn.ps1 -- run MESA star from the beginning (equivalent of ./rn)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    Remove-Item -Force restart_photo -ErrorAction SilentlyContinue
    Get-Date -Format "'DATE: 'yyyy-MM-dd`n'TIME: 'HH:mm:ss"
    & .\star.exe
    $rc = $LASTEXITCODE
    Get-Date -Format "'DATE: 'yyyy-MM-dd`n'TIME: 'HH:mm:ss"
    exit $rc
} finally { Pop-Location }
