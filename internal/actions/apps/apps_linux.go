//go:build linux

package apps

import (
	"bufio"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Scan discovers installed applications from .desktop files.
func Scan() []AppEntry {
	dirs := []string{
		"/usr/share/applications",
		"/usr/local/share/applications",
	}
	if home, err := os.UserHomeDir(); err == nil {
		dirs = append(dirs, filepath.Join(home, ".local", "share", "applications"))
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
		if f.IsDir() || !strings.HasSuffix(f.Name(), ".desktop") {
			continue
		}
		path := filepath.Join(dir, f.Name())
		name := parseDesktopName(path)
		if name != "" {
			entries = append(entries, AppEntry{Name: name, Path: f.Name()})
		}
	}
	return entries
}

func parseDesktopName(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "Name=") {
			return strings.TrimPrefix(line, "Name=")
		}
	}
	return ""
}

// Launch opens the application using gtk-launch.
func Launch(app AppEntry) {
	// app.Path is the .desktop filename (e.g. "firefox.desktop")
	name := strings.TrimSuffix(app.Path, ".desktop")
	exec.Command("gtk-launch", name).Start()
}
