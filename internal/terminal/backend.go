package terminal

import "os/exec"

// LaunchOpts holds the parameters backends translate into CLI flags.
type LaunchOpts struct {
	Cols, Lines int
	PosX, PosY  int
	Title       string
	Borderless  bool
	Profile     string // terminal profile name (used by WT)
}

// Backend abstracts a terminal emulator for launching karchy windows.
type Backend interface {
	// Name returns the backend identifier (e.g. "alacritty", "kitty").
	Name() string

	// Binary returns the executable name for this terminal.
	Binary() string

	// LaunchArgs returns the CLI args to launch the terminal with the
	// given options and child command + args.
	LaunchArgs(opts LaunchOpts, childArgs []string) []string
}

// backendRegistry maps terminal app names to backends.
var backendRegistry = map[string]Backend{}

// RegisterBackend adds a backend to the registry.
func RegisterBackend(b Backend) {
	backendRegistry[b.Name()] = b
}

// detectOrder is the priority list for auto-detecting a terminal on Linux/macOS.
var detectOrder = []string{"ghostty", "alacritty", "kitty", "foot", "wezterm", "konsole", "gnome-terminal"}

// BackendNames returns the names of all registered backends.
func BackendNames() []string {
	names := make([]string, 0, len(backendRegistry))
	for n := range backendRegistry {
		names = append(names, n)
	}
	return names
}

// GetBackend returns the backend for the given name.
// If the name is empty or not found, it tries to detect an available terminal.
func GetBackend(name string) Backend {
	if b, ok := backendRegistry[name]; ok {
		return b
	}
	// Auto-detect: walk priority list and return the first whose binary is in PATH.
	for _, n := range detectOrder {
		if b, ok := backendRegistry[n]; ok {
			if _, err := exec.LookPath(b.Binary()); err == nil {
				return b
			}
		}
	}
	// Last resort fallback to whatever is registered first.
	for _, b := range backendRegistry {
		return b
	}
	return nil
}
