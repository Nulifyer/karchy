//go:build linux

package daemon

import (
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"github.com/godbus/dbus/v5"
	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
)

// shortcutDef matches the D-Bus type (sa{sv}) expected by the GlobalShortcuts portal.
type shortcutDef struct {
	ID   string                    `dbus:"struct"`
	Opts map[string]dbus.Variant
}

func lockFilePath() string {
	cacheDir, err := os.UserCacheDir()
	if err != nil {
		home, _ := os.UserHomeDir()
		cacheDir = filepath.Join(home, ".cache")
	}
	return filepath.Join(cacheDir, "karchy-daemon.lock")
}

func isRunning() bool {
	data, err := os.ReadFile(lockFilePath())
	if err != nil {
		return false
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil {
		return false
	}
	proc, err := os.FindProcess(pid)
	if err != nil {
		return false
	}
	return proc.Signal(syscall.Signal(0)) == nil
}

func stopDaemon() {
	data, err := os.ReadFile(lockFilePath())
	if err != nil {
		return
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil {
		return
	}
	proc, err := os.FindProcess(pid)
	if err != nil {
		return
	}
	_ = proc.Signal(syscall.SIGTERM)
	_ = os.Remove(lockFilePath())
}

func hideProcess(cmd *exec.Cmd) {
	cmd.Stdout = nil
	cmd.Stderr = nil
	cmd.Stdin = nil
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Setsid: true,
	}
}

var menuPID int

func run() {
	// Write PID lock file
	lockFile := lockFilePath()
	_ = os.MkdirAll(filepath.Dir(lockFile), 0755)
	_ = os.WriteFile(lockFile, []byte(fmt.Sprintf("%d", os.Getpid())), 0644)
	defer os.Remove(lockFile)

	// Handle SIGTERM gracefully
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)

	cfg := config.Load()
	hotkey := cfg.Hotkey.Toggle
	if hotkey == "" {
		hotkey = "Super+Space"
	}

	// Try D-Bus GlobalShortcuts portal
	portalCh, err := registerPortalShortcut(hotkey)
	if err != nil {
		logging.Info("portal shortcut failed: %v", err)
		fmt.Printf("Karchy daemon running (portal shortcut unavailable: %v)\n", err)
		// Block waiting for signal
		<-sigCh
		return
	}

	fmt.Println("Karchy daemon started.")
	logging.Info("daemon: portal shortcut registered for %s", hotkey)

	for {
		select {
		case <-portalCh:
			logging.Info("daemon: hotkey activated")
			// Kill existing popup before launching new one
			if menuPID != 0 {
				if p, err := os.FindProcess(menuPID); err == nil {
					p.Kill()
					logging.Info("daemon: killed existing menu pid=%d", menuPID)
				}
				menuPID = 0
			}
			launchMenu()
		case <-sigCh:
			logging.Info("daemon: received signal, shutting down")
			return
		}
	}
}

func launchMenu() {
	args := []string{}
	if logging.Enabled() {
		args = append(args, "--debug")
	}
	args = append(args, "menu")
	logging.Info("launchMenu: args=%v", args)

	pid, err := terminal.Launch(40, 14, "Karchy", args...)
	if err != nil {
		logging.Error("launchMenu: %v", err)
		return
	}
	menuPID = pid
}

// portalTrigger converts a config hotkey string like "Super+Space" to a
// portal-compatible trigger string like "super+space".
func portalTrigger(hotkey string) string {
	// Portal expects lowercase XKB-style triggers
	parts := strings.Split(hotkey, "+")
	for i, p := range parts {
		p = strings.TrimSpace(p)
		switch strings.ToLower(p) {
		case "super", "win", "cmd", "command":
			parts[i] = "SUPER"
		case "alt", "option":
			parts[i] = "ALT"
		case "ctrl", "control":
			parts[i] = "CTRL"
		case "shift":
			parts[i] = "SHIFT"
		case "space":
			parts[i] = "space"
		default:
			parts[i] = strings.ToLower(p)
		}
	}
	return strings.Join(parts, "+")
}

// registerPortalShortcut registers a global shortcut via the xdg-desktop-portal
// GlobalShortcuts D-Bus interface. Returns a channel that receives a value each
// time the shortcut is activated.
func registerPortalShortcut(hotkey string) (<-chan struct{}, error) {
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return nil, fmt.Errorf("connect session bus: %w", err)
	}

	portal := conn.Object("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop")

	// Step 1: CreateSession
	sessionToken := "karchy_session"
	createOpts := map[string]dbus.Variant{
		"handle_token":  dbus.MakeVariant("karchy_create"),
		"session_handle_token": dbus.MakeVariant(sessionToken),
	}

	// Subscribe to the Response signal before making the call
	responseCh := make(chan *dbus.Signal, 1)
	conn.Signal(responseCh)

	// Match response signals from the portal
	senderName := strings.Replace(conn.Names()[0], ":", "", 1)
	senderName = strings.Replace(senderName, ".", "_", -1)
	responsePath := dbus.ObjectPath("/org/freedesktop/portal/desktop/request/" + senderName + "/karchy_create")
	conn.BusObject().Call("org.freedesktop.DBus.AddMatch", 0,
		fmt.Sprintf("type='signal',interface='org.freedesktop.portal.Request',path='%s',member='Response'", responsePath))

	var requestPath dbus.ObjectPath
	err = portal.Call("org.freedesktop.portal.GlobalShortcuts.CreateSession", 0, createOpts).Store(&requestPath)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("CreateSession: %w", err)
	}

	logging.Info("portal: CreateSession request=%s", requestPath)

	// Wait for response
	var sessionPath dbus.ObjectPath
	select {
	case sig := <-responseCh:
		if len(sig.Body) < 2 {
			conn.Close()
			return nil, fmt.Errorf("CreateSession response: unexpected body")
		}
		responseCode, ok := sig.Body[0].(uint32)
		if !ok || responseCode != 0 {
			conn.Close()
			return nil, fmt.Errorf("CreateSession response: code=%v", sig.Body[0])
		}
		results, ok := sig.Body[1].(map[string]dbus.Variant)
		if !ok {
			conn.Close()
			return nil, fmt.Errorf("CreateSession response: unexpected results type")
		}
		if sp, ok := results["session_handle"]; ok {
			sessionPath = dbus.ObjectPath(sp.Value().(string))
		}
	}

	if sessionPath == "" {
		conn.Close()
		return nil, fmt.Errorf("CreateSession: no session handle in response")
	}

	logging.Info("portal: session=%s", sessionPath)

	// Remove the create response match
	conn.BusObject().Call("org.freedesktop.DBus.RemoveMatch", 0,
		fmt.Sprintf("type='signal',interface='org.freedesktop.portal.Request',path='%s',member='Response'", responsePath))

	// Step 2: BindShortcuts
	// Portal expects a(sa{sv}) — array of (string, dict) tuples
	trigger := portalTrigger(hotkey)
	shortcutEntry := shortcutDef{
		ID: "karchy-toggle",
		Opts: map[string]dbus.Variant{
			"description":       dbus.MakeVariant("Toggle Karchy Menu"),
			"preferred_trigger": dbus.MakeVariant(trigger),
		},
	}
	shortcuts := []shortcutDef{shortcutEntry}

	bindOpts := map[string]dbus.Variant{
		"handle_token": dbus.MakeVariant("karchy_bind"),
	}

	bindResponsePath := dbus.ObjectPath("/org/freedesktop/portal/desktop/request/" + senderName + "/karchy_bind")
	conn.BusObject().Call("org.freedesktop.DBus.AddMatch", 0,
		fmt.Sprintf("type='signal',interface='org.freedesktop.portal.Request',path='%s',member='Response'", bindResponsePath))

	err = portal.Call("org.freedesktop.portal.GlobalShortcuts.BindShortcuts", 0,
		sessionPath, shortcuts, "", bindOpts).Store(&requestPath)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("BindShortcuts: %w", err)
	}

	logging.Info("portal: BindShortcuts request=%s trigger=%s", requestPath, trigger)

	// Wait for bind response
	select {
	case sig := <-responseCh:
		if len(sig.Body) >= 1 {
			responseCode, ok := sig.Body[0].(uint32)
			if !ok || responseCode != 0 {
				conn.Close()
				return nil, fmt.Errorf("BindShortcuts response: code=%v", sig.Body[0])
			}
		}
	}

	logging.Info("portal: shortcuts bound successfully")

	// Remove the bind response match
	conn.BusObject().Call("org.freedesktop.DBus.RemoveMatch", 0,
		fmt.Sprintf("type='signal',interface='org.freedesktop.portal.Request',path='%s',member='Response'", bindResponsePath))

	// Step 3: Listen for Activated signals
	conn.BusObject().Call("org.freedesktop.DBus.AddMatch", 0,
		"type='signal',interface='org.freedesktop.portal.GlobalShortcuts',member='Activated'")

	activatedCh := make(chan struct{}, 1)

	// Stop forwarding response signals, start listening for activation
	conn.RemoveSignal(responseCh)

	signalCh := make(chan *dbus.Signal, 10)
	conn.Signal(signalCh)

	go func() {
		for sig := range signalCh {
			if sig.Name == "org.freedesktop.portal.GlobalShortcuts.Activated" {
				logging.Info("portal: Activated signal received: %v", sig.Body)
				select {
				case activatedCh <- struct{}{}:
				default:
				}
			}
		}
	}()

	return activatedCh, nil
}
