package terminal

import (
	"os"
	"os/exec"
	"runtime"

	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/platform"
)

// Launch opens a borderless terminal centered on screen running karchy with the given args.
// Returns the terminal process PID (0 on error).
func Launch(cols, lines int, title string, args ...string) (int, error) {
	cfg := config.Load()
	b := GetBackend(cfg.Terminal.App)
	posX, posY := estimateCenter(cols, lines)

	opts := LaunchOpts{
		Cols:       cols,
		Lines:      lines,
		PosX:       posX,
		PosY:       posY,
		Title:      title,
		Borderless: true,
		Profile:    cfg.Terminal.Profile,
	}

	exePath, _ := os.Executable()
	childArgs := append([]string{exePath}, args...)
	cmdArgs := b.LaunchArgs(opts, childArgs)

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

// LaunchProgramDefault opens the user's preferred terminal without any karchy
// overrides, so the terminal's own settings (decorations, theme, etc.)
// are used as-is. Suitable for interactive sessions like WSL distros.
func LaunchProgramDefault(program string, args ...string) (int, error) {
	cfg := config.Load()
	b := GetBackend(cfg.Terminal.App)
	childArgs := append([]string{program}, args...)
	cmdArgs := b.LaunchArgs(LaunchOpts{}, childArgs)

	logging.Info("LaunchProgramDefault: %s %v", b.Binary(), cmdArgs)
	cmd := exec.Command(b.Binary(), cmdArgs...)
	platform.Detach(cmd)

	if err := cmd.Start(); err != nil {
		logging.Error("LaunchProgramDefault: %v", err)
		return 0, err
	}
	pid := cmd.Process.Pid
	logging.Info("LaunchProgramDefault: pid=%d", pid)
	return pid, nil
}

// LaunchProgram opens a borderless terminal running an arbitrary program (not karchy).
func LaunchProgram(cols, lines int, program string, args ...string) (int, error) {
	cfg := config.Load()
	b := GetBackend(cfg.Terminal.App)
	posX, posY := estimateCenter(cols, lines)

	opts := LaunchOpts{
		Cols:       cols,
		Lines:      lines,
		PosX:       posX,
		PosY:       posY,
		Borderless: true,
		Profile:    cfg.Terminal.Profile,
	}

	childArgs := append([]string{program}, args...)
	cmdArgs := b.LaunchArgs(opts, childArgs)

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

// LaunchShell opens a borderless terminal running a shell command via cmd /c (Windows) or sh -c.
func LaunchShell(cols, lines int, title, script string) (int, error) {
	cfg := config.Load()
	b := GetBackend(cfg.Terminal.App)
	posX, posY := estimateCenter(cols, lines)

	opts := LaunchOpts{
		Cols:       cols,
		Lines:      lines,
		PosX:       posX,
		PosY:       posY,
		Title:      title,
		Borderless: true,
		Profile:    cfg.Terminal.Profile,
	}

	var shell, flag string
	if runtime.GOOS == "windows" {
		shell = "cmd"
		flag = "/c"
	} else {
		shell = "sh"
		flag = "-c"
	}

	childArgs := []string{shell, flag, script}
	cmdArgs := b.LaunchArgs(opts, childArgs)

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

// LaunchTerminal opens a new terminal window in the user's home directory
// using the configured terminal backend with default settings.
func LaunchTerminal() (int, error) {
	cfg := config.Load()
	b := GetBackend(cfg.Terminal.App)

	home, _ := os.UserHomeDir()
	cmdArgs := b.LaunchArgs(LaunchOpts{}, nil)

	logging.Info("LaunchTerminal: %s %v (dir=%s)", b.Binary(), cmdArgs, home)
	cmd := exec.Command(b.Binary(), cmdArgs...)
	cmd.Dir = home
	platform.Detach(cmd)

	if err := cmd.Start(); err != nil {
		logging.Error("LaunchTerminal: %v", err)
		return 0, err
	}
	pid := cmd.Process.Pid
	logging.Info("LaunchTerminal: pid=%d", pid)
	return pid, nil
}
