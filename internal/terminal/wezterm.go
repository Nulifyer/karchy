package terminal

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/theme"
)

func init() {
	RegisterBackend(&weztermBackend{})
}

type weztermBackend struct{}

func (w *weztermBackend) Name() string   { return "wezterm" }
func (w *weztermBackend) Binary() string { return "wezterm" }

func (w *weztermBackend) LaunchArgs(configFile, title string, childArgs []string) []string {
	args := []string{"start"}
	if configFile != "" {
		args = append(args, "--config-file", configFile)
	}
	if len(childArgs) > 0 {
		args = append(args, "--")
		args = append(args, childArgs...)
	}
	return args
}

func (w *weztermBackend) WriteConfig(cols, lines, padX, padY int, pal theme.Palette, app config.AppearanceConfig) string {
	lua := fmt.Sprintf(`local wezterm = require 'wezterm'
local config = wezterm.config_builder()

config.initial_cols = %d
config.initial_rows = %d
config.window_padding = { left = %d, right = %d, top = %d, bottom = %d }
config.window_decorations = "NONE"
config.font = wezterm.font("%s")
config.font_size = %.0f
config.enable_tab_bar = false
`, cols, lines, padX, padX, padY, padY, app.FontFamily, app.FontSize)

	if !pal.IsInherit() {
		lua += fmt.Sprintf(`
config.colors = {
  background = "%s",
  foreground = "%s",
  ansi = {"%s", "%s", "%s", "%s", "%s", "%s", "%s", "%s"},
  brights = {"%s", "%s", "%s", "%s", "%s", "%s", "%s", "%s"},
}
`,
			pal.BG, pal.FG,
			pal.Colors[0], pal.Colors[1], pal.Colors[2], pal.Colors[3],
			pal.Colors[4], pal.Colors[5], pal.Colors[6], pal.Colors[7],
			pal.Colors[8], pal.Colors[9], pal.Colors[10], pal.Colors[11],
			pal.Colors[12], pal.Colors[13], pal.Colors[14], pal.Colors[15],
		)
	}

	lua += "\nreturn config\n"

	tmpFile := filepath.Join(os.TempDir(), "karchy-wezterm.lua")
	_ = os.WriteFile(tmpFile, []byte(lua), 0o644)
	return tmpFile
}
