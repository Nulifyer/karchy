package terminal

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/theme"
)

func init() {
	RegisterBackend(&kittyBackend{})
}

type kittyBackend struct{}

func (k *kittyBackend) Name() string   { return "kitty" }
func (k *kittyBackend) Binary() string { return "kitty" }

func (k *kittyBackend) LaunchArgs(configFile, title string, childArgs []string) []string {
	var args []string
	if configFile != "" {
		args = append(args, "--config", configFile)
	}
	if title != "" {
		args = append(args, "--title", title)
	}
	if len(childArgs) > 0 {
		args = append(args, childArgs...)
	}
	return args
}

func (k *kittyBackend) WriteConfig(cols, lines, padX, padY int, pal theme.Palette, app config.AppearanceConfig) string {
	var b []byte

	b = append(b, fmt.Sprintf("remember_window_size no\ninitial_window_width %dc\ninitial_window_height %dl\n", cols, lines)...)
	b = append(b, fmt.Sprintf("window_padding_width %d %d\n", padY, padX)...)
	b = append(b, "hide_window_decorations yes\n"...)
	b = append(b, fmt.Sprintf("font_family %s\nfont_size %.0f\n", app.FontFamily, app.FontSize)...)

	if !pal.IsInherit() {
		b = append(b, fmt.Sprintf("\nbackground %s\nforeground %s\n", pal.BG, pal.FG)...)
		names := [16]string{
			"color0", "color1", "color2", "color3", "color4", "color5", "color6", "color7",
			"color8", "color9", "color10", "color11", "color12", "color13", "color14", "color15",
		}
		for i, name := range names {
			b = append(b, fmt.Sprintf("%s %s\n", name, pal.Colors[i])...)
		}
	}

	tmpFile := filepath.Join(os.TempDir(), "karchy-kitty.conf")
	_ = os.WriteFile(tmpFile, b, 0o644)
	return tmpFile
}
