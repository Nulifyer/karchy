//go:build windows

package terminal

import (
	"os/exec"
	"syscall"
)

func hideLaunch(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		CreationFlags: 0x08000000, // CREATE_NO_WINDOW
	}
}
