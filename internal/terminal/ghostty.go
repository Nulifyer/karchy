package terminal

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/theme"
)

func init() {
	RegisterBackend(&ghosttyBackend{})
}

type ghosttyBackend struct{}

func (g *ghosttyBackend) Name() string   { return "ghostty" }
func (g *ghosttyBackend) Binary() string { return "ghostty" }

func (g *ghosttyBackend) LaunchArgs(configFile, title string, childArgs []string) []string {
	var args []string
	if configFile != "" {
		args = append(args, "--config-file="+configFile)
	}
	if title != "" {
		args = append(args, "--title="+title)
	}
	if len(childArgs) > 0 {
		args = append(args, "-e")
		args = append(args, childArgs...)
	}
	return args
}

func (g *ghosttyBackend) WriteConfig(cols, lines, padX, padY int, pal theme.Palette, app config.AppearanceConfig) string {
	var b []byte

	b = append(b, fmt.Sprintf("window-width = %d\nwindow-height = %d\n", cols, lines)...)
	b = append(b, fmt.Sprintf("window-padding-x = %d\nwindow-padding-y = %d\n", padX, padY)...)
	b = append(b, "window-decoration = false\n"...)
	b = append(b, "gtk-titlebar = false\n"...)
	b = append(b, fmt.Sprintf("font-family = %s\nfont-size = %.0f\n", app.FontFamily, app.FontSize)...)

	if !pal.IsInherit() {
		b = append(b, fmt.Sprintf("background = %s\nforeground = %s\n", pal.BG, pal.FG)...)
		for i := 0; i < 16; i++ {
			b = append(b, fmt.Sprintf("palette = %d=%s\n", i, pal.Colors[i])...)
		}
	}

	tmpFile := filepath.Join(os.TempDir(), "karchy-ghostty.conf")
	_ = os.WriteFile(tmpFile, b, 0o644)
	return tmpFile
}
