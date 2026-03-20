//go:build windows

package daemon

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"github.com/nulifyer/karchy/assets"
	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/selfupdate"
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
	procSetForegroundWindow      = user32.NewProc("SetForegroundWindow")
	procAllowSetForegroundWindow = user32.NewProc("AllowSetForegroundWindow")
	procGetCursorPos             = user32.NewProc("GetCursorPos")
	procRegisterWindowMessageW   = user32.NewProc("RegisterWindowMessageW")
	procSetTimer                 = user32.NewProc("SetTimer")
	procKillTimer                = user32.NewProc("KillTimer")
	procShellNotifyIconW         = shell32.NewProc("Shell_NotifyIconW")
)

const (
	mutexName          = "Global\\KarchyDaemon"
	errorAlreadyExists = 183

	wmDestroy          = 0x0002
	wmTimer            = 0x0113
	wmCommand          = 0x0111
	wmTrayIcon         = 0x8001 // WM_APP + 1
	wmLaunchMenu       = 0x8003 // WM_APP + 3 — posted by hook to trigger launch on msg thread
	wsOverlappedWindow = 0x00CF0000

	// WM_TIMER IDs for menu window polling (all on the message thread, no goroutines)
	timerIDMenuPoll  = 1 // fires every 50ms until Alacritty window is detected
	timerIDMenuFocus = 2 // fires once 300ms after window detected, to focus it

	// Low-level keyboard hook
	whKeyboardLL = 13
	wmKeyDown    = 0x0100
	wmKeyUp      = 0x0101
	wmSysKeyDown = 0x0104
	wmSysKeyUp   = 0x0105

	// Power broadcast
	wmPowerBroadcast      = 0x0218
	pbtApmResumeAutomatic = 0x0012 // fired on any resume (S3/S4/hibernate)
	pbtApmResumeSuspend   = 0x0007 // fired when user-initiated resume

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
	nimModify  = 0x01
	nimDelete  = 0x02
	nifIcon    = 0x02
	nifMessage = 0x01
	nifTip     = 0x04

	mfString       = 0x00
	tpmBottomAlign = 0x0020
	tpmLeftAlign   = 0x0000
	tpmRightButton = 0x0002
	idmOpen        = 1001
	idmSelfUpdate  = 1002
	idmExit        = 1004

	// MF_SEPARATOR for popup menus
	mfSeparator = 0x0800

	imageIcon      = 1
	lrLoadFromFile = 0x00000010
	idiApplication = 32512
)

// Hotkey state
var (
	trayHwnd         uintptr
	hookHandle       uintptr
	targetMod        uint32 // VK code for modifier (e.g. vkLWin)
	targetKey        uint32 // VK code for key (e.g. vkSpace)
	menuPID          int    // PID of the Alacritty popup (0 = not running)
	menuTimerAttempts int   // poll attempts for timerIDMenuPoll
	selfUpdateVer    string // newer karchy version available (empty if up to date)
	wmTaskbarCreated uint32 // registered message ID for "TaskbarCreated"
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

var (
	procGetConsoleWindow = kernel32.NewProc("GetConsoleWindow")
	procShowWindow       = user32.NewProc("ShowWindow")
)

// hideConsole hides the console window of the current process.
// Called by daemon start so the brief startup window is invisible.
func hideConsole() {
	hwnd, _, _ := procGetConsoleWindow.Call()
	if hwnd != 0 {
		procShowWindow.Call(hwnd, 0) // SW_HIDE
	}
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

	// Parse config
	cfg := config.Load()
	parseHotkey(cfg.Hotkey.Toggle)
	terminal.SetMonitorBehavior(terminal.ParseMonitorBehavior(cfg.Window.SummonOn))

	// Register "TaskbarCreated" so we can re-add the tray icon if Explorer restarts
	tcStr, _ := syscall.UTF16PtrFromString("TaskbarCreated")
	r, _, _ := procRegisterWindowMessageW.Call(uintptr(unsafe.Pointer(tcStr)))
	wmTaskbarCreated = uint32(r)

	// Create tray window + icon
	createTrayIcon()

	// Install low-level keyboard hook
	installHook()

	// Start periodic self-update checker
	go func() {
		checkSelfUpdate()
		ticker := time.NewTicker(1 * time.Hour)
		defer ticker.Stop()
		for range ticker.C {
			checkSelfUpdate()
		}
	}()

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
		hookHandle = 0
	}
	removeTrayIcon()
}

// installHook installs the low-level keyboard hook.
func installHook() {
	hookHandle, _, _ = procSetWindowsHookExW.Call(whKeyboardLL, syscall.NewCallback(keyboardProc), 0, 0)
	if hookHandle == 0 {
		logging.Info("installHook: SetWindowsHookEx failed")
	} else {
		logging.Info("installHook: hook installed mod=0x%x key=0x%x", targetMod, targetKey)
	}
}

// reinstallHook removes the existing hook and installs a fresh one.
// Called after sleep/resume or Explorer restart when the hook may have gone stale.
func reinstallHook() {
	if hookHandle != 0 {
		procUnhookWindowsHookEx.Call(hookHandle)
		hookHandle = 0
	}
	installHook()
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

	tip := "Karchy"
	for i, ch := range tip {
		if i >= 127 {
			break
		}
		nid.SzTip[i] = uint16(ch)
	}

	procShellNotifyIconW.Call(nimAdd, uintptr(unsafe.Pointer(&nid)))
}

func loadTrayIcon() uintptr {
	// Write the embedded ICO to a cache file so LoadImageW can load it.
	dir, err := os.UserCacheDir()
	if err != nil {
		return 0
	}
	icoPath := filepath.Join(dir, "karchy", "karchy.ico")
	os.MkdirAll(filepath.Dir(icoPath), 0o755)
	if err := os.WriteFile(icoPath, assets.IconICO, 0o644); err != nil {
		return 0
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

// readdTrayIcon re-adds the tray icon after Explorer restarts (TaskbarCreated).
// The window already exists; we just need Shell_NotifyIconW(NIM_ADD) again.
func readdTrayIcon() {
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
	tip := "Karchy"
	for i, ch := range tip {
		if i >= 127 {
			break
		}
		nid.SzTip[i] = uint16(ch)
	}
	procShellNotifyIconW.Call(nimAdd, uintptr(unsafe.Pointer(&nid)))
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
	// TaskbarCreated is a dynamically registered message — check before the switch.
	// Fired when Explorer restarts; the tray icon is lost and the hook may be stale.
	if wmTaskbarCreated != 0 && umsg == wmTaskbarCreated {
		logging.Info("trayWndProc: TaskbarCreated, re-registering tray icon and hook")
		readdTrayIcon()
		reinstallHook()
		return 0
	}

	switch umsg {
	case wmPowerBroadcast:
		if wParam == pbtApmResumeAutomatic || wParam == pbtApmResumeSuspend {
			logging.Info("trayWndProc: power resume (wParam=0x%x), reinstalling hook", wParam)
			reinstallHook()
		}
		return 0

	case wmTrayIcon:
		event := uint32(lParam & 0xFFFF)
		if event == 0x0205 || event == 0x0202 { // WM_RBUTTONUP, WM_LBUTTONUP
			showContextMenu(hwnd)
		}
		return 0

	case wmTimer:
		switch wParam {
		case timerIDMenuPoll:
			if terminal.HasVisibleWindow(menuPID) {
				procKillTimer.Call(trayHwnd, timerIDMenuPoll)
				menuTimerAttempts = 0
				procSetTimer.Call(trayHwnd, timerIDMenuFocus, 300, 0)
			} else {
				menuTimerAttempts++
				if menuTimerAttempts >= 40 { // 2 s timeout
					procKillTimer.Call(trayHwnd, timerIDMenuPoll)
					menuTimerAttempts = 0
					logging.Info("wmTimer: menu window not found after timeout pid=%d", menuPID)
				}
			}
		case timerIDMenuFocus:
			procKillTimer.Call(trayHwnd, timerIDMenuFocus)
			hwnd := terminal.FindAndCenterByPID(menuPID)
			if hwnd == 0 {
				logging.Info("wmTimer: window gone before focus pid=%d", menuPID)
				return 0
			}
			r1, _, e1 := procSetForegroundWindow.Call(hwnd)
			logging.Info("wmTimer: SetForegroundWindow hwnd=%x ret=%d err=%v", hwnd, r1, e1)
			terminal.FocusHwnd(hwnd)
			logging.Info("wmTimer: FocusHwnd complete hwnd=%x pid=%d", hwnd, menuPID)
		}
		return 0

	case wmLaunchMenu:
		// Make the daemon the foreground process NOW, while we still hold
		// foreground rights from the keyboard hook intercept. This keeps us
		// foreground until the timer fires and we explicitly hand off to Alacritty.
		procSetForegroundWindow.Call(trayHwnd)
		// Cancel any in-flight timers from a previous launch.
		procKillTimer.Call(trayHwnd, timerIDMenuPoll)
		procKillTimer.Call(trayHwnd, timerIDMenuFocus)
		menuTimerAttempts = 0
		// Kill existing popup so a fresh one takes focus cleanly.
		if menuPID != 0 {
			if p, err := os.FindProcess(menuPID); err == nil {
				p.Kill()
				logging.Info("wmLaunchMenu: killed existing pid=%d", menuPID)
			}
			menuPID = 0
		}
		launchMenu()
		// Poll on the message thread via WM_TIMER — no goroutine.
		procSetTimer.Call(trayHwnd, timerIDMenuPoll, 50, 0)
		return 0

	case wmCommand:
		id := uint16(wParam & 0xFFFF)
		switch id {
		case idmOpen:
			go launchMenu()
		case idmSelfUpdate:
			go func() {
				exePath, _ := os.Executable()
				// Launch in a visible terminal so the user sees progress;
				// "karchy update self" handles daemon restart internally.
				script := fmt.Sprintf(`"%s" update self & pause`, exePath)
				terminal.LaunchShell(80, 20, "Karchy Update", script)
			}()
		case idmExit:
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

	openText, _ := syscall.UTF16PtrFromString("Open Karchy")
	procAppendMenuW.Call(menu, mfString, idmOpen, uintptr(unsafe.Pointer(openText)))

	if selfUpdateVer != "" {
		updateText, _ := syscall.UTF16PtrFromString(fmt.Sprintf("Update Karchy (%s)", selfUpdateVer))
		procAppendMenuW.Call(menu, mfString, idmSelfUpdate, uintptr(unsafe.Pointer(updateText)))
	}

	procAppendMenuW.Call(menu, mfSeparator, 0, 0)

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
			parts = append(parts, strings.ToLower(s[start:i]))
			start = i + 1
		}
	}
	parts = append(parts, strings.ToLower(s[start:]))
	return parts
}

// ── Launch ─────────────────────────────────────────────────────────────────

// launchMenu spawns the terminal process. Window polling and focus are handled
// on the message thread via WM_TIMER (timerIDMenuPoll / timerIDMenuFocus).
func launchMenu() {
	args := []string{}
	if logging.Enabled() {
		args = append(args, "--debug")
	}
	args = append(args, "menu")
	logging.Info("launchMenu: args=%v", args)

	pid, err := terminal.Launch(40, 14, "Karchy", args...)
	if err != nil {
		logging.Info("launchMenu: launch failed: %v", err)
		return
	}
	menuPID = pid
	logging.Info("launchMenu: pid=%d", pid)
}

func checkSelfUpdate() {
	if Version == "" || Version == "dev" {
		return
	}
	if v := selfupdate.CheckAvailable(Version); v != "" {
		selfUpdateVer = v
		logging.Info("daemon: karchy update available: %s", v)
		updateTrayTooltip(fmt.Sprintf("Karchy - %s available", v))
		updateTrayIcon(assets.IconBadgeICO)
	}
}

func updateTrayTooltip(tip string) {
	var nid notifyIconData
	nid.CbSize = uint32(unsafe.Sizeof(nid))
	nid.Hwnd = trayHwnd
	nid.UID = 1
	nid.UFlags = nifTip
	for i, ch := range tip {
		if i >= 127 {
			break
		}
		nid.SzTip[i] = uint16(ch)
	}
	procShellNotifyIconW.Call(nimModify, uintptr(unsafe.Pointer(&nid)))
}

func updateTrayIcon(icoData []byte) {
	dir, err := os.UserCacheDir()
	if err != nil {
		return
	}
	icoPath := filepath.Join(dir, "karchy", "karchy-tray.ico")
	os.MkdirAll(filepath.Dir(icoPath), 0o755)
	if err := os.WriteFile(icoPath, icoData, 0o644); err != nil {
		return
	}
	pathPtr, _ := syscall.UTF16PtrFromString(icoPath)
	icon, _, _ := procLoadImageW.Call(
		0,
		uintptr(unsafe.Pointer(pathPtr)),
		imageIcon,
		16, 16,
		lrLoadFromFile,
	)
	if icon == 0 {
		return
	}
	var nid notifyIconData
	nid.CbSize = uint32(unsafe.Sizeof(nid))
	nid.Hwnd = trayHwnd
	nid.UID = 1
	nid.UFlags = nifIcon
	nid.HIcon = icon
	procShellNotifyIconW.Call(nimModify, uintptr(unsafe.Pointer(&nid)))
}
