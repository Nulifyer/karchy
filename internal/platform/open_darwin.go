//go:build darwin

package platform

import "os/exec"

// Open launches a file or URI using the open command.
func Open(path string) {
	exec.Command("open", path).Start()
}
