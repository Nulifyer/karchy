//go:build linux

package webapp

import (
	"bufio"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/nulifyer/karchy/internal/logging"
)

// knownChromiumDesktops maps .desktop filenames to whether they support --app=.
var knownChromiumDesktops = map[string]bool{
	"brave-browser.desktop":        true,
	"brave-browser-stable.desktop": true,
	"ungoogled-chromium.desktop":   true,
	"chromium.desktop":             true,
	"chromium-browser.desktop":     true,
	"vivaldi-stable.desktop":       true,
	"vivaldi.desktop":              true,
	"opera.desktop":                true,
	"google-chrome.desktop":        true,
	"google-chrome-stable.desktop": true,
}

// chromiumDesktopOrder is the fallback probe order.
var chromiumDesktopOrder = []string{
	"brave-browser.desktop",
	"brave-browser-stable.desktop",
	"ungoogled-chromium.desktop",
	"chromium.desktop",
	"chromium-browser.desktop",
	"vivaldi-stable.desktop",
	"vivaldi.desktop",
	"opera.desktop",
	"google-chrome.desktop",
	"google-chrome-stable.desktop",
}

// DetectBrowser returns the path to a Chromium-based browser executable.
func DetectBrowser() string {
	// Try default browser first
	if desktop := defaultBrowser(); desktop != "" {
		if knownChromiumDesktops[desktop] {
			if exe := resolveDesktopExec(desktop); exe != "" {
				logging.Info("DetectBrowser: default browser is Chromium: %s", exe)
				return exe
			}
		}
		logging.Info("DetectBrowser: default browser %s is not Chromium", desktop)
	}

	// Fallback: probe in order
	for _, desktop := range chromiumDesktopOrder {
		if exe := resolveDesktopExec(desktop); exe != "" {
			logging.Info("DetectBrowser: found %s", exe)
			return exe
		}
	}

	logging.Info("DetectBrowser: no Chromium browser found")
	return ""
}

// defaultBrowser returns the default web browser .desktop filename.
func defaultBrowser() string {
	out, err := exec.Command("xdg-settings", "get", "default-web-browser").Output()
	if err != nil {
		logging.Info("defaultBrowser: xdg-settings failed: %v", err)
		return ""
	}
	return strings.TrimSpace(string(out))
}

// resolveDesktopExec finds the Exec binary from a .desktop file.
func resolveDesktopExec(desktop string) string {
	dirs := []string{
		"/usr/share/applications",
		filepath.Join(os.Getenv("HOME"), ".local/share/applications"),
	}
	for _, dir := range dirs {
		path := filepath.Join(dir, desktop)
		if exe := parseExecFromDesktop(path); exe != "" {
			return exe
		}
	}
	return ""
}

// parseExecFromDesktop extracts the binary path from Exec= line.
func parseExecFromDesktop(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "Exec=") {
			// Extract first token (the binary), strip field codes like %u %U
			cmd := strings.TrimPrefix(line, "Exec=")
			parts := strings.Fields(cmd)
			if len(parts) > 0 {
				return parts[0]
			}
		}
	}
	return ""
}
