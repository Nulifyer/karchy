//go:build windows

package install

import (
	"bufio"
	"fmt"
	"os"

	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
)

// SystemUpdate finds all installed packages and runs them through the batch pipeline.
// Returns 0 since the update runs inline (no external terminal PID to wait on).
func SystemUpdate() int {
	terminal.ResizeAndCenter(100, 30)

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

func FirmwareUpdate() {}
func MirrorUpdate()   {}
