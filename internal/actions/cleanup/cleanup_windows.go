//go:build windows

package cleanup

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"

	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
)

const (
	colorGreen = "\033[32m"
	colorRed   = "\033[31m"
	colorCyan  = "\033[36m"
	colorBold  = "\033[1m"
	colorReset = "\033[0m"
)

// target represents a cleanup location.
type target struct {
	label string
	path  string
}

func targets() []target {
	userTemp := os.TempDir()
	return []target{
		{"User temp", userTemp},
		{"Windows temp", `C:\Windows\Temp`},
		{"Prefetch", `C:\Windows\Prefetch`},
		{"Windows Update cache", `C:\Windows\SoftwareDistribution\Download`},
	}
}

// Run scans cleanup targets, shows sizes, prompts, and deletes.
func Run() {
	terminal.ResizeAndCenter(80, 20)

	fmt.Printf("\n %s%s:: Scanning...%s\n\n", colorBold, colorCyan, colorReset)

	type result struct {
		target
		size  int64
		count int
	}

	var results []result
	var totalSize int64

	for _, t := range targets() {
		size, count := dirSize(t.path)
		if count > 0 {
			results = append(results, result{t, size, count})
			totalSize += size
		}
	}

	if len(results) == 0 {
		fmt.Printf(" %s%s:: Nothing to clean.%s\n\n", colorBold, colorGreen, colorReset)
		fmt.Print(" Press Enter to close...")
		bufio.NewReader(os.Stdin).ReadBytes('\n')
		return
	}

	for _, r := range results {
		fmt.Printf(" %-30s %s (%d files)\n", r.label, formatSize(r.size), r.count)
	}
	fmt.Printf("\n Total: %s%s%s\n", colorBold, formatSize(totalSize), colorReset)

	fmt.Printf("\n %s%s:: Proceed with cleanup? [Y/n]%s ", colorBold, colorCyan, colorReset)
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	if len(line) > 0 && (line[0] == 'n' || line[0] == 'N') {
		return
	}

	fmt.Printf("\n %s%s:: Cleaning...%s\n\n", colorBold, colorCyan, colorReset)

	var freed int64
	var errors int
	for _, r := range results {
		fmt.Printf(" %-30s", r.label)
		removed, errs := cleanDir(r.path)
		if errs > 0 {
			fmt.Printf(" %s%s freed (%d skipped)%s\n", colorGreen, formatSize(removed), errs, colorReset)
			errors += errs
		} else {
			fmt.Printf(" %s%s freed%s\n", colorGreen, formatSize(removed), colorReset)
		}
		freed += removed
	}

	fmt.Printf("\n %s%s:: %s freed.%s\n\n", colorBold, colorGreen, formatSize(freed), colorReset)
	if errors > 0 {
		fmt.Printf(" %sSome files were skipped (in use or permission denied).%s\n\n", colorRed, colorReset)
	}

	fmt.Print(" Press Enter to close...")
	bufio.NewReader(os.Stdin).ReadBytes('\n')
}

// dirSize returns total size and file count of a directory.
func dirSize(dir string) (int64, int) {
	var size int64
	var count int
	filepath.Walk(dir, func(_ string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !info.IsDir() {
			size += info.Size()
			count++
		}
		return nil
	})
	return size, count
}

// cleanDir removes all files and subdirectories inside a directory.
// Returns bytes freed and number of errors.
func cleanDir(dir string) (int64, int) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		logging.Info("cleanDir: read %s failed: %v", dir, err)
		return 0, 1
	}

	var freed int64
	var errors int
	for _, e := range entries {
		path := filepath.Join(dir, e.Name())
		size := entrySize(path, e)

		if err := os.RemoveAll(path); err != nil {
			logging.Info("cleanDir: remove %s failed: %v", path, err)
			errors++
		} else {
			freed += size
		}
	}
	return freed, errors
}

// entrySize returns the total size of a file or directory entry.
func entrySize(path string, e os.DirEntry) int64 {
	if !e.IsDir() {
		if info, err := e.Info(); err == nil {
			return info.Size()
		}
		return 0
	}
	size, _ := dirSize(path)
	return size
}

func formatSize(b int64) string {
	const (
		kib = 1024
		mib = 1024 * kib
		gib = 1024 * mib
	)
	switch {
	case b >= gib:
		return fmt.Sprintf("%.1f GiB", float64(b)/float64(gib))
	case b >= mib:
		return fmt.Sprintf("%.1f MiB", float64(b)/float64(mib))
	case b >= kib:
		return fmt.Sprintf("%.1f KiB", float64(b)/float64(kib))
	default:
		return fmt.Sprintf("%d B", b)
	}
}
