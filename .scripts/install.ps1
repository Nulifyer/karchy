# Karchy Installer for Windows
# Usage: irm https://raw.githubusercontent.com/Nulifyer/karchy/main/.scripts/install.ps1 | iex

$ErrorActionPreference = "Stop"

$repo = "Nulifyer/karchy"
$installDir = "$env:LOCALAPPDATA\Karchy"
$exe = "$installDir\karchy.exe"

Write-Host "Installing Karchy..." -ForegroundColor Cyan

# 1. Get latest release
Write-Host "  Fetching latest release..."
$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
$tag = $release.tag_name
$asset = $release.assets | Where-Object { $_.name -eq "karchy-windows-amd64.exe" }
if (-not $asset) {
    Write-Host "  ERROR: No Windows binary found in release $tag" -ForegroundColor Red
    exit 1
}

# 2. Download binary
Write-Host "  Downloading $tag..."
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
$tmpFile = "$installDir\karchy-update.exe"
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpFile

# 3. Replace binary (handle running exe)
if (Test-Path $exe) {
    $oldFile = "$exe.old"
    if (Test-Path $oldFile) { Remove-Item $oldFile -Force }
    try {
        Rename-Item $exe $oldFile -Force
    } catch {
        Write-Host "  WARNING: Could not rename existing binary. Stop the daemon first." -ForegroundColor Yellow
    }
}
Rename-Item $tmpFile $exe -Force
Write-Host "  Downloaded to $exe" -ForegroundColor Green

# 4. Add to PATH if not already there
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$installDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$userPath;$installDir", "User")
    $env:PATH = "$env:PATH;$installDir"
    Write-Host "  Added to PATH" -ForegroundColor Green
} else {
    Write-Host "  Already in PATH" -ForegroundColor Green
}

# 5. Run self-install (registers startup, checks deps, starts daemon)
& $exe install

Write-Host "`nKarchy $tag installed!" -ForegroundColor Cyan
Write-Host "Press Win+Space to launch." -ForegroundColor Cyan
