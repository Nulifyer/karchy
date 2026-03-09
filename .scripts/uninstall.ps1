# Karchy Uninstaller for Windows
# Usage: irm https://raw.githubusercontent.com/Nulifyer/karchy/main/.scripts/uninstall.ps1 | iex

$ErrorActionPreference = "Stop"

$installDir = "$env:LOCALAPPDATA\Karchy"
$exe = "$installDir\karchy.exe"

Write-Host "Uninstalling Karchy..." -ForegroundColor Cyan

# 1. Run self-uninstall (stops daemon, removes registry entries)
if (Test-Path $exe) {
    & $exe uninstall
}

# 2. Remove from PATH
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -like "*$installDir*") {
    $newPath = ($userPath -split ";" | Where-Object { $_ -ne $installDir }) -join ";"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    Write-Host "  Removed from PATH" -ForegroundColor Green
}

# 3. Remove install directory
if (Test-Path $installDir) {
    Remove-Item $installDir -Recurse -Force
    Write-Host "  Removed $installDir" -ForegroundColor Green
}

Write-Host "`nKarchy uninstalled." -ForegroundColor Cyan
