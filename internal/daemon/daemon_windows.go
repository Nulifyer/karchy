//go:build windows

package daemon

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"
	"unsafe"

	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
)

var (
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	user32   = syscall.NewLazyDLL("user32.dll")
	shell32  = syscall.NewLazyDLL("shell32.dll")

	procCreateMutex  = kernel32.NewProc("CreateMutexW")
	procOpenMutex    = kernel32.NewProc("OpenMutexW")
	procCloseHandle  = kernel32.NewProc("CloseHandle")
	procReleaseMutex = kernel32.NewProc("ReleaseMutex")
	procGetLastError = kernel32.NewProc("GetLastError")

	procRegisterClassW           = user32.NewProc("RegisterClassW")
	procCreateWindowExW          = user32.NewProc("CreateWindowExW")
	procDefWindowProcW           = user32.NewProc("DefWindowProcW")
	procGetMessageW              = user32.NewProc("GetMessageW")
	procTranslateMessage         = user32.NewProc("TranslateMessage")
	procDispatchMessageW         = user32.NewProc("DispatchMessageW")
	procPostQuitMessage          = user32.NewProc("PostQuitMessage")
	procPostMessageW             = user32.NewProc("PostMessageW")
	procSetWindowsHookExW        = user32.NewProc("SetWindowsHookExW")
	procCallNextHookEx           = user32.NewProc("CallNextHookEx")
	procUnhookWindowsHookEx      = user32.NewProc("UnhookWindowsHookEx")
	procGetAsyncKeyState         = user32.NewProc("GetAsyncKeyState")
	procLoadIconW                = user32.NewProc("LoadIconW")
	procLoadImageW               = user32.NewProc("LoadImageW")
	procCreatePopupMenu          = user32.NewProc("CreatePopupMenu")
	procAppendMenuW              = user32.NewProc("AppendMenuW")
	procTrackPopupMenu           = user32.NewProc("TrackPopupMenu")
	procDestroyMenu              = user32.NewProc("DestroyMenu")
	procSetForegroundWindow         = user32.NewProc("SetForegroundWindow")
	procAllowSetForegroundWindow    = user32.NewProc("AllowSetForegroundWindow")
	procGetCursorPos                = user32.NewProc("GetCursorPos")
	procShellNotifyIconW = shell32.NewProc("Shell_NotifyIconW")
)

const (
	mutexName          = "Global\\KarchyDaemon"
	errorAlreadyExists = 183

	wmDestroy          = 0x0002
	wmCommand          = 0x0111
	wmTrayIcon         = 0x8001 // WM_APP + 1
	wmFocusMenu        = 0x8002 // WM_APP + 2 — posted by goroutine to focus on msg thread
	wmLaunchMenu       = 0x8003 // WM_APP + 3 — posted by hook to trigger launch on msg thread
	wsOverlappedWindow = 0x00CF0000

	// Low-level keyboard hook
	whKeyboardLL = 13
	wmKeyDown    = 0x0100
	wmKeyUp      = 0x0101
	wmSysKeyDown = 0x0104
	wmSysKeyUp   = 0x0105

	// Virtual key codes
	vkSpace    = 0x20
	vkLWin     = 0x5B
	vkRWin     = 0x5C
	vkLMenu    = 0xA4 // Left Alt
	vkRMenu    = 0xA5 // Right Alt
	vkLControl = 0xA2
	vkRControl = 0xA3
	vkLShift   = 0xA0
	vkRShift   = 0xA1

	nimAdd     = 0x00
	nimDelete  = 0x02
	nifIcon    = 0x02
	nifMessage = 0x01
	nifTip     = 0x04

	mfString       = 0x00
	tpmBottomAlign = 0x0020
	tpmLeftAlign   = 0x0000
	tpmRightButton = 0x0002
	idmExit        = 1001

	imageIcon      = 1
	lrLoadFromFile = 0x00000010
	idiApplication = 32512
)

// Hotkey state
var (
	trayHwnd   uintptr
	hookHandle uintptr
	targetMod  uint32 // VK code for modifier (e.g. vkLWin)
	targetKey  uint32 // VK code for key (e.g. vkSpace)
	menuPID    int    // PID of the Alacritty popup (0 = not running)
)

// KBDLLHOOKSTRUCT
type kbdllHookStruct struct {
	VkCode      uint32
	ScanCode    uint32
	Flags       uint32
	Time        uint32
	DwExtraInfo uintptr
}

type point struct{ X, Y int32 }

type msg struct {
	Hwnd    uintptr
	Message uint32
	WParam  uintptr
	LParam  uintptr
	Time    uint32
	Pt      point
}

type wndClass struct {
	Style      uint32
	WndProc    uintptr
	ClsExtra   int32
	WndExtra   int32
	Instance   uintptr
	Icon       uintptr
	Cursor     uintptr
	Background uintptr
	MenuName   *uint16
	ClassName  *uint16
}

// NOTIFYICONDATAW — full Win32 struct is 956 bytes on 64-bit.
// We define up through szTip and pad to the correct total size.
type notifyIconData struct {
	CbSize           uint32
	Hwnd             uintptr
	UID              uint32
	UFlags           uint32
	UCallbackMessage uint32
	HIcon            uintptr
	SzTip            [128]uint16
	_pad             [444]byte
}

func isRunning() bool {
	name, _ := syscall.UTF16PtrFromString(mutexName)
	h, _, _ := procOpenMutex.Call(0x00100000, 0, uintptr(unsafe.Pointer(name)))
	if h != 0 {
		procCloseHandle.Call(h)
		return true
	}
	return false
}

func pidFilePath() string {
	dir, err := os.UserConfigDir()
	if err != nil {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "karchy", "daemon.pid")
}

func writePIDFile() {
	path := pidFilePath()
	os.MkdirAll(filepath.Dir(path), 0o755)
	os.WriteFile(path, []byte(fmt.Sprintf("%d", os.Getpid())), 0o644)
}

func removePIDFile() {
	os.Remove(pidFilePath())
}

func stopDaemon() {
	data, err := os.ReadFile(pidFilePath())
	if err != nil {
		return
	}
	pid := 0
	fmt.Sscan(string(data), &pid)
	if pid == 0 {
		return
	}
	proc, err := os.FindProcess(pid)
	if err != nil {
		return
	}
	_ = proc.Kill()
	os.Remove(pidFilePath())
}

func hideProcess(cmd *exec.Cmd) {
	cmd.SysProcAttr = &syscall.SysProcAttr{
		CreationFlags: 0x08000000,
	}
}

func run() {
	// Single-instance mutex
	name, _ := syscall.UTF16PtrFromString(mutexName)
	h, _, _ := procCreateMutex.Call(0, 1, uintptr(unsafe.Pointer(name)))
	if h == 0 {
		fmt.Println("Failed to create mutex")
		os.Exit(1)
	}
	lastErr, _, _ := procGetLastError.Call()
	if lastErr == errorAlreadyExists {
		fmt.Println("Daemon already running")
		os.Exit(0)
	}
	defer procReleaseMutex.Call(h)
	defer procCloseHandle.Call(h)

	writePIDFile()
	defer removePIDFile()

	// Parse hotkey
	cfg := config.Load()
	parseHotkey(cfg.Hotkey.Toggle)

	// Create tray window + icon
	createTrayIcon()

	// Install low-level keyboard hook
	hookHandle, _, _ = procSetWindowsHookExW.Call(whKeyboardLL, syscall.NewCallback(keyboardProc), 0, 0)
	if hookHandle == 0 {
		logging.Info("SetWindowsHookEx failed")
	} else {
		logging.Info("LL keyboard hook installed mod=0x%x key=0x%x", targetMod, targetKey)
	}

	fmt.Println("Karchy daemon started.")

	// Message loop
	var m msg
	for {
		r, _, _ := procGetMessageW.Call(uintptr(unsafe.Pointer(&m)), 0, 0, 0)
		if r == 0 || r == uintptr(^uintptr(0)) {
			break
		}
		procTranslateMessage.Call(uintptr(unsafe.Pointer(&m)))
		procDispatchMessageW.Call(uintptr(unsafe.Pointer(&m)))
	}

	if hookHandle != 0 {
		procUnhookWindowsHookEx.Call(hookHandle)
	}
	removeTrayIcon()
}

// keyboardProc is the low-level keyboard hook callback.
func keyboardProc(nCode int32, wParam uintptr, lParam uintptr) uintptr {
	if nCode >= 0 {
		kb := (*kbdllHookStruct)(unsafe.Pointer(lParam))
		if wParam == wmKeyDown || wParam == wmSysKeyDown {
			if kb.VkCode == targetKey && isModDown(targetMod) {
				// Post message to our window so launchMenu runs on the message thread
				procPostMessageW.Call(trayHwnd, wmLaunchMenu, 0, 0)
				// Send a dummy key-up to prevent Start Menu from activating (PowerToys technique)
				sendDummyKeyUp()
				return 1 // swallow the key
			}
		}
	}
	ret, _, _ := procCallNextHookEx.Call(hookHandle, uintptr(nCode), wParam, lParam)
	return ret
}

// isModDown checks if the target modifier key is currently held.
func isModDown(vk uint32) bool {
	// Check both left and right variants
	switch vk {
	case vkLWin:
		stL, _, _ := procGetAsyncKeyState.Call(uintptr(vkLWin))
		stR, _, _ := procGetAsyncKeyState.Call(uintptr(vkRWin))
		return (stL&0x8000) != 0 || (stR&0x8000) != 0
	case vkLMenu:
		stL, _, _ := procGetAsyncKeyState.Call(uintptr(vkLMenu))
		stR, _, _ := procGetAsyncKeyState.Call(uintptr(vkRMenu))
		return (stL&0x8000) != 0 || (stR&0x8000) != 0
	case vkLControl:
		stL, _, _ := procGetAsyncKeyState.Call(uintptr(vkLControl))
		stR, _, _ := procGetAsyncKeyState.Call(uintptr(vkRControl))
		return (stL&0x8000) != 0 || (stR&0x8000) != 0
	case vkLShift:
		stL, _, _ := procGetAsyncKeyState.Call(uintptr(vkLShift))
		stR, _, _ := procGetAsyncKeyState.Call(uintptr(vkRShift))
		return (stL&0x8000) != 0 || (stR&0x8000) != 0
	}
	st, _, _ := procGetAsyncKeyState.Call(uintptr(vk))
	return (st & 0x8000) != 0
}

// sendDummyKeyUp sends a dummy key-up event to prevent the Start Menu from
// activating when we swallow a Win+key combo (same technique as PowerToys).
func sendDummyKeyUp() {
	type keyInput struct {
		Type        uint32
		_           uint32
		Vk          uint16
		Scan        uint16
		Flags       uint32
		Time        uint32
		DwExtraInfo uintptr
		_           [8]byte // pad to 40 bytes
	}
	input := keyInput{
		Type:  1, // INPUT_KEYBOARD
		Vk:    0xFF,
		Flags: 0x0002, // KEYEVENTF_KEYUP
	}
	procSendInput := user32.NewProc("SendInput")
	procSendInput.Call(1, uintptr(unsafe.Pointer(&input)), 40)
}

// ── Tray Icon ──────────────────────────────────────────────────────────────

func createTrayIcon() {
	className, _ := syscall.UTF16PtrFromString("KarchyTray")

	wc := wndClass{
		WndProc:   syscall.NewCallback(trayWndProc),
		ClassName: className,
	}
	procRegisterClassW.Call(uintptr(unsafe.Pointer(&wc)))

	// Use a normal hidden window (not HWND_MESSAGE) — Shell_NotifyIcon needs it
	trayHwnd, _, _ = procCreateWindowExW.Call(
		0,
		uintptr(unsafe.Pointer(className)),
		uintptr(unsafe.Pointer(className)),
		wsOverlappedWindow,
		0, 0, 0, 0,
		0, 0, 0, 0,
	)
	if trayHwnd == 0 {
		fmt.Println("Failed to create tray window")
		return
	}

	// Load icon from karchy.ico next to the exe, fall back to default app icon
	icon := loadTrayIcon()
	if icon == 0 {
		icon, _, _ = procLoadIconW.Call(0, idiApplication)
	}

	var nid notifyIconData
	nid.CbSize = uint32(unsafe.Sizeof(nid))
	nid.Hwnd = trayHwnd
	nid.UID = 1
	nid.UFlags = nifIcon | nifMessage | nifTip
	nid.UCallbackMessage = wmTrayIcon
	nid.HIcon = icon

	tip := "Karchy Daemon"
	for i, ch := range tip {
		if i >= 127 {
			break
		}
		nid.SzTip[i] = uint16(ch)
	}

	procShellNotifyIconW.Call(nimAdd, uintptr(unsafe.Pointer(&nid)))
}

func loadTrayIcon() uintptr {
	// Look for karchy.ico next to the executable
	exePath, err := os.Executable()
	if err != nil {
		return 0
	}
	icoPath := filepath.Join(filepath.Dir(exePath), "assets", "karchy.ico")
	if _, err := os.Stat(icoPath); err != nil {
		// Also try same directory as exe
		icoPath = filepath.Join(filepath.Dir(exePath), "karchy.ico")
		if _, err := os.Stat(icoPath); err != nil {
			return 0
		}
	}
	pathPtr, _ := syscall.UTF16PtrFromString(icoPath)
	icon, _, _ := procLoadImageW.Call(
		0,
		uintptr(unsafe.Pointer(pathPtr)),
		imageIcon,
		16, 16,
		lrLoadFromFile,
	)
	return icon
}

func removeTrayIcon() {
	if trayHwnd == 0 {
		return
	}
	var nid notifyIconData
	nid.CbSize = uint32(unsafe.Sizeof(nid))
	nid.Hwnd = trayHwnd
	nid.UID = 1
	procShellNotifyIconW.Call(nimDelete, uintptr(unsafe.Pointer(&nid)))
}

func trayWndProc(hwnd uintptr, umsg uint32, wParam, lParam uintptr) uintptr {
	switch umsg {
	case wmTrayIcon:
		event := uint32(lParam & 0xFFFF)
		if event == 0x0205 || event == 0x0202 { // WM_RBUTTONUP, WM_LBUTTONUP
			showContextMenu(hwnd)
		}
		return 0

	case wmLaunchMenu:
		// Kill existing popup so a fresh one takes focus cleanly
		if menuPID != 0 {
			if p, err := os.FindProcess(menuPID); err == nil {
				p.Kill()
				logging.Info("wmLaunchMenu: killed existing pid=%d", menuPID)
			}
			menuPID = 0
		}
		go launchMenu()
		return 0

	case wmFocusMenu:
		// wParam = hwnd to focus. Called on the message thread so SendInput works.
		terminal.FocusHwnd(uintptr(wParam))
		logging.Info("wmFocusMenu: focused hwnd=%x", wParam)
		return 0

	case wmCommand:
		id := uint16(wParam & 0xFFFF)
		if id == idmExit {
			removeTrayIcon()
			procPostQuitMessage.Call(0)
		}
		return 0

	case wmDestroy:
		removeTrayIcon()
		procPostQuitMessage.Call(0)
		return 0
	}

	ret, _, _ := procDefWindowProcW.Call(hwnd, uintptr(umsg), wParam, lParam)
	return ret
}

func showContextMenu(hwnd uintptr) {
	menu, _, _ := procCreatePopupMenu.Call()
	if menu == 0 {
		return
	}

	exitText, _ := syscall.UTF16PtrFromString("Exit Karchy")
	procAppendMenuW.Call(menu, mfString, idmExit, uintptr(unsafe.Pointer(exitText)))

	var pt point
	procGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))

	procSetForegroundWindow.Call(hwnd)
	procTrackPopupMenu.Call(
		menu,
		tpmBottomAlign|tpmLeftAlign|tpmRightButton,
		uintptr(pt.X), uintptr(pt.Y),
		0, hwnd, 0,
	)
	procDestroyMenu.Call(menu)
}

// ── Hotkey Parsing ─────────────────────────────────────────────────────────

func parseHotkey(s string) {
	targetMod = vkLWin
	targetKey = vkSpace

	parts := splitHotkey(s)
	if len(parts) < 2 {
		return
	}

	switch parts[0] {
	case "super", "win", "cmd", "command":
		targetMod = vkLWin
	case "alt", "option":
		targetMod = vkLMenu
	case "ctrl", "control":
		targetMod = vkLControl
	case "shift":
		targetMod = vkLShift
	}

	key := parts[len(parts)-1]
	switch key {
	case "space":
		targetKey = vkSpace
	default:
		if len(key) == 1 && key[0] >= 'a' && key[0] <= 'z' {
			targetKey = uint32(key[0] - 'a' + 'A')
		}
	}
}

func splitHotkey(s string) []string {
	var parts []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '+' {
			parts = append(parts, lower(s[start:i]))
			start = i + 1
		}
	}
	parts = append(parts, lower(s[start:]))
	return parts
}

func lower(s string) string {
	b := make([]byte, len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c >= 'A' && c <= 'Z' {
			c += 'a' - 'A'
		}
		b[i] = c
	}
	return string(b)
}

// ── Launch ─────────────────────────────────────────────────────────────────

func launchMenu() {
	args := []string{}
	if logging.Enabled() {
		args = append(args, "--debug")
	}
	args = append(args, "menu")
	logging.Info("launchMenu: args=%v", args)

	// Grant any process the right to set foreground (we have rights from WM_HOTKEY).
	procAllowSetForegroundWindow.Call(^uintptr(0)) // ASFW_ANY = -1

	pid, err := terminal.Launch(40, 14, "Karchy", args...)
	if err != nil {
		return
	}
	menuPID = pid

	// Poll for the window, center it, then post focus to the message thread.
	// Running in a goroutine so the message loop keeps pumping.
	var hwnd uintptr
	for i := 0; i < 20; i++ {
		time.Sleep(50 * time.Millisecond)
		hwnd = terminal.FindAndCenterByPID(pid)
		if hwnd != 0 {
			logging.Info("launchMenu: centered pid=%d attempt=%d", pid, i)
			break
		}
	}
	if hwnd == 0 {
		logging.Info("launchMenu: window not found after polling pid=%d", pid)
		return
	}

	// Wait for Alacritty to finish init, then post focus to message thread
	time.Sleep(300 * time.Millisecond)
	procPostMessageW.Call(trayHwnd, wmFocusMenu, hwnd, 0)
	logging.Info("launchMenu: posted focus for pid=%d hwnd=%x", pid, hwnd)
}
