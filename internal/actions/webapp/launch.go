package webapp

import (
	"crypto/sha256"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/nulifyer/karchy/internal/logging"
)

// Launch opens a URL in app mode using the detected Chromium browser.
// Each URL gets its own user-data-dir so Chrome remembers window size/position.
func Launch(url string) {
	browser := DetectBrowser()
	if browser == "" {
		fmt.Fprintf(os.Stderr, "No Chromium-based browser found.\n")
		os.Exit(1)
	}

	dataDir := appDataDir(url)
	logging.Info("Launch: %s --app=%s --user-data-dir=%s", browser, url, dataDir)
	cmd := exec.Command(browser, "--app="+url, "--user-data-dir="+dataDir)
	cmd.Start()
}

// appDataDir returns a per-URL Chrome user data directory under the karchy config dir.
func appDataDir(url string) string {
	dir, err := os.UserConfigDir()
	if err != nil {
		dir = os.TempDir()
	}
	hash := fmt.Sprintf("%x", sha256.Sum256([]byte(url)))[:12]
	return filepath.Join(dir, "karchy", "webapp-profiles", hash)
}
