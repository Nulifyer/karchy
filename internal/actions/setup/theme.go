package setup

import (
	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
)

// SelectTheme saves the theme to config and relaunches the TUI.
func SelectTheme(name string) {
	config.SaveTheme(name)
	args := []string{"menu"}
	if logging.Enabled() {
		args = []string{"--debug", "menu"}
	}
	_, _ = terminal.Launch(40, 14, "Karchy", args...)
}
