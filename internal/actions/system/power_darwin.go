//go:build darwin

package system

import "os/exec"

func Lock() {
	exec.Command("pmset", "displaysleepnow").Run()
}

func Sleep() {
	exec.Command("pmset", "sleepnow").Run()
}

func Hibernate() {
	// macOS doesn't have true hibernate separate from sleep
	exec.Command("pmset", "sleepnow").Run()
}

func Logout() {
	exec.Command("osascript", "-e", `tell application "System Events" to log out`).Run()
}

func Restart() {
	exec.Command("osascript", "-e", `tell application "System Events" to restart`).Run()
}

func Shutdown() {
	exec.Command("osascript", "-e", `tell application "System Events" to shut down`).Run()
}
