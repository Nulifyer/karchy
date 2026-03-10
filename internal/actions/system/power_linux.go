//go:build linux

package system

import (
	"os"
	"os/exec"
	"os/user"
)

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
	// Try KDE first, then generic loginctl
	if err := exec.Command("qdbus6", "org.kde.Shutdown", "/Shutdown", "logout").Run(); err != nil {
		if u, err := user.Current(); err == nil {
			exec.Command("loginctl", "terminate-user", u.Username).Run()
		}
	}
}

func Restart() {
	exec.Command("systemctl", "reboot").Run()
}

func Shutdown() {
	// Try KDE first for a clean logout+shutdown, then generic
	if err := exec.Command("qdbus6", "org.kde.Shutdown", "/Shutdown", "logoutAndShutdown").Run(); err != nil {
		exec.Command("systemctl", "poweroff").Run()
	}
}

func init() {
	// Ensure XDG_RUNTIME_DIR is set for loginctl
	if os.Getenv("XDG_RUNTIME_DIR") == "" {
		if u, err := user.Current(); err == nil {
			os.Setenv("XDG_RUNTIME_DIR", "/run/user/"+u.Uid)
		}
	}
}
