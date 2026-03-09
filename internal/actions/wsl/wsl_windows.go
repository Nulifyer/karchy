//go:build windows

package wsl

import (
	"fmt"
	"os/exec"
	"strings"
	"syscall"

	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
)

func hiddenProcAttr() *syscall.SysProcAttr {
	return &syscall.SysProcAttr{CreationFlags: 0x08000000} // CREATE_NO_WINDOW
}

// Distro represents an installed or available WSL distribution.
type Distro struct {
	Name string
}

// ListInstalled returns the names of installed WSL distributions.
func ListInstalled() []Distro {
	lines := wslCommand("-l", "-q")
	distros := make([]Distro, 0, len(lines))
	for _, name := range lines {
		if name != "" {
			distros = append(distros, Distro{Name: name})
		}
	}
	return distros
}

// ListOnline returns distributions available for install via wsl --install.
func ListOnline() []Distro {
	lines := wslCommand("--list", "--online")

	// Skip header lines until we find the "NAME" column header, then parse the rest
	pastHeader := false
	var distros []Distro
	for _, line := range lines {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		if !pastHeader {
			if strings.EqualFold(fields[0], "NAME") {
				pastHeader = true
			}
			continue
		}
		distros = append(distros, Distro{Name: fields[0]})
	}
	return distros
}

// Launch opens the given distro in a themed Alacritty window.
func Launch(d Distro) {
	logging.Info("wsl: launch %s", d.Name)
	terminal.LaunchProgram(100, 30, "wsl", "-d", d.Name)
}

// Install runs wsl --install for the given distros in a terminal window.
func Install(distros []Distro) {
	if len(distros) == 0 {
		return
	}
	var cmds []string
	for _, d := range distros {
		cmds = append(cmds, fmt.Sprintf("wsl --install -d %s --no-launch", d.Name))
	}
	script := strings.Join(cmds, " && ") + " & pause"
	title := fmt.Sprintf("Installing %d distro(s)", len(distros))
	if len(distros) == 1 {
		title = "Installing " + distros[0].Name
	}
	logging.Info("wsl: install %v", script)
	terminal.LaunchShell(100, 30, title, script)
}

// Remove unregisters the given distros.
func Remove(distros []Distro) {
	if len(distros) == 0 {
		return
	}
	var cmds []string
	for _, d := range distros {
		cmds = append(cmds, fmt.Sprintf("wsl --unregister %s", d.Name))
	}
	script := strings.Join(cmds, " && ") + " & pause"
	title := fmt.Sprintf("Removing %d distro(s)", len(distros))
	if len(distros) == 1 {
		title = "Removing " + distros[0].Name
	}
	logging.Info("wsl: remove %v", script)
	terminal.LaunchShell(100, 30, title, script)
}

// Shutdown runs wsl --shutdown.
func Shutdown() {
	logging.Info("wsl: shutdown")
	terminal.LaunchShell(80, 10, "WSL Shutdown", "wsl --shutdown & echo Done. & pause")
}

// Enable installs WSL and sets default version to 2.
func Enable() {
	logging.Info("wsl: enable")
	terminal.LaunchShell(100, 30, "Enable WSL", "wsl --install && wsl --set-default-version 2 & pause")
}

// wslCommand runs wsl.exe with args and returns decoded output lines.
// WSL outputs UTF-16LE; we strip null bytes to decode.
func wslCommand(args ...string) []string {
	cmd := exec.Command("wsl.exe", args...)
	cmd.SysProcAttr = hiddenProcAttr()
	out, err := cmd.Output()
	if err != nil {
		logging.Info("wslCommand %v: %v", args, err)
		return nil
	}

	// WSL outputs UTF-16LE — filter null bytes to get ASCII/UTF-8
	clean := make([]byte, 0, len(out)/2)
	for _, b := range out {
		if b != 0 {
			clean = append(clean, b)
		}
	}

	lines := strings.Split(string(clean), "\n")
	result := make([]string, 0, len(lines))
	for _, line := range lines {
		line = strings.TrimRight(line, "\r \t")
		if line != "" {
			result = append(result, line)
		}
	}
	return result
}
