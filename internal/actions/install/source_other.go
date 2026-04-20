//go:build !windows

package install

// RefreshSources is a no-op on non-Windows platforms. Linux refresh happens
// inside SystemUpdate via `pacman -Syu`; AUR helpers query RPC directly.
func RefreshSources() {}
