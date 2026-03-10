//go:build !windows

package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
)

func selfInstall() {
	exePath, err := os.Executable()
	if err != nil {
		fmt.Println("Failed to get executable path:", err)
		os.Exit(1)
	}
	exePath, _ = filepath.EvalSymlinks(exePath)

	fmt.Println("Installing Karchy...")

	// 1. Register autostart
	switch runtime.GOOS {
	case "linux":
		installLinuxAutostart(exePath)
	case "darwin":
		installMacOSLaunchAgent(exePath)
	}

	// 2. Check for Alacritty
	if _, err := exec.LookPath("alacritty"); err != nil {
		fmt.Println("  ⚠ Alacritty not found.")
		switch runtime.GOOS {
		case "linux":
			fmt.Println("    Install it with your package manager:")
			fmt.Println("      pacman -S alacritty")
			fmt.Println("      apt install alacritty")
		case "darwin":
			fmt.Println("    Install it with: brew install --cask alacritty")
		}
	} else {
		fmt.Println("  ✓ Alacritty found")
	}

	// 3. Start daemon (session-managed)
	fmt.Println("  → Starting daemon...")
	startDaemonManaged(exePath)

	fmt.Println("\nKarchy installed!")
}

func selfUninstall() {
	fmt.Println("Uninstalling Karchy...")

	// 1. Stop daemon
	exePath, _ := os.Executable()
	cmd := exec.Command(exePath, "daemon", "stop")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Run()

	// 2. Remove autostart
	switch runtime.GOOS {
	case "linux":
		autostartPath := filepath.Join(xdgConfigHome(), "autostart", "karchy.desktop")
		os.Remove(autostartPath)
		fmt.Println("  ✓ Removed autostart entry")
	case "darwin":
		plistPath := filepath.Join(os.Getenv("HOME"), "Library", "LaunchAgents", "com.karchy.daemon.plist")
		exec.Command("launchctl", "unload", plistPath).Run()
		os.Remove(plistPath)
		fmt.Println("  ✓ Removed LaunchAgent")
	}

	// 3. Remove config directory
	configDir := filepath.Join(xdgConfigHome(), "karchy")
	os.RemoveAll(configDir)
	fmt.Println("  ✓ Removed config directory")

	fmt.Println("\nKarchy uninstalled.")
}

func startDaemonManaged(exePath string) {
	switch runtime.GOOS {
	case "linux":
		// Stop any existing instance, then start via systemd user session
		exec.Command("systemctl", "--user", "stop", "karchy.service").Run()
		cmd := exec.Command("systemd-run", "--user", "--unit=karchy", "--description=Karchy", exePath, "daemon", "run")
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			fmt.Println("  ✗ Failed to start daemon:", err)
		}
	case "darwin":
		// launchctl load already done in installMacOSLaunchAgent, just kickstart
		exec.Command("launchctl", "kickstart", "-k", "gui/"+fmt.Sprint(os.Getuid())+"/com.karchy.daemon").Run()
	}
}

func installLinuxAutostart(exePath string) {
	dir := filepath.Join(xdgConfigHome(), "autostart")
	os.MkdirAll(dir, 0o755)
	desktop := fmt.Sprintf(`[Desktop Entry]
Type=Application
Name=Karchy
Exec=%s daemon run
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
`, exePath)
	path := filepath.Join(dir, "karchy.desktop")
	if err := os.WriteFile(path, []byte(desktop), 0o644); err != nil {
		fmt.Println("  ✗ Failed to create autostart entry:", err)
		return
	}
	fmt.Println("  ✓ Registered autostart")
}

func installMacOSLaunchAgent(exePath string) {
	dir := filepath.Join(os.Getenv("HOME"), "Library", "LaunchAgents")
	os.MkdirAll(dir, 0o755)
	plist := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.karchy.daemon</string>
	<key>ProgramArguments</key>
	<array>
		<string>%s</string>
		<string>daemon</string>
		<string>run</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<false/>
</dict>
</plist>
`, exePath)
	path := filepath.Join(dir, "com.karchy.daemon.plist")
	if err := os.WriteFile(path, []byte(plist), 0o644); err != nil {
		fmt.Println("  ✗ Failed to create LaunchAgent:", err)
		return
	}
	exec.Command("launchctl", "load", path).Run()
	fmt.Println("  ✓ Registered LaunchAgent")
}

func xdgConfigHome() string {
	if dir := os.Getenv("XDG_CONFIG_HOME"); dir != "" {
		return dir
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config")
}
