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

	// Register global shortcut via KDE's kglobalaccel
	hotkeyActivated, err := registerKGlobalAccel(hotkey)
	if err != nil {
		logging.Error("kglobalaccel failed: %v", err)
		fmt.Printf("Karchy daemon running (shortcut unavailable: %v)\n", err)
		<-sigCh
		return
	}

	fmt.Println("Karchy daemon started.")
	logging.Info("daemon: shortcut registered for %s", hotkey)

	for {
		select {
		case <-hotkeyActivated:
			logging.Info("daemon: hotkey activated")
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

// qtKeyCode converts a hotkey string like "Super+Space" to a Qt key code integer.
// Qt modifier values: Meta=0x10000000, Ctrl=0x04000000, Alt=0x08000000, Shift=0x02000000
// Qt key values: Space=0x20, A-Z=0x41-0x5A, F1-F12=0x01000030-0x0100003B
func qtKeyCode(hotkey string) (int32, error) {
	var mods int32
	var key int32

	parts := strings.Split(hotkey, "+")
	for _, p := range parts {
		p = strings.TrimSpace(p)
		switch strings.ToLower(p) {
		case "super", "win", "meta", "cmd", "command":
			mods |= 0x10000000 // Qt::MetaModifier
		case "ctrl", "control":
			mods |= 0x04000000 // Qt::ControlModifier
		case "alt", "option":
			mods |= 0x08000000 // Qt::AltModifier
		case "shift":
			mods |= 0x02000000 // Qt::ShiftModifier
		case "space":
			key = 0x20
		case "return", "enter":
			key = 0x01000004
		case "escape", "esc":
			key = 0x01000000
		case "tab":
			key = 0x01000001
		case "backspace":
			key = 0x01000003
		case "delete", "del":
			key = 0x01000007
		default:
			lower := strings.ToLower(p)
			// F1-F12
			if len(lower) >= 2 && lower[0] == 'f' {
				if n, err := strconv.Atoi(lower[1:]); err == nil && n >= 1 && n <= 12 {
					key = int32(0x01000030 + n - 1)
					continue
				}
			}
			// Single letter A-Z
			if len(lower) == 1 && lower[0] >= 'a' && lower[0] <= 'z' {
				key = int32(lower[0] - 'a' + 'A') // Qt uses uppercase
				continue
			}
			return 0, fmt.Errorf("unknown key: %s", p)
		}
	}
	if key == 0 {
		return 0, fmt.Errorf("no key found in hotkey: %s", hotkey)
	}
	return mods | key, nil
}

// registerKGlobalAccel registers a global shortcut via KDE's kglobalaccel D-Bus
// service and listens for activation signals.
func registerKGlobalAccel(hotkey string) (<-chan struct{}, error) {
	keyCode, err := qtKeyCode(hotkey)
	if err != nil {
		return nil, fmt.Errorf("parse hotkey: %w", err)
	}
	logging.Info("kglobalaccel: hotkey=%s keyCode=0x%08X", hotkey, keyCode)

	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return nil, fmt.Errorf("connect session bus: %w", err)
	}

	kga := conn.Object("org.kde.kglobalaccel", "/kglobalaccel")

	// actionId = [componentUnique, componentFriendly, actionUnique, actionFriendly]
	actionID := []string{"karchy", "Karchy", "toggle-menu", "Toggle Karchy Menu"}

	// Register the action
	err = kga.Call("org.kde.KGlobalAccel.doRegister", 0, actionID).Err
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("doRegister: %w", err)
	}
	logging.Info("kglobalaccel: action registered")

	// Set the shortcut (flags=2 means SetPresent — set without prompting)
	var result []int32
	err = kga.Call("org.kde.KGlobalAccel.setShortcut", 0,
		actionID, []int32{keyCode}, uint32(2)).Store(&result)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("setShortcut: %w", err)
	}
	logging.Info("kglobalaccel: shortcut set, result=%v", result)

	// Listen for globalShortcutPressed on the component path
	componentPath := dbus.ObjectPath("/component/karchy")
	conn.BusObject().Call("org.freedesktop.DBus.AddMatch", 0,
		fmt.Sprintf("type='signal',sender='org.kde.kglobalaccel',path='%s',interface='org.kde.kglobalaccel.Component',member='globalShortcutPressed'", componentPath))

	signalCh := make(chan *dbus.Signal, 10)
	conn.Signal(signalCh)

	activatedCh := make(chan struct{}, 1)
	go func() {
		for sig := range signalCh {
			if sig.Name == "org.kde.kglobalaccel.Component.globalShortcutPressed" {
				logging.Info("kglobalaccel: shortcut pressed: %v", sig.Body)
				select {
				case activatedCh <- struct{}{}:
				default:
				}
			}
		}
	}()

	return activatedCh, nil
}
