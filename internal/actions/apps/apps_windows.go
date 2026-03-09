//go:build windows

package apps

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/nulifyer/karchy/internal/platform"
)

// Scan discovers installed applications from Start Menu shortcut directories.
func Scan() []AppEntry {
	var entries []AppEntry

	// User Start Menu
	if appdata := os.Getenv("APPDATA"); appdata != "" {
		dir := filepath.Join(appdata, "Microsoft", "Windows", "Start Menu", "Programs")
		entries = append(entries, scanDir(dir)...)
	}

	// System Start Menu
	entries = append(entries, scanDir(`C:\ProgramData\Microsoft\Windows\Start Menu\Programs`)...)

	sortEntries(entries)
	return dedupSorted(entries)
}

func scanDir(root string) []AppEntry {
	var entries []AppEntry
	filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if !info.IsDir() && strings.EqualFold(filepath.Ext(path), ".lnk") {
			entries = append(entries, AppEntry{
				Name: nameFromPath(path),
				Path: path,
			})
		}
		return nil
	})
	return entries
}

// Launch opens the application at the given path.
func Launch(app AppEntry) {
	platform.Open(app.Path)
}
