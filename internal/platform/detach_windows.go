//go:build windows

package platform

import (
	"os/exec"
	"syscall"
)

// Detach sets creation flags so the child process survives after the parent exits.
func Detach(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		CreationFlags: 0x00000200, // CREATE_NEW_PROCESS_GROUP
	}
}
