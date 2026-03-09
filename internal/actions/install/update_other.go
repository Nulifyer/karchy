//go:build !windows && !linux

package install

// SystemUpdate upgrades all outdated packages.
func SystemUpdate() {
	// TODO: pacman -Syu / brew upgrade
}
