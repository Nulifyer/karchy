//go:build linux

package cleanup

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

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

// Run performs system cleanup: removes orphan packages and cleans package cache.
func Run() {
	terminal.ResizeAndCenter(80, 24)

	fmt.Printf("\n %s%s:: Scanning...%s\n\n", colorBold, colorCyan, colorReset)

	// Check for orphan packages
	orphans := findOrphans()
	cacheSize := pacmanCacheSize()
	userCacheSize, userCacheCount := dirSize(userCacheDir())

	hasWork := len(orphans) > 0 || cacheSize > 0 || userCacheCount > 0

	if !hasWork {
		fmt.Printf(" %s%s:: System is clean.%s\n\n", colorBold, colorGreen, colorReset)
		fmt.Print(" Press Enter to close...")
		bufio.NewReader(os.Stdin).ReadBytes('\n')
		return
	}

	if len(orphans) > 0 {
		fmt.Printf(" Orphan packages:         %d packages\n", len(orphans))
		for _, o := range orphans {
			fmt.Printf("   %s\n", o)
		}
	}

	if cacheSize > 0 {
		fmt.Printf(" Package cache:           %s\n", formatSize(cacheSize))
	}

	if userCacheCount > 0 {
		fmt.Printf(" User cache (~/.cache):   %s (%d files)\n", formatSize(userCacheSize), userCacheCount)
	}

	fmt.Printf("\n %s%s:: Proceed with cleanup? [Y/n]%s ", colorBold, colorCyan, colorReset)
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	if len(line) > 0 && (line[0] == 'n' || line[0] == 'N') {
		return
	}

	fmt.Printf("\n %s%s:: Cleaning...%s\n\n", colorBold, colorCyan, colorReset)

	// Remove orphans
	if len(orphans) > 0 {
		fmt.Print(" Removing orphan packages...")
		cmd := exec.Command("sudo", append([]string{"pacman", "-Rns", "--noconfirm"}, orphans...)...)
		if err := cmd.Run(); err != nil {
			fmt.Printf(" %sfailed: %v%s\n", colorRed, err, colorReset)
		} else {
			fmt.Printf(" %sdone%s\n", colorGreen, colorReset)
		}
	}

	// Clean package cache (keep last version only)
	if cacheSize > 0 {
		fmt.Print(" Cleaning package cache...")
		if hasPaccache() {
			cmd := exec.Command("sudo", "paccache", "-rk1")
			if err := cmd.Run(); err != nil {
				fmt.Printf(" %sfailed: %v%s\n", colorRed, err, colorReset)
			} else {
				fmt.Printf(" %sdone%s\n", colorGreen, colorReset)
			}
		} else {
			cmd := exec.Command("sudo", "pacman", "-Sc", "--noconfirm")
			if err := cmd.Run(); err != nil {
				fmt.Printf(" %sfailed: %v%s\n", colorRed, err, colorReset)
			} else {
				fmt.Printf(" %sdone%s\n", colorGreen, colorReset)
			}
		}
	}

	// Clean user cache
	if userCacheCount > 0 {
		fmt.Print(" Cleaning user cache...")
		freed, errs := cleanDir(userCacheDir())
		if errs > 0 {
			fmt.Printf(" %s%s freed (%d skipped)%s\n", colorGreen, formatSize(freed), errs, colorReset)
		} else {
			fmt.Printf(" %s%s freed%s\n", colorGreen, formatSize(freed), colorReset)
		}
	}

	fmt.Printf("\n %s%s:: Cleanup complete.%s\n\n", colorBold, colorGreen, colorReset)
	fmt.Print(" Press Enter to close...")
	bufio.NewReader(os.Stdin).ReadBytes('\n')
}

func findOrphans() []string {
	out, err := exec.Command("pacman", "-Qdtq").Output()
	if err != nil {
		// Exit code 1 means no orphans
		return nil
	}
	var orphans []string
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if line != "" {
			orphans = append(orphans, line)
		}
	}
	return orphans
}

func pacmanCacheSize() int64 {
	size, _ := dirSize("/var/cache/pacman/pkg")
	return size
}

func userCacheDir() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".cache")
}

func hasPaccache() bool {
	_, err := exec.LookPath("paccache")
	return err == nil
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
