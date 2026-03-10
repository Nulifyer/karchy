package webapp

import (
	"fmt"
	"os"
	"os/exec"

	"github.com/nulifyer/karchy/internal/logging"
)

// Launch opens a URL in app mode using the detected Chromium browser.
// If the web app is marked as isolated, it uses a separate user-data-dir for per-app window sizing.
// Otherwise, it uses the default browser profile so extensions have full access to their data.
func Launch(url string) {
	browser := DetectBrowser()
	if browser == "" {
		fmt.Fprintf(os.Stderr, "No Chromium-based browser found.\n")
		os.Exit(1)
	}

	args := []string{"--app=" + url}
	args = append(args, launchExtraArgs()...)

	meta, ok := readMetaByURL(url)
	if ok && meta.Isolated {
		args = append(args, "--user-data-dir="+appDataDir(url))
	}

	logging.Info("Launch: %s %v", browser, args)
	cmd := exec.Command(browser, args...)
	cmd.Start()
}
