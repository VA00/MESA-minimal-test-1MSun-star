# re.ps1 -- restart MESA star from a photo (equivalent of ./re)
#   .\re.ps1            restart from the most recent photo
#   .\re.ps1 x100       restart from photos\x100
param([string]$Photo)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $photoDir = 'photos'
    if (-not $Photo) {
        $Photo = Get-ChildItem $photoDir -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty Name
    }
    if (-not $Photo -or -not (Test-Path (Join-Path $photoDir $Photo) -PathType Leaf)) {
        Write-Host 'specified photo does not exist'; exit 1
    }
    Write-Host "restart from $Photo"
    Copy-Item (Join-Path $photoDir $Photo) restart_photo -Force
    Get-Date -Format "'DATE: 'yyyy-MM-dd`n'TIME: 'HH:mm:ss"
    & .\star.exe
    $rc = $LASTEXITCODE
    Get-Date -Format "'DATE: 'yyyy-MM-dd`n'TIME: 'HH:mm:ss"
    exit $rc
} finally { Pop-Location }
