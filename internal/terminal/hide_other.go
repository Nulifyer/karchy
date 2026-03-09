//go:build !windows

package terminal

import "os/exec"

func hideLaunch(cmd *exec.Cmd) {}
