//go:build linux

package platform

import "os/exec"

// Open launches a file or URI using xdg-open.
func Open(path string) {
	exec.Command("xdg-open", path).Start()
}
