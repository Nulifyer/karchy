//go:build !windows && !linux

package webapp

// DetectBrowser returns the path to a Chromium-based browser executable.
func DetectBrowser() string {
	// TODO: macOS browser detection
	return ""
}
