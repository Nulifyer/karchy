package terminal

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/theme"
)

// Launch opens Alacritty with a borderless themed config running the given command.
// Returns the Alacritty process PID (0 on error).
func Launch(cols, lines int, title string, args ...string) (int, error) {
	cfg := config.Load()
	pal := theme.Load(cfg.Theme.Name)
	configFile := writeAlacrittyConfig(cols, lines, 4, 4, pal, cfg.Appearance)
	exePath, _ := os.Executable()

	cmdArgs := []string{
		"--config-file", configFile,
		"--title", title,
		"-e", exePath,
	}
	cmdArgs = append(cmdArgs, args...)

	logging.Info("Launch: alacritty %v", cmdArgs)
	cmd := exec.Command("alacritty", cmdArgs...)

	hideLaunch(cmd)

	err := cmd.Start()
	if err != nil {
		logging.Error("Launch: %v", err)
		return 0, err
	}
	pid := cmd.Process.Pid
	logging.Info("Launch: pid=%d", pid)
	return pid, nil
}

// LaunchProgram opens Alacritty running an arbitrary program (not karchy).
func LaunchProgram(cols, lines int, program string, args ...string) (int, error) {
	cmdArgs := []string{
		"-e", program,
	}
	cmdArgs = append(cmdArgs, args...)

	logging.Info("LaunchProgram: alacritty %v", cmdArgs)
	cmd := exec.Command("alacritty", cmdArgs...)

	hideLaunch(cmd)

	err := cmd.Start()
	if err != nil {
		logging.Error("LaunchProgram: %v", err)
		return 0, err
	}
	pid := cmd.Process.Pid
	logging.Info("LaunchProgram: pid=%d", pid)
	return pid, nil
}

// LaunchShell opens Alacritty running a shell command via cmd /c (Windows) or sh -c.
func LaunchShell(cols, lines int, title, script string) (int, error) {
	cfg := config.Load()
	pal := theme.Load(cfg.Theme.Name)
	configFile := writeAlacrittyConfig(cols, lines, 16, 12, pal, cfg.Appearance)

	var shell, flag string
	if runtime.GOOS == "windows" {
		shell = "cmd"
		flag = "/c"
	} else {
		shell = "sh"
		flag = "-c"
	}

	cmdArgs := []string{
		"--config-file", configFile,
		"--title", title,
		"-e", shell, flag, script,
	}

	logging.Info("LaunchShell: alacritty %v", cmdArgs)
	cmd := exec.Command("alacritty", cmdArgs...)

	hideLaunch(cmd)

	err := cmd.Start()
	if err != nil {
		logging.Error("LaunchShell: %v", err)
		return 0, err
	}
	pid := cmd.Process.Pid
	logging.Info("LaunchShell: pid=%d", pid)
	return pid, nil
}

func writeAlacrittyConfig(cols, lines, padX, padY int, pal theme.Palette, app config.AppearanceConfig) string {
	// Check for user's existing config to import
	var importSection string
	if userConfig := userAlacrittyConfig(); userConfig != "" {
		escaped := strings.ReplaceAll(userConfig, "\\", "/")
		importSection = fmt.Sprintf("[general]\nimport = [\"%s\"]\n", escaped)
	}

	// Estimate center position
	posX, posY := estimateCenter(cols, lines)

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
		pal.BG, pal.FG,
		pal.Colors[0], pal.Colors[1], pal.Colors[2], pal.Colors[3],
		pal.Colors[4], pal.Colors[5], pal.Colors[6], pal.Colors[7],
		pal.Colors[8], pal.Colors[9], pal.Colors[10], pal.Colors[11],
		pal.Colors[12], pal.Colors[13], pal.Colors[14], pal.Colors[15],
	)

	tmpFile := filepath.Join(os.TempDir(), "karchy-alacritty.toml")
	_ = os.WriteFile(tmpFile, []byte(toml), 0644)
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
