//go:build linux

package install

import (
	"github.com/nulifyer/karchy/internal/terminal"
)

// SystemUpdate runs a full system upgrade via pacman.
func SystemUpdate() {
	script := "sudo pacman -Syu; echo; read -rp 'Press Enter to close...'"
	terminal.LaunchShell(100, 30, "System Update", script)
}
