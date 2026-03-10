# Karchy Installer for Windows
# Usage: irm https://raw.githubusercontent.com/Nulifyer/karchy/main/.scripts/install.ps1 | iex

$ErrorActionPreference = "Stop"

$repo = "Nulifyer/karchy"
$installDir = "$env:LOCALAPPDATA\Karchy"
$exe = "$installDir\karchy.exe"

# Detect architecture
$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    "AMD64" { "amd64" }
    "ARM64" { "arm64" }
    default {
        Write-Host "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Installing Karchy for windows/${arch}..." -ForegroundColor Cyan

# 1. Get latest release
Write-Host "  Fetching latest release..."
$release = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest"
$tag = $release.tag_name
$version = $tag.TrimStart("v")
$assetName = "karchy_${version}_windows_${arch}.zip"
$checksumName = "checksums.txt"
$asset = $release.assets | Where-Object { $_.name -eq $assetName }
$checksumAsset = $release.assets | Where-Object { $_.name -eq $checksumName }
if (-not $asset) {
    Write-Host "  ERROR: No Windows archive found in release $tag ($assetName)" -ForegroundColor Red
    exit 1
}

# 2. Download archive
Write-Host "  Downloading $tag..."
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
$zipFile = "$installDir\karchy-update.zip"
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipFile

# 3. Verify checksum
if ($checksumAsset) {
    Write-Host "  Verifying checksum..."
    $checksums = (Invoke-WebRequest -Uri $checksumAsset.browser_download_url).Content
    $expectedLine = ($checksums -split "`n") | Where-Object { $_ -like "*$assetName*" } | Select-Object -First 1
    if ($expectedLine) {
        $expectedHash = ($expectedLine -split "\s+")[0]
        $actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash.ToLower()
        if ($actualHash -ne $expectedHash) {
            Remove-Item $zipFile -Force
            Write-Host "  ERROR: Checksum mismatch!" -ForegroundColor Red
            Write-Host "    Expected: $expectedHash" -ForegroundColor Red
            Write-Host "    Got:      $actualHash" -ForegroundColor Red
            exit 1
        }
        Write-Host "  Checksum verified" -ForegroundColor Green
    }
}

# 4. Extract
$extractDir = "$installDir\karchy-extract"
if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force
Remove-Item $zipFile -Force

$newExe = "$extractDir\karchy.exe"
if (-not (Test-Path $newExe)) {
    Write-Host "  ERROR: karchy.exe not found in archive" -ForegroundColor Red
    Remove-Item $extractDir -Recurse -Force
    exit 1
}

# 5. Replace binary (handle running exe)
if (Test-Path $exe) {
    $oldFile = "$exe.old"
    if (Test-Path $oldFile) { Remove-Item $oldFile -Force }
    try {
        Rename-Item $exe $oldFile -Force
    } catch {
        Write-Host "  WARNING: Could not rename existing binary. Stop the daemon first." -ForegroundColor Yellow
    }
}
Move-Item $newExe $exe -Force
Remove-Item $extractDir -Recurse -Force
Write-Host "  Installed to $exe" -ForegroundColor Green

# 6. Add to PATH if not already there
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$installDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$userPath;$installDir", "User")
    $env:PATH = "$env:PATH;$installDir"
    Write-Host "  Added to PATH" -ForegroundColor Green
} else {
    Write-Host "  Already in PATH" -ForegroundColor Green
}

# 7. Run self-install (registers startup, checks deps, starts daemon)
try {
    & $exe install
} catch {
    Write-Host "  WARNING: Post-install setup failed. You may need to run 'karchy install' manually." -ForegroundColor Yellow
}

Write-Host "`nKarchy $tag installed!" -ForegroundColor Cyan
Write-Host "Press Win+Space to launch." -ForegroundColor Cyan
