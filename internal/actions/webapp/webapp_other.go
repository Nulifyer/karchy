//go:build !windows

package webapp

import "fmt"

// ShortcutDir returns the directory for web app shortcuts.
func ShortcutDir() string { return "" }

// IconDir returns the directory for web app icons.
func IconDir() string { return "" }

// convertIcon is a no-op on non-Windows (keep original format).
func convertIcon(appName, tmpPath, _ string) (string, error) {
	return tmpPath, nil
}

// Scan returns all installed web app shortcuts.
func Scan() []WebApp {
	// TODO: scan .desktop files on Linux
	return nil
}

// Remove deletes web app shortcuts.
func Remove(apps []WebApp) {
	// TODO: Linux .desktop removal
}

// deleteApps removes shortcut files and their icons.
func deleteApps(apps []WebApp) {
	// TODO: Linux .desktop removal
}

// createShortcut creates a shortcut for a web app.
func createShortcut(appName, appURL, iconPath string) error {
	return fmt.Errorf("not implemented on this platform")
}

// Create interactively creates a new web app.
func Create() {
	// TODO: Linux .desktop creation
}
