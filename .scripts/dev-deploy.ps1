# dev-deploy.ps1 — Build and install dev binary to production path
# Usage: .\.scripts\dev-deploy.ps1

$ErrorActionPreference = "Stop"

$installDir = "$env:LOCALAPPDATA\Karchy"
$exe = "$installDir\karchy.exe"
$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# Kill any running karchy processes
$procs = Get-Process -Name "karchy" -ErrorAction SilentlyContinue
if ($procs) {
    Write-Host "Killing karchy..." -ForegroundColor Yellow
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

# Clear log so the next run starts fresh
$logFile = "$env:APPDATA\karchy\karchy.log"
if (Test-Path $logFile) {
    Clear-Content $logFile
    Write-Host "Cleared $logFile" -ForegroundColor DarkGray
}

# Build dev version string from git
$commitShort = git -C $repoRoot rev-parse --short HEAD
$version = "dev-$commitShort"
Write-Host "Building karchy $version ..." -ForegroundColor Cyan

# Build
$ldflags = "-s -w -X main.Version=$version"
$outPath = "$repoRoot\karchy.exe"
Push-Location $repoRoot
try {
    go build -ldflags $ldflags -o $outPath .
    if ($LASTEXITCODE -ne 0) { throw "Build failed" }
} finally {
    Pop-Location
}

# Install
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Copy-Item -Force $outPath $exe
Remove-Item $outPath

Write-Host "Installed $exe ($version)" -ForegroundColor Green

# Start daemon in debug mode
Write-Host "Starting daemon (debug mode)..." -ForegroundColor Yellow
& $exe --debug daemon start

Write-Host "Done! Log: $env:APPDATA\karchy\karchy.log" -ForegroundColor Green
