//go:build windows

package install

import (
	"bufio"
	"encoding/base64"
	"fmt"
	"os"
	"unicode/utf16"

	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
)

// encodePSCommand encodes a PowerShell script as UTF-16LE base64 for use with -EncodedCommand.
func encodePSCommand(script string) string {
	runes := utf16.Encode([]rune(script))
	b := make([]byte, len(runes)*2)
	for i, r := range runes {
		b[i*2] = byte(r)
		b[i*2+1] = byte(r >> 8)
	}
	return base64.StdEncoding.EncodeToString(b)
}

// SystemUpdate finds all installed packages and runs them through the batch pipeline.
// Returns 0 since the update runs inline (no external terminal PID to wait on).
func SystemUpdate() int {
	terminal.ResizeAndCenter(100, 30)

	fmt.Printf("\n :: Refreshing sources...\n\n")
	refreshSources()

	fmt.Printf("\n :: Checking for updates...\n\n")

	installed := InstalledIDs()
	if len(installed) == 0 {
		fmt.Printf(" No installed packages found.\n\n")
		fmt.Print(" Press Enter to close...")
		bufio.NewReader(os.Stdin).ReadBytes('\n')
		return 0
	}

	all := SearchPackages()
	if len(all) == 0 {
		fmt.Printf(" Could not load package index.\n\n")
		fmt.Print(" Press Enter to close...")
		bufio.NewReader(os.Stdin).ReadBytes('\n')
		return 0
	}

	// Collect all installed packages that exist in the search index
	var candidates []PackageEntry
	for _, pkg := range all {
		if _, ok := installed[pkg.ID]; ok {
			candidates = append(candidates, pkg)
		}
	}

	if len(candidates) == 0 {
		fmt.Printf(" No matching packages in index.\n\n")
		fmt.Print(" Press Enter to close...")
		bufio.NewReader(os.Stdin).ReadBytes('\n')
		return 0
	}

	logging.Info("SystemUpdate: %d installed packages found in index", len(candidates))

	// batchPipeline handles version check, download, verify, install
	batchPipeline(candidates, true)
	return 0
}

func FirmwareUpdate() {
	script := `$ErrorActionPreference = 'SilentlyContinue'

Write-Host ''
Write-Host 'Checking for driver and firmware updates...' -ForegroundColor Cyan
Write-Host ''

$session = New-Object -ComObject 'Microsoft.Update.Session'
$searcher = $session.CreateUpdateSearcher()
$results = $searcher.Search("IsInstalled=0 and Type='Driver'")
$updates = $results.Updates

if ($updates.Count -eq 0) {
    Write-Host 'No driver or firmware updates available.' -ForegroundColor Green
} else {
    Write-Host ('Found ' + $updates.Count + ' update(s):') -ForegroundColor Yellow
    Write-Host ''
    foreach ($u in $updates) { Write-Host ('  - ' + $u.Title) }
    Write-Host ''
    $ans = Read-Host 'Install all updates? [Y/n]'
    if ($ans -eq '' -or $ans -eq 'Y' -or $ans -eq 'y') {
        $dl = $session.CreateUpdateDownloader()
        $dl.Updates = $updates
        Write-Host ''
        Write-Host 'Downloading updates...' -ForegroundColor Cyan
        $dl.Download() | Out-Null
        $inst = $session.CreateUpdateInstaller()
        $inst.Updates = $updates
        Write-Host 'Installing updates...' -ForegroundColor Cyan
        $res = $inst.Install()
        Write-Host ''
        if ($res.ResultCode -eq 2 -or $res.ResultCode -eq 3) {
            Write-Host 'All updates installed successfully.' -ForegroundColor Green
            if ($res.RebootRequired) {
                Write-Host 'A reboot is required to complete installation.' -ForegroundColor Yellow
            }
        } else {
            Write-Host ('Installation failed. Result code: ' + $res.ResultCode) -ForegroundColor Red
        }
    }
}

Write-Host ''
Read-Host 'Press Enter to close'
`
	terminal.LaunchProgramElevated(100, 25, "Firmware & Driver Update", "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encodePSCommand(script))
}

func MirrorUpdate() {}
