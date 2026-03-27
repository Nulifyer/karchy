//go:build windows

package system

import "os/exec"

func Lock() {
	exec.Command("rundll32.exe", "user32.dll,LockWorkStation").Run()
}

func Sleep() {
	exec.Command("rundll32.exe", "powrprof.dll,SetSuspendState", "0,1,0").Run()
}

func Hibernate() {
	exec.Command("shutdown", "/h").Run()
}

func Logout() {
	exec.Command("shutdown", "/l").Run()
}

func Restart() {
	exec.Command("shutdown", "/r", "/t", "0").Run()
}

func Shutdown() {
	exec.Command("shutdown", "/s", "/t", "0").Run()
}
