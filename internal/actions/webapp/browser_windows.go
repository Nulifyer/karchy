//go:build windows

package webapp

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/nulifyer/karchy/internal/logging"
	"golang.org/x/sys/windows/registry"
)

// knownChromiumExes maps lowercase exe filenames to whether they support --app=.
var knownChromiumExes = map[string]bool{
	"brave.exe":   true,
	"chrome.exe":  true,
	"msedge.exe":  true,
	"vivaldi.exe": true,
	"opera.exe":   true,
}

// chromiumPaths is the ordered fallback list if the default browser isn't Chromium.
var chromiumPaths = []string{
	// Brave
	`%ProgramFiles%\BraveSoftware\Brave-Browser\Application\brave.exe`,
	`%ProgramFiles(x86)%\BraveSoftware\Brave-Browser\Application\brave.exe`,
	// Chromium / Ungoogled Chromium
	`%ProgramFiles%\Chromium\Application\chrome.exe`,
	`%LOCALAPPDATA%\Chromium\Application\chrome.exe`,
	// Vivaldi
	`%LOCALAPPDATA%\Vivaldi\Application\vivaldi.exe`,
	`%ProgramFiles%\Vivaldi\Application\vivaldi.exe`,
	// Opera
	`%LOCALAPPDATA%\Programs\Opera\opera.exe`,
	`%LOCALAPPDATA%\Programs\Opera GX\opera.exe`,
	`%ProgramFiles%\Opera\opera.exe`,
	// Chrome
	`%ProgramFiles%\Google\Chrome\Application\chrome.exe`,
	`%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe`,
	// Edge
	`%ProgramFiles%\Microsoft\Edge\Application\msedge.exe`,
	`%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe`,
}

// DetectBrowser returns the path to a Chromium-based browser.
// Checks the default browser first, then falls back to the ordered probe list.
func DetectBrowser() string {
	// Try default browser
	if exe := defaultBrowser(); exe != "" {
		name := strings.ToLower(filepath.Base(exe))
		if knownChromiumExes[name] {
			logging.Info("DetectBrowser: default browser is Chromium: %s", exe)
			return exe
		}
		logging.Info("DetectBrowser: default browser %s is not Chromium", exe)
	}

	// Fallback: probe known paths
	for _, tmpl := range chromiumPaths {
		path := os.ExpandEnv(tmpl)
		if _, err := os.Stat(path); err == nil {
			logging.Info("DetectBrowser: found %s", path)
			return path
		}
	}

	logging.Info("DetectBrowser: no Chromium browser found")
	return ""
}

// defaultBrowser reads the Windows default HTTP handler from the registry
// and resolves its executable path.
func defaultBrowser() string {
	// Read ProgId from UserChoice
	const userChoicePath = `Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice`
	key, err := registry.OpenKey(registry.CURRENT_USER, userChoicePath, registry.QUERY_VALUE)
	if err != nil {
		logging.Info("defaultBrowser: open UserChoice failed: %v", err)
		return ""
	}
	defer key.Close()

	progID, _, err := key.GetStringValue("ProgId")
	if err != nil || progID == "" {
		logging.Info("defaultBrowser: read ProgId failed: %v", err)
		return ""
	}
	logging.Info("defaultBrowser: ProgId=%s", progID)

	// Resolve ProgId → exe path via HKCR\{ProgId}\shell\open\command
	cmdKey, err := registry.OpenKey(registry.CLASSES_ROOT, progID+`\shell\open\command`, registry.QUERY_VALUE)
	if err != nil {
		logging.Info("defaultBrowser: open command key failed: %v", err)
		return ""
	}
	defer cmdKey.Close()

	cmd, _, err := cmdKey.GetStringValue("")
	if err != nil || cmd == "" {
		logging.Info("defaultBrowser: read command failed: %v", err)
		return ""
	}

	// Extract exe path from command string (may be quoted)
	exe := extractExePath(cmd)
	if exe == "" {
		return ""
	}

	if _, err := os.Stat(exe); err != nil {
		logging.Info("defaultBrowser: exe not found: %s", exe)
		return ""
	}
	return exe
}

// extractExePath extracts the executable path from a shell command string.
// Handles: "C:\path\browser.exe" --args  or  C:\path\browser.exe --args
func extractExePath(cmd string) string {
	cmd = strings.TrimSpace(cmd)
	if cmd == "" {
		return ""
	}
	if cmd[0] == '"' {
		end := strings.Index(cmd[1:], `"`)
		if end < 0 {
			return cmd[1:]
		}
		return cmd[1 : end+1]
	}
	lower := strings.ToLower(cmd)
	if idx := strings.Index(lower, ".exe "); idx >= 0 {
		return cmd[:idx+4]
	}
	if idx := strings.Index(lower, ".exe"); idx >= 0 {
		return cmd[:idx+4]
	}
	parts := strings.SplitN(cmd, " ", 2)
	return parts[0]
}
