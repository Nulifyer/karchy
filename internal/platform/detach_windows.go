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
		CreationFlags: 0x00000200, // CREATE_NEW_PROCESS_GROUP
	}
}

// DetachedStart launches a command fully detached from the parent process.
func DetachedStart(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	Detach(cmd)
	err := cmd.Start()
	time.Sleep(500 * time.Millisecond)
	return err
}
