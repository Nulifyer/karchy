//go:build windows

package platform

import (
	"os/exec"
	"syscall"
	"time"
)

// Detach sets creation flags so the child process survives after the parent exits.
func Detach(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		CreationFlags: 0x00000200 | 0x08000000, // CREATE_NEW_PROCESS_GROUP | CREATE_NO_WINDOW
	}
}

// DetachedStart launches a command fully detached from the parent process.
// Returns the child PID (0 on error) and any start error.
func DetachedStart(name string, args ...string) (int, error) {
	cmd := exec.Command(name, args...)
	Detach(cmd)
	err := cmd.Start()
	if err != nil {
		return 0, err
	}
	time.Sleep(500 * time.Millisecond)
	return cmd.Process.Pid, nil
}
