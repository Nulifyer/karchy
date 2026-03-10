package terminal

import (
	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/theme"
)

// Backend abstracts a terminal emulator for launching karchy windows.
type Backend interface {
	// Name returns the backend identifier (e.g. "alacritty", "kitty").
	Name() string

	// WriteConfig generates a temporary config file for this terminal
	// and returns its path. If the palette is inherit, color sections
	// should be omitted so the terminal's own theme is used.
	WriteConfig(cols, lines, padX, padY int, pal theme.Palette, app config.AppearanceConfig) string

	// LaunchArgs returns the CLI args to launch the terminal with the
	// given config file, optional title, and child command + args.
	// The caller handles process spawning.
	LaunchArgs(configFile, title string, childArgs []string) []string

	// Binary returns the executable name for this terminal.
	Binary() string
}

// backendRegistry maps terminal app names to backends.
var backendRegistry = map[string]Backend{}

// RegisterBackend adds a backend to the registry.
func RegisterBackend(b Backend) {
	backendRegistry[b.Name()] = b
}

// GetBackend returns the backend for the configured terminal, falling back to alacritty.
func GetBackend(name string) Backend {
	if b, ok := backendRegistry[name]; ok {
		return b
	}
	return backendRegistry["alacritty"]
}
