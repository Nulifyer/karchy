//go:build !windows

package platform

import (
	"os/exec"
	"syscall"
	"time"
)

// Detach fully detaches the child process so it becomes an orphan reparented
// to init/systemd. This prevents the window manager from grouping it with the
// parent (Karchy/Alacritty).
func Detach(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setsid: true,
	}
	cmd.Stdin = nil
	cmd.Stdout = nil
	cmd.Stderr = nil
}

// DetachedStart launches a command fully detached in a new session so it's
// immediately reparented to PID 1, with no process tree link to the caller.
func DetachedStart(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	Detach(cmd)
	err := cmd.Start()
	time.Sleep(500 * time.Millisecond)
	return err
}
