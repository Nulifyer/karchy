package webapp

import (
	"fmt"
	"os"
	"os/exec"

	"github.com/nulifyer/karchy/internal/logging"
)

// Launch opens a URL in app mode using the detected Chromium browser.
func Launch(url string) {
	browser := DetectBrowser()
	if browser == "" {
		fmt.Fprintf(os.Stderr, "No Chromium-based browser found.\n")
		os.Exit(1)
	}

	logging.Info("Launch: %s --app=%s", browser, url)
	cmd := exec.Command(browser, "--app="+url)
	cmd.Start()
}
