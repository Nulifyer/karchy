//go:build darwin

package install

// SystemUpdate upgrades all outdated packages.
// Returns 0 (no external terminal PID to wait on).
func SystemUpdate() int {
	// TODO: brew upgrade
	return 0
}

func FirmwareUpdate() {}
func MirrorUpdate()   {}
