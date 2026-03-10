package terminal

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/theme"
)

func init() {
	RegisterBackend(&alacrittyBackend{})
}

type alacrittyBackend struct{}

func (a *alacrittyBackend) Name() string   { return "alacritty" }
func (a *alacrittyBackend) Binary() string { return "alacritty" }

func (a *alacrittyBackend) LaunchArgs(configFile, title string, childArgs []string) []string {
	var args []string
	if configFile != "" {
		args = append(args, "--config-file", configFile)
	}
	if title != "" {
		args = append(args, "--title", title)
	}
	if len(childArgs) > 0 {
		args = append(args, "-e")
		args = append(args, childArgs...)
	}
	return args
}

func (a *alacrittyBackend) WriteConfig(cols, lines, padX, padY int, pal theme.Palette, app config.AppearanceConfig) string {
	var importSection string
	if userConfig := userAlacrittyConfig(); userConfig != "" {
		escaped := strings.ReplaceAll(userConfig, "\\", "/")
		importSection = fmt.Sprintf("[general]\nimport = [\"%s\"]\n", escaped)
	}

	posX, posY := estimateCenter(cols, lines)

	var colorSection string
	if !pal.IsInherit() {
		colorSection = fmt.Sprintf(`
[colors.primary]
background = "%s"
foreground = "%s"

[colors.normal]
black = "%s"
red = "%s"
green = "%s"
yellow = "%s"
blue = "%s"
magenta = "%s"
cyan = "%s"
white = "%s"

[colors.bright]
black = "%s"
red = "%s"
green = "%s"
yellow = "%s"
blue = "%s"
magenta = "%s"
cyan = "%s"
white = "%s"
`,
			pal.BG, pal.FG,
			pal.Colors[0], pal.Colors[1], pal.Colors[2], pal.Colors[3],
			pal.Colors[4], pal.Colors[5], pal.Colors[6], pal.Colors[7],
			pal.Colors[8], pal.Colors[9], pal.Colors[10], pal.Colors[11],
			pal.Colors[12], pal.Colors[13], pal.Colors[14], pal.Colors[15],
		)
	}

	toml := fmt.Sprintf(`%s
[window]
decorations = "None"

[window.padding]
x = %d
y = %d

[window.dimensions]
columns = %d
lines = %d

[window.position]
x = %d
y = %d

[font]
size = %.0f

[font.normal]
family = "%s"
%s
[[keyboard.bindings]]
key = "V"
mods = "Control|Shift"
action = "Paste"

[[keyboard.bindings]]
key = "C"
mods = "Control|Shift"
action = "Copy"
`,
		importSection,
		padX, padY,
		cols, lines,
		posX, posY,
		app.FontSize, app.FontFamily,
		colorSection,
	)

	tmpFile := filepath.Join(os.TempDir(), "karchy-alacritty.toml")
	_ = os.WriteFile(tmpFile, []byte(toml), 0o644)
	return tmpFile
}

func userAlacrittyConfig() string {
	if runtime.GOOS == "windows" {
		if appdata := os.Getenv("APPDATA"); appdata != "" {
			p := filepath.Join(appdata, "alacritty", "alacritty.toml")
			if _, err := os.Stat(p); err == nil {
				return p
			}
		}
	} else {
		if home, err := os.UserHomeDir(); err == nil {
			p := filepath.Join(home, ".config", "alacritty", "alacritty.toml")
			if _, err := os.Stat(p); err == nil {
				return p
			}
		}
	}
	return ""
}
