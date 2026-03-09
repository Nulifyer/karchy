//go:build windows

package system

import "os/exec"

func Lock() {
	exec.Command("rundll32.exe", "user32.dll,LockWorkStation").Start()
}

func Sleep() {
	exec.Command("rundll32.exe", "powrprof.dll,SetSuspendState", "0,1,0").Start()
}

func Hibernate() {
	exec.Command("shutdown", "/h").Start()
}

func Logout() {
	exec.Command("shutdown", "/l").Start()
}

func Restart() {
	exec.Command("shutdown", "/r", "/t", "0").Start()
}

func Shutdown() {
	exec.Command("shutdown", "/s", "/t", "0").Start()
}
