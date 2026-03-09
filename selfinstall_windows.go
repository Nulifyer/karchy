//go:build windows

package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"golang.org/x/sys/windows/registry"
)

const (
	runKey          = `Software\Microsoft\Windows\CurrentVersion\Run`
	karchyValueName = "Karchy"
	// Keyboard layout toggle — disabling Win+Space language switcher
	keyboardToggleKey = `Keyboard Layout\Toggle`
)

func selfInstall() {
	exePath, err := os.Executable()
	if err != nil {
		fmt.Println("Failed to get executable path:", err)
		os.Exit(1)
	}
	exePath, _ = filepath.EvalSymlinks(exePath)

	fmt.Println("Installing Karchy...")

	// 1. Register startup
	k, _, err := registry.CreateKey(registry.CURRENT_USER, runKey, registry.SET_VALUE)
	if err != nil {
		fmt.Println("Failed to open Run registry key:", err)
	} else {
		err = k.SetStringValue(karchyValueName, `"`+exePath+`" daemon start`)
		k.Close()
		if err != nil {
			fmt.Println("Failed to set startup entry:", err)
		} else {
			fmt.Println("  ✓ Registered startup")
		}
	}

	// 2. Disable Win+Space language switcher
	disableWinSpaceToggle()

	// 3. Check for Alacritty
	if _, err := exec.LookPath("alacritty"); err != nil {
		fmt.Println("  → Alacritty not found. Installing...")
		cmd := exec.Command(exePath, "install-run", "winget", "install", "Alacritty.Alacritty", "--accept-package-agreements", "--accept-source-agreements")
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Run()
	} else {
		fmt.Println("  ✓ Alacritty found")
	}

	// 4. Check for oh-my-posh
	if _, err := exec.LookPath("oh-my-posh"); err != nil {
		fmt.Println("  → oh-my-posh not found. Installing...")
		cmd := exec.Command(exePath, "install-run", "winget", "install", "JanDeDobbeleer.OhMyPosh", "--accept-package-agreements", "--accept-source-agreements")
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		cmd.Run()
	} else {
		fmt.Println("  ✓ oh-my-posh found")
	}

	// 5. Start daemon
	fmt.Println("  → Starting daemon...")
	cmd := exec.Command(exePath, "daemon", "start")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()

	fmt.Println("\nKarchy installed! Press Win+Space to launch.")
}

func selfUninstall() {
	fmt.Println("Uninstalling Karchy...")

	// 1. Stop daemon
	exePath, _ := os.Executable()
	cmd := exec.Command(exePath, "daemon", "stop")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()

	// 2. Remove startup entry
	k, err := registry.OpenKey(registry.CURRENT_USER, runKey, registry.SET_VALUE)
	if err == nil {
		k.DeleteValue(karchyValueName)
		k.Close()
		fmt.Println("  ✓ Removed startup entry")
	}

	// 3. Re-enable Win+Space language switcher
	enableWinSpaceToggle()

	// 4. Remove config directory
	if dir, err := os.UserConfigDir(); err == nil {
		configDir := filepath.Join(dir, "karchy")
		os.RemoveAll(configDir)
		fmt.Println("  ✓ Removed config directory")
	}

	fmt.Println("\nKarchy uninstalled.")
}

func disableWinSpaceToggle() {
	k, _, err := registry.CreateKey(registry.CURRENT_USER, keyboardToggleKey, registry.SET_VALUE)
	if err != nil {
		return
	}
	defer k.Close()
	// "3" = disabled, "1" = Ctrl+Shift, "2" = Left Alt+Shift
	k.SetStringValue("Language Hotkey", "3")
	k.SetStringValue("Layout Hotkey", "3")
	fmt.Println("  ✓ Disabled Win+Space language switcher")
}

func enableWinSpaceToggle() {
	k, err := registry.OpenKey(registry.CURRENT_USER, keyboardToggleKey, registry.SET_VALUE)
	if err != nil {
		return
	}
	defer k.Close()
	k.SetStringValue("Language Hotkey", "1")
	k.SetStringValue("Layout Hotkey", "1")
	fmt.Println("  ✓ Re-enabled language switcher")
}
