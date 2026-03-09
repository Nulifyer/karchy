//go:build linux

package system

import "os/exec"

func Lock() {
	exec.Command("loginctl", "lock-session").Run()
}

func Sleep() {
	exec.Command("systemctl", "suspend").Run()
}

func Hibernate() {
	exec.Command("systemctl", "hibernate").Run()
}

func Logout() {
	// Try KDE first, then generic
	if err := exec.Command("qdbus6", "org.kde.Shutdown", "/Shutdown", "logout").Run(); err != nil {
		exec.Command("loginctl", "terminate-user", "").Run()
	}
}

func Restart() {
	exec.Command("systemctl", "reboot").Run()
}

func Shutdown() {
	exec.Command("systemctl", "poweroff").Run()
}
