//go:build linux

package apps

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"

	"github.com/nulifyer/karchy/internal/platform"
)

// xdgDataDirs returns the XDG application directories in priority order.
func xdgDataDirs() []string {
	var dirs []string

	// Highest priority: user local
	if home, err := os.UserHomeDir(); err == nil {
		dirs = append(dirs, filepath.Join(home, ".local", "share", "applications"))
	}

	// $XDG_DATA_DIRS or fallback per spec
	if env := os.Getenv("XDG_DATA_DIRS"); env != "" {
		for _, d := range strings.Split(env, ":") {
			if d != "" {
				dirs = append(dirs, filepath.Join(d, "applications"))
			}
		}
	} else {
		dirs = append(dirs,
			"/usr/local/share/applications",
			"/usr/share/applications",
		)
	}

	return dirs
}

// Scan discovers installed applications from .desktop files.
func Scan() []AppEntry {
	var entries []AppEntry
	for _, dir := range xdgDataDirs() {
		entries = append(entries, scanDir(dir)...)
	}

	sortEntries(entries)
	return dedupSorted(entries)
}

func scanDir(dir string) []AppEntry {
	var entries []AppEntry
	filepath.WalkDir(dir, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			return nil
		}
		if !strings.HasSuffix(d.Name(), ".desktop") {
			return nil
		}
		// Skip karchy's autostart entry
		if d.Name() == "karchy.desktop" {
			return nil
		}
		name, visible := parseDesktop(path)
		if name != "" && visible {
			entries = append(entries, AppEntry{Name: name, Path: d.Name()})
		}
		return nil
	})
	return entries
}

// parseDesktop extracts the Name and checks NoDisplay/Hidden from a .desktop file.
func parseDesktop(path string) (name string, visible bool) {
	f, err := os.Open(path)
	if err != nil {
		return "", false
	}
	defer f.Close()

	visible = true
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		switch {
		case strings.HasPrefix(line, "Name=") && name == "":
			name = strings.TrimPrefix(line, "Name=")
		case line == "NoDisplay=true" || line == "Hidden=true":
			visible = false
		}
	}
	return name, visible
}

// Launch opens the application using gtk-launch.
func Launch(app AppEntry) {
	// app.Path is the .desktop filename (e.g. "firefox.desktop")
	name := strings.TrimSuffix(app.Path, ".desktop")
	platform.DetachedStart("gtk-launch", name)
}
