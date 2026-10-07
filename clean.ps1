# clean.ps1 -- remove compiled files of a MESA star work directory (equivalent of ./clean)
Push-Location (Join-Path $PSScriptRoot 'make')
try { Remove-Item -Force *.o, *.mod, *.smod, ..\star.exe -ErrorAction SilentlyContinue } finally { Pop-Location }
