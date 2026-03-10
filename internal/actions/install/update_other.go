//go:build darwin

package install

// SystemUpdate upgrades all outdated packages.
func SystemUpdate() int {
	// TODO: brew upgrade
	return 0
}

func FirmwareUpdate() {}
func MirrorUpdate()   {}
