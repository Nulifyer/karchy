//go:build linux

package fonts

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
)

// Installed returns a set of oh-my-posh font names that are currently installed.
func Installed() map[string]bool {
	// Check user font directory for NerdFont files
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}

	fontDirs := []string{
		filepath.Join(home, ".local", "share", "fonts"),
		"/usr/share/fonts",
		"/usr/local/share/fonts",
	}

	installed := make(map[string]bool)
	allFonts := All()

	for _, dir := range fontDirs {
		filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
			if err != nil || info.IsDir() {
				return nil
			}
			name := info.Name()
			// Nerd Font files contain "NerdFont" in the name
			idx := strings.Index(name, "NerdFont")
			if idx <= 0 {
				return nil
			}
			prefix := strings.ToLower(name[:idx])
			for _, f := range allFonts {
				if strings.EqualFold(f.Name, name[:idx]) {
					installed[f.Name] = true
					break
				}
				// Check overrides (CascadiaCode -> CaskaydiaCove)
				if p, ok := fontFamilyOverride[f.Name]; ok {
					if strings.EqualFold(p, name[:idx]) {
						installed[f.Name] = true
						break
					}
				}
			}
			_ = prefix
			return nil
		})
	}

	logging.Info("fonts: %d installed", len(installed))
	return installed
}

// Install installs fonts via oh-my-posh in a terminal window.
func Install(fonts []Font) {
	if len(fonts) == 0 {
		return
	}
	var cmds []string
	for _, f := range fonts {
		cmds = append(cmds, fmt.Sprintf("oh-my-posh font install %s", f.Name))
	}
	script := strings.Join(cmds, " && ") + "; echo; read -rp 'Press Enter to close...'"
	title := fmt.Sprintf("Installing %d font(s)", len(fonts))
	if len(fonts) == 1 {
		title = "Installing " + fonts[0].Name
	}
	logging.Info("fonts: install %v", script)
	terminal.LaunchShell(100, 30, title, script)
}

// Uninstall removes fonts by deleting their files from the user fonts directory.
func Uninstall(fonts []Font) {
	if len(fonts) == 0 {
		return
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return
	}
	fontsDir := filepath.Join(home, ".local", "share", "fonts")

	var cmds []string
	for _, f := range fonts {
		prefix := f.Name
		if p, ok := fontFamilyOverride[f.Name]; ok {
			prefix = p
		}
		cmds = append(cmds, fmt.Sprintf("rm -f %q/%sNerdFont*", fontsDir, prefix))
	}
	script := strings.Join(cmds, " && ") + " && fc-cache -f; echo 'Done.'; read -rp 'Press Enter to close...'"
	title := fmt.Sprintf("Removing %d font(s)", len(fonts))
	if len(fonts) == 1 {
		title = "Removing " + fonts[0].Name
	}
	logging.Info("fonts: uninstall %v", script)
	terminal.LaunchShell(100, 30, title, script)
}
