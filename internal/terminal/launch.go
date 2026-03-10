package terminal

import (
	"os"
	"os/exec"
	"runtime"

	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/platform"
	"github.com/nulifyer/karchy/internal/theme"
)

// Launch opens a terminal with a borderless themed config running karchy with the given args.
// Returns the terminal process PID (0 on error).
func Launch(cols, lines int, title string, args ...string) (int, error) {
	cfg := config.Load()
	pal := theme.Load(cfg.Theme.Name)
	b := GetBackend(cfg.Terminal.App)
	configFile := b.WriteConfig(cols, lines, 4, 4, pal, cfg.Appearance)

	exePath, _ := os.Executable()
	childArgs := append([]string{exePath}, args...)
	cmdArgs := b.LaunchArgs(configFile, title, childArgs)

	logging.Info("Launch: %s %v", b.Binary(), cmdArgs)
	cmd := exec.Command(b.Binary(), cmdArgs...)
	platform.Detach(cmd)

	if err := cmd.Start(); err != nil {
		logging.Error("Launch: %v", err)
		return 0, err
	}
	pid := cmd.Process.Pid
	logging.Info("Launch: pid=%d", pid)
	return pid, nil
}

// LaunchProgram opens a terminal running an arbitrary program (not karchy).
func LaunchProgram(cols, lines int, program string, args ...string) (int, error) {
	cfg := config.Load()
	pal := theme.Load(cfg.Theme.Name)
	b := GetBackend(cfg.Terminal.App)
	configFile := b.WriteConfig(cols, lines, 4, 4, pal, cfg.Appearance)

	childArgs := append([]string{program}, args...)
	cmdArgs := b.LaunchArgs(configFile, "", childArgs)

	logging.Info("LaunchProgram: %s %v", b.Binary(), cmdArgs)
	cmd := exec.Command(b.Binary(), cmdArgs...)
	platform.Detach(cmd)

	if err := cmd.Start(); err != nil {
		logging.Error("LaunchProgram: %v", err)
		return 0, err
	}
	pid := cmd.Process.Pid
	logging.Info("LaunchProgram: pid=%d", pid)
	return pid, nil
}

// LaunchShell opens a terminal running a shell command via cmd /c (Windows) or sh -c.
func LaunchShell(cols, lines int, title, script string) (int, error) {
	cfg := config.Load()
	pal := theme.Load(cfg.Theme.Name)
	b := GetBackend(cfg.Terminal.App)
	configFile := b.WriteConfig(cols, lines, 16, 12, pal, cfg.Appearance)

	var shell, flag string
	if runtime.GOOS == "windows" {
		shell = "cmd"
		flag = "/c"
	} else {
		shell = "sh"
		flag = "-c"
	}

	childArgs := []string{shell, flag, script}
	cmdArgs := b.LaunchArgs(configFile, title, childArgs)

	logging.Info("LaunchShell: %s %v", b.Binary(), cmdArgs)
	cmd := exec.Command(b.Binary(), cmdArgs...)
	platform.Detach(cmd)

	if err := cmd.Start(); err != nil {
		logging.Error("LaunchShell: %v", err)
		return 0, err
	}
	pid := cmd.Process.Pid
	logging.Info("LaunchShell: pid=%d", pid)
	return pid, nil
}
