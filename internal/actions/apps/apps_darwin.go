//go:build darwin

package apps

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/nulifyer/karchy/internal/platform"
)

// Scan discovers installed applications from .app bundles.
func Scan() []AppEntry {
	dirs := []string{
		"/Applications",
		"/System/Applications",
	}

	var entries []AppEntry
	for _, dir := range dirs {
		entries = append(entries, scanDir(dir)...)
	}

	sortEntries(entries)
	return dedupSorted(entries)
}

func scanDir(dir string) []AppEntry {
	var entries []AppEntry
	files, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	for _, f := range files {
		if !strings.HasSuffix(f.Name(), ".app") {
			continue
		}
		entries = append(entries, AppEntry{
			Name: strings.TrimSuffix(f.Name(), ".app"),
			Path: filepath.Join(dir, f.Name()),
		})
	}
	return entries
}

// Launch opens the application using the open command.
func Launch(app AppEntry) {
	platform.Open(app.Path)
}
