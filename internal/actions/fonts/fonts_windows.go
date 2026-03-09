//go:build windows

package fonts

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
)

// fontFilePrefix maps oh-my-posh font names to their NerdFont file prefix
// when it differs from the name. Most fonts use the same name.
var fontFilePrefix = map[string]string{
	"CascadiaCode": "CaskaydiaCove",
	"CascadiaMono": "CaskaydiaMono",
}

// reversePrefix maps font file prefixes back to oh-my-posh names.
var reversePrefix map[string]string

func init() {
	reversePrefix = make(map[string]string)
	for name, prefix := range fontFilePrefix {
		reversePrefix[strings.ToLower(prefix)] = name
	}
}

// Installed returns a set of oh-my-posh font names that are currently installed.
func Installed() map[string]bool {
	fontsDir := filepath.Join(os.Getenv("LOCALAPPDATA"), `Microsoft\Windows\Fonts`)
	entries, err := os.ReadDir(fontsDir)
	if err != nil {
		logging.Info("fonts: scan %s: %v", fontsDir, err)
		return nil
	}

	installed := make(map[string]bool)
	for _, e := range entries {
		name := e.Name()
		idx := strings.Index(name, "NerdFont")
		if idx <= 0 {
			continue
		}
		prefix := strings.ToLower(name[:idx])

		// Check reverse map for known overrides
		if omp, ok := reversePrefix[prefix]; ok {
			installed[omp] = true
			continue
		}
		// Default: prefix matches the oh-my-posh name (case-insensitive)
		for _, f := range All() {
			if strings.EqualFold(f.Name, name[:idx]) {
				installed[f.Name] = true
				break
			}
		}
	}
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
	script := strings.Join(cmds, " && ") + " & pause"
	title := fmt.Sprintf("Installing %d font(s)", len(fonts))
	if len(fonts) == 1 {
		title = "Installing " + fonts[0].Name
	}
	logging.Info("fonts: install %v", script)
	terminal.LaunchShell(100, 30, title, script)
}

// Uninstall removes fonts by deleting their files from the user fonts directory
// and removing registry entries, then runs in a terminal window.
func Uninstall(fonts []Font) {
	if len(fonts) == 0 {
		return
	}
	// oh-my-posh doesn't have an uninstall command, so we remove files manually.
	// Font files are in %LOCALAPPDATA%\Microsoft\Windows\Fonts\ and registered
	// in HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts.
	var cmds []string
	fontsDir := filepath.Join(os.Getenv("LOCALAPPDATA"), `Microsoft\Windows\Fonts`)
	for _, f := range fonts {
		prefix := f.Name
		if p, ok := fontFilePrefix[f.Name]; ok {
			prefix = p
		}
		cmds = append(cmds, fmt.Sprintf(`del /q "%s\%sNerdFont*" 2>nul`, fontsDir, prefix))
		cmds = append(cmds, fmt.Sprintf(`powershell -NoProfile -Command "Get-Item 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' | Select-Object -ExpandProperty Property | Where-Object { $_ -like '*%sNerdFont*' } | ForEach-Object { Remove-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' -Name $_ -Force }" 2>nul`, prefix))
	}
	script := strings.Join(cmds, " & ") + ` & echo Done. & pause`
	title := fmt.Sprintf("Removing %d font(s)", len(fonts))
	if len(fonts) == 1 {
		title = "Removing " + fonts[0].Name
	}
	logging.Info("fonts: uninstall %v", script)
	terminal.LaunchShell(100, 30, title, script)
}
