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
	ID   string
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
			parts[i] = "LOGO"
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

// waitResponse drains the signal channel until it finds a Response signal
// matching the expected path, skipping unrelated signals like NameAcquired.
func waitResponse(ch <-chan *dbus.Signal, path dbus.ObjectPath) (*dbus.Signal, error) {
	for sig := range ch {
		if sig.Path == path && sig.Name == "org.freedesktop.portal.Request.Response" {
			return sig, nil
		}
		logging.Info("portal: skipping signal %s on %s (waiting for %s)", sig.Name, sig.Path, path)
	}
	return nil, fmt.Errorf("signal channel closed")
}

// parseResponse extracts the response code and results map from a portal Response signal.
func parseResponse(sig *dbus.Signal) (uint32, map[string]dbus.Variant, error) {
	if len(sig.Body) < 2 {
		return 0, nil, fmt.Errorf("unexpected body length %d", len(sig.Body))
	}
	code, ok := sig.Body[0].(uint32)
	if !ok {
		return 0, nil, fmt.Errorf("response code type %T", sig.Body[0])
	}
	results, ok := sig.Body[1].(map[string]dbus.Variant)
	if !ok {
		return code, nil, fmt.Errorf("results type %T", sig.Body[1])
	}
	return code, results, nil
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

	// Register app identity so the portal shows "Karchy" instead of guessing
	err = portal.Call("org.freedesktop.host.portal.Registry.Register", 0,
		"karchy", map[string]dbus.Variant{}).Err
	if err != nil {
		logging.Info("portal: Registry.Register failed (may not be supported): %v", err)
	}

	// Compute our sender name for request paths
	senderName := strings.Replace(conn.Names()[0], ":", "", 1)
	senderName = strings.Replace(senderName, ".", "_", -1)

	// Single signal channel for all portal interactions
	signalCh := make(chan *dbus.Signal, 10)
	conn.Signal(signalCh)

	// Step 1: CreateSession
	createResponsePath := dbus.ObjectPath("/org/freedesktop/portal/desktop/request/" + senderName + "/karchy_create")
	conn.BusObject().Call("org.freedesktop.DBus.AddMatch", 0,
		fmt.Sprintf("type='signal',interface='org.freedesktop.portal.Request',path='%s',member='Response'", createResponsePath))

	createOpts := map[string]dbus.Variant{
		"handle_token":         dbus.MakeVariant("karchy_create"),
		"session_handle_token": dbus.MakeVariant("karchy_session"),
	}

	var requestPath dbus.ObjectPath
	err = portal.Call("org.freedesktop.portal.GlobalShortcuts.CreateSession", 0, createOpts).Store(&requestPath)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("CreateSession: %w", err)
	}
	logging.Info("portal: CreateSession request=%s", requestPath)

	sig, err := waitResponse(signalCh, createResponsePath)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("CreateSession wait: %w", err)
	}

	code, results, err := parseResponse(sig)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("CreateSession response: %w", err)
	}
	if code != 0 {
		conn.Close()
		return nil, fmt.Errorf("CreateSession rejected: code=%d", code)
	}

	sp, ok := results["session_handle"]
	if !ok {
		conn.Close()
		return nil, fmt.Errorf("CreateSession: no session_handle in response")
	}
	sessionPath := dbus.ObjectPath(sp.Value().(string))
	logging.Info("portal: session=%s", sessionPath)

	// Step 2: BindShortcuts
	trigger := portalTrigger(hotkey)
	shortcuts := []shortcutDef{{
		ID: "karchy-toggle",
		Opts: map[string]dbus.Variant{
			"description":       dbus.MakeVariant("Toggle Karchy Menu"),
			"preferred_trigger": dbus.MakeVariant(trigger),
		},
	}}

	bindResponsePath := dbus.ObjectPath("/org/freedesktop/portal/desktop/request/" + senderName + "/karchy_bind")
	conn.BusObject().Call("org.freedesktop.DBus.AddMatch", 0,
		fmt.Sprintf("type='signal',interface='org.freedesktop.portal.Request',path='%s',member='Response'", bindResponsePath))

	bindOpts := map[string]dbus.Variant{
		"handle_token": dbus.MakeVariant("karchy_bind"),
	}

	err = portal.Call("org.freedesktop.portal.GlobalShortcuts.BindShortcuts", 0,
		sessionPath, shortcuts, "", bindOpts).Store(&requestPath)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("BindShortcuts: %w", err)
	}
	logging.Info("portal: BindShortcuts request=%s trigger=%s", requestPath, trigger)

	sig, err = waitResponse(signalCh, bindResponsePath)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("BindShortcuts wait: %w", err)
	}

	code, _, err = parseResponse(sig)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("BindShortcuts response: %w", err)
	}
	if code != 0 {
		conn.Close()
		return nil, fmt.Errorf("BindShortcuts rejected: code=%d", code)
	}
	logging.Info("portal: shortcuts bound successfully")

	// Step 3: Listen for Activated signals
	conn.BusObject().Call("org.freedesktop.DBus.AddMatch", 0,
		"type='signal',interface='org.freedesktop.portal.GlobalShortcuts',member='Activated'")

	activatedCh := make(chan struct{}, 1)
	go func() {
		for sig := range signalCh {
			if sig.Name == "org.freedesktop.portal.GlobalShortcuts.Activated" {
				logging.Info("portal: Activated signal: %v", sig.Body)
				select {
				case activatedCh <- struct{}{}:
				default:
				}
			}
		}
	}()

	return activatedCh, nil
}
