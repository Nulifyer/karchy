//go:build !windows

package cleanup

// Run performs system cleanup.
func Run() {
	// TODO: remove orphans + cache (pacman) / brew cleanup
}
