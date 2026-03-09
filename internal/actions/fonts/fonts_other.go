//go:build darwin

package fonts

// Installed returns a set of installed font names.
func Installed() map[string]bool { return nil }

// Install installs the given fonts.
func Install(fonts []Font) {
	// TODO: Linux (pacman), macOS (brew cask)
}

// Uninstall removes the given fonts.
func Uninstall(fonts []Font) {
	// TODO: Linux, macOS
}
