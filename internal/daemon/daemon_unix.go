//go:build darwin

package daemon

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
)

func lockFilePath() string {
	cacheDir, err := os.UserCacheDir()
	if err != nil {
		home, _ := os.UserHomeDir()
		cacheDir = filepath.Join(home, ".cache")
	}
	return filepath.Join(cacheDir, "karchy-daemon.lock")
}

func isRunning() bool {
	data, err := os.ReadFile(lockFilePath())
	if err != nil {
		return false
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil {
		return false
	}
	// Check if process exists
	proc, err := os.FindProcess(pid)
	if err != nil {
		return false
	}
	err = proc.Signal(syscall.Signal(0))
	return err == nil
}

func stopDaemon() {
	data, err := os.ReadFile(lockFilePath())
	if err != nil {
		return
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil {
		return
	}
	proc, err := os.FindProcess(pid)
	if err != nil {
		return
	}
	_ = proc.Signal(syscall.SIGTERM)
	_ = os.Remove(lockFilePath())
}

func hideConsole() {}

func hideProcess(cmd *exec.Cmd) {
	cmd.Stdout = nil
	cmd.Stderr = nil
	cmd.Stdin = nil
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setsid: true,
	}
}

func run() {
	// Write PID lock file
	lockFile := lockFilePath()
	_ = os.MkdirAll(filepath.Dir(lockFile), 0755)
	_ = os.WriteFile(lockFile, []byte(fmt.Sprintf("%d", os.Getpid())), 0644)
	defer os.Remove(lockFile)

	// TODO: Register global hotkey via global-hotkey equivalent or X11/Wayland bindings
	// For now, just block and wait
	fmt.Println("Unix daemon running (hotkey not yet implemented)")
	select {}
}

func launchMenu() {
	args := []string{"menu"}
	if logging.Enabled() {
		args = []string{"--debug", "menu"}
	}
	_, _ = terminal.Launch(40, 14, "Karchy", args...)
}
