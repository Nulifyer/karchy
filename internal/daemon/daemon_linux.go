//go:build linux

package daemon

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"fyne.io/systray"
	"github.com/godbus/dbus/v5"
	"github.com/nulifyer/karchy/assets"
	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/actions/install"
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

// trayActionCh receives tray menu actions on the daemon's main loop.
var trayActionCh = make(chan string, 1)

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

	// Start system tray icon
	var mUpdate *systray.MenuItem
	start, stop := systray.RunWithExternalLoop(func() {
		systray.SetTitle("Karchy")
		systray.SetTooltip("Karchy Daemon")
		systray.SetIcon(assets.IconPNG)
		logging.Info("daemon: tray ready")

		mUpdate = systray.AddMenuItem("System Update", "Install available updates")
		mUpdate.Hide()
		mOpen := systray.AddMenuItem("Open Karchy", "Open the Karchy menu")
		systray.AddSeparator()
		mRestart := systray.AddMenuItem("Restart Daemon", "Restart the Karchy daemon")
		mQuit := systray.AddMenuItem("Quit", "Stop the Karchy daemon")

		go func() {
			for {
				select {
				case <-mUpdate.ClickedCh:
					trayActionCh <- "update"
				case <-mOpen.ClickedCh:
					trayActionCh <- "open"
				case <-mRestart.ClickedCh:
					trayActionCh <- "restart"
				case <-mQuit.ClickedCh:
					trayActionCh <- "quit"
				}
			}
		}()
	}, func() {
		logging.Info("daemon: tray exited")
	})
	start()
	defer stop()

	// Start periodic update checker
	updateCh := make(chan int, 1)
	go updateChecker(updateCh)

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
		case count := <-updateCh:
			if count > 0 {
				logging.Info("daemon: %d updates available", count)
				systray.SetTooltip(fmt.Sprintf("Karchy Daemon - %d update(s) available", count))
				systray.SetIcon(iconWithBadge())
				mUpdate.SetTitle(fmt.Sprintf("System Update (%d)", count))
				mUpdate.Show()
			} else {
				systray.SetTooltip("Karchy Daemon")
				systray.SetIcon(assets.IconPNG)
				mUpdate.Hide()
			}
		case action := <-trayActionCh:
			switch action {
			case "update":
				logging.Info("daemon: tray update clicked")
				pid := install.SystemUpdate()
				// Wait for the update terminal to close, then refresh the tray
				if pid > 0 {
					go func() {
						if p, err := os.FindProcess(pid); err == nil {
							p.Wait()
						}
						checkUpdates(updateCh)
					}()
				}
			case "open":
				logging.Info("daemon: tray open clicked")
				launchMenu()
			case "restart":
				logging.Info("daemon: tray restart clicked")
				Restart()
				return
			case "quit":
				logging.Info("daemon: tray quit clicked")
				return
			}
		case <-sigCh:
			logging.Info("daemon: received signal, shutting down")
			return
		}
	}
}

// updateChecker periodically checks for available system updates.
func updateChecker(ch chan<- int) {
	// Check immediately on startup
	checkUpdates(ch)
	// Then check every hour
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()
	for range ticker.C {
		checkUpdates(ch)
	}
}

// checkUpdates runs checkupdates and sends the count to the channel.
func checkUpdates(ch chan<- int) {
	out, err := exec.Command("checkupdates").Output()
	if err != nil {
		// checkupdates exits 2 when no updates, 1 on error
		logging.Info("daemon: checkupdates: %v", err)
		select {
		case ch <- 0:
		default:
		}
		return
	}
	count := 0
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		if line != "" {
			count++
		}
	}
	select {
	case ch <- count:
	default:
	}
}

// iconWithBadge returns the tray icon PNG with an orange notification dot.
func iconWithBadge() []byte {
	src, err := png.Decode(bytes.NewReader(assets.IconPNG))
	if err != nil {
		return assets.IconPNG
	}
	bounds := src.Bounds()
	img := image.NewRGBA(bounds)
	draw.Draw(img, bounds, src, bounds.Min, draw.Src)

	// Draw a 10px orange circle in the top-right corner
	orange := color.RGBA{R: 255, G: 140, B: 0, A: 255}
	cx, cy, r := bounds.Max.X-6, bounds.Min.Y+6, 5
	for y := cy - r; y <= cy+r; y++ {
		for x := cx - r; x <= cx+r; x++ {
			dx, dy := x-cx, y-cy
			if dx*dx+dy*dy <= r*r {
				img.Set(x, y, orange)
			}
		}
	}

	var buf bytes.Buffer
	png.Encode(&buf, img)
	return buf.Bytes()
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
			if len(lower) >= 2 && lower[0] == 'f' {
				if n, err := strconv.Atoi(lower[1:]); err == nil && n >= 1 && n <= 12 {
					key = int32(0x01000030 + n - 1)
					continue
				}
			}
			if len(lower) == 1 && lower[0] >= 'a' && lower[0] <= 'z' {
				key = int32(lower[0] - 'a' + 'A')
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

	actionID := []string{"karchy", "Karchy", "toggle-menu", "Toggle Karchy Menu"}

	err = kga.Call("org.kde.KGlobalAccel.doRegister", 0, actionID).Err
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("doRegister: %w", err)
	}
	logging.Info("kglobalaccel: action registered")

	var result []int32
	err = kga.Call("org.kde.KGlobalAccel.setShortcut", 0,
		actionID, []int32{keyCode}, uint32(2)).Store(&result)
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("setShortcut: %w", err)
	}
	logging.Info("kglobalaccel: shortcut set, result=%v", result)

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
