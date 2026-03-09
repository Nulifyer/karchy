//go:build !windows

package platform

import "os/exec"

// Detach is a no-op on Unix — child processes already survive parent exit with Start().
func Detach(cmd *exec.Cmd) {}
