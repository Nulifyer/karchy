package webapp

import (
	"fmt"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/nulifyer/karchy/internal/logging"
)

// Launch opens a URL in app mode using the detected Chromium browser.
// If the web app is marked as isolated, it uses a separate user-data-dir for per-app window sizing.
// Otherwise, it uses the default browser profile so extensions have full access to their data.
func Launch(appURL string) {
	browser := DetectBrowser()
	if browser == "" {
		fmt.Fprintf(os.Stderr, "No Chromium-based browser found.\n")
		os.Exit(1)
	}

	args := []string{"--app=" + appURL}
	args = append(args, launchExtraArgs()...)

	meta, ok := readMetaByURL(appURL)
	if ok && meta.Isolated {
		args = append(args, "--user-data-dir="+appDataDir(appURL))
	}

	logging.Info("Launch: %s %v", browser, args)
	cmd := exec.Command(browser, args...)
	if err := cmd.Start(); err != nil {
		logging.Error("Launch: failed to start browser: %v", err)
		fmt.Fprintf(os.Stderr, "Failed to launch browser: %v\n", err)
		os.Exit(1)
	}
}

// chromiumAppID returns the app_id that Chromium-based browsers generate
// for --app= mode on Wayland. Format: <browser>-<host><path>-<profile>
// where slashes in the path become "__".
func chromiumAppID(browser, appURL string) string {
	u, err := url.Parse(appURL)
	if err != nil {
		return ""
	}

	// Browser name prefix (e.g. "brave", "chromium", "google-chrome")
	base := strings.TrimSuffix(filepath.Base(browser), "-stable")
	base = strings.TrimSuffix(base, "-browser")

	// URL part: host + path with / replaced by __
	urlPart := u.Host
	path := strings.TrimRight(u.Path, "/")
	if path != "" {
		urlPart += strings.ReplaceAll(path, "/", "__")
	}
	urlPart += "__"

	return base + "-" + urlPart + "-Default"
}
