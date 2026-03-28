//go:build windows

package terminal

import (
	"os"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"

	"github.com/nulifyer/karchy/internal/logging"
)

var (
	kernel32 = syscall.NewLazyDLL("kernel32.dll")
	user32   = syscall.NewLazyDLL("user32.dll")

	procGetCurrentThreadId       = kernel32.NewProc("GetCurrentThreadId")
	procGetWindowRect            = user32.NewProc("GetWindowRect")
	procSetWindowPos             = user32.NewProc("SetWindowPos")
	procShowWindow               = user32.NewProc("ShowWindow")
	procEnumWindows              = user32.NewProc("EnumWindows")
	procGetWindowThreadProcessId = user32.NewProc("GetWindowThreadProcessId")
	procIsWindowVisible          = user32.NewProc("IsWindowVisible")
	procSendInput                = user32.NewProc("SendInput")
	procGetSystemMetrics         = user32.NewProc("GetSystemMetrics")
	procGetCursorPos             = user32.NewProc("GetCursorPos")
	procGetForegroundWindow      = user32.NewProc("GetForegroundWindow")
	procSetForegroundWindow      = user32.NewProc("SetForegroundWindow")
	procAttachThreadInput        = user32.NewProc("AttachThreadInput")
	procSetActiveWindow          = user32.NewProc("SetActiveWindow")
	procSetFocus                 = user32.NewProc("SetFocus")
	procMonitorFromPoint         = user32.NewProc("MonitorFromPoint")
	procMonitorFromWindow        = user32.NewProc("MonitorFromWindow")
	procGetMonitorInfoW          = user32.NewProc("GetMonitorInfoW")
	procGetWindowTextW           = user32.NewProc("GetWindowTextW")

	procOpenFileMappingW = kernel32.NewProc("OpenFileMappingW")
	procMapViewOfFile    = kernel32.NewProc("MapViewOfFile")
	procUnmapViewOfFile  = kernel32.NewProc("UnmapViewOfFile")
)

const (
	swpNoSize     = 0x0001
	swpNoMove     = 0x0002
	swpShowWindow = 0x0040

	hwndTopmost = ^uintptr(0) // HWND_TOPMOST = -1
	swShow      = 5          // SW_SHOW

	monitorDefaultToNearest = 0x00000002
	monitorDefaultToPrimary = 0x00000001

	// SM_ indices for virtual screen bounds (multi-monitor)
	smXVirtualScreen  = 76
	smYVirtualScreen  = 77
	smCXVirtualScreen = 78
	smCYVirtualScreen = 79

	sizeofInput = 40 // sizeof(INPUT) on 64-bit Windows
)

type rect struct {
	Left, Top, Right, Bottom int32
}

func (r rect) Width() int  { return int(r.Right - r.Left) }
func (r rect) Height() int { return int(r.Bottom - r.Top) }

type point struct{ X, Y int32 }

// monitorInfo mirrors MONITORINFO (Win32).
type monitorInfo struct {
	CbSize    uint32
	RcMonitor rect
	RcWork    rect
	DwFlags   uint32
}

const (
	hwndShmName = `Local\KarchyHwnd`
	fileMapRead = 0x0004
)

// readHwndShm reads the terminal HWND from shared memory written by the menuhost.
// Returns 0 if the mapping does not exist or has not been written yet.
func readHwndShm() uintptr {
	namePtr, _ := syscall.UTF16PtrFromString(hwndShmName)
	h, _, _ := procOpenFileMappingW.Call(fileMapRead, 0, uintptr(unsafe.Pointer(namePtr)))
	if h == 0 {
		return 0
	}
	defer syscall.CloseHandle(syscall.Handle(h))
	addr, _, _ := procMapViewOfFile.Call(h, fileMapRead, 0, 0, 8)
	if addr == 0 {
		return 0
	}
	defer procUnmapViewOfFile.Call(addr)
	return *(*uintptr)(unsafe.Pointer(addr))
}

// capturedWorkArea holds the work area captured by the daemon at hotkey time.
// The menuhost writes it via SetCapturedWorkArea immediately after waking.
var (
	capturedWorkArea    rect
	capturedWorkAreaSet bool
)

// SetCapturedWorkArea stores the work area rect captured by the daemon at hotkey
// time. Called by the menuhost process after reading from shared memory.
func SetCapturedWorkArea(left, top, right, bottom int32) {
	capturedWorkArea = rect{left, top, right, bottom}
	capturedWorkAreaSet = true
}

// GetCurrentWorkAreaRect returns the work area of the configured target monitor,
// sampled right now. Called by the daemon in wmLaunchMenu (before SetForegroundWindow
// alters state) so the correct monitor is captured at hotkey time.
func GetCurrentWorkAreaRect() (left, top, right, bottom int32) {
	wa := workAreaForBehavior(activeBehavior)
	return wa.Left, wa.Top, wa.Right, wa.Bottom
}

// workAreaForBehavior returns the work area (screen minus taskbar) of the
// target monitor based on the configured MonitorBehavior.
func workAreaForBehavior(b MonitorBehavior) rect {
	var hmon uintptr

	switch b {
	case MonitorPrimary:
		// Primary monitor always contains virtual point (0,0).
		var pt point
		hmon, _, _ = procMonitorFromPoint.Call(
			uintptr(unsafe.Pointer(&pt)),
			monitorDefaultToPrimary,
		)
	case MonitorActiveWindow:
		fgWnd, _, _ := procGetForegroundWindow.Call()
		if fgWnd != 0 {
			hmon, _, _ = procMonitorFromWindow.Call(fgWnd, monitorDefaultToNearest)
		}
	default: // MonitorMouse
		var pt point
		procGetCursorPos.Call(uintptr(unsafe.Pointer(&pt)))
		hmon, _, _ = procMonitorFromPoint.Call(
			uintptr(unsafe.Pointer(&pt)),
			monitorDefaultToNearest,
		)
	}

	if hmon == 0 {
		// Fallback: primary monitor
		var pt point
		hmon, _, _ = procMonitorFromPoint.Call(
			uintptr(unsafe.Pointer(&pt)),
			monitorDefaultToPrimary,
		)
	}

	var mi monitorInfo
	mi.CbSize = uint32(unsafe.Sizeof(mi))
	procGetMonitorInfoW.Call(hmon, uintptr(unsafe.Pointer(&mi)))
	return mi.RcWork
}

// estimateWorkArea returns the work area of the configured target monitor
// for use in initial position estimates before the window is rendered.
func estimateWorkArea() (left, top, w, h int) {
	if capturedWorkAreaSet {
		wa := capturedWorkArea
		return int(wa.Left), int(wa.Top), wa.Width(), wa.Height()
	}
	wa := workAreaForBehavior(activeBehavior)
	return int(wa.Left), int(wa.Top), wa.Width(), wa.Height()
}

// workAreaForWindow returns the work area of the monitor that owns hwnd.
// Used by ResizeAndCenter to keep the window on its current monitor.
func workAreaForWindow(hwnd uintptr) rect {
	hmon, _, _ := procMonitorFromWindow.Call(hwnd, monitorDefaultToNearest)
	if hmon == 0 {
		return workAreaForBehavior(MonitorPrimary)
	}
	var mi monitorInfo
	mi.CbSize = uint32(unsafe.Sizeof(mi))
	procGetMonitorInfoW.Call(hmon, uintptr(unsafe.Pointer(&mi)))
	return mi.RcWork
}

// ResizeAndCenter resizes the terminal window (cols/lines), centers it within
// the work area of its current monitor, and gives it focus. It reads the HWND
// from shared memory (written by the menuhost), falling back to a process tree
// walk if shared memory is not available.
func ResizeAndCenter(cols, lines int) {
	hwnd := readHwndShm()
	if hwnd == 0 {
		hwnd = findAncestorWindow()
	}
	if hwnd == 0 {
		logging.Info("ResizeAndCenter: no window found")
		return
	}

	var r rect
	procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&r)))
	curW := r.Width()
	curH := r.Height()
	if curW <= 0 || curH <= 0 || launchCols <= 0 || launchLines <= 0 {
		logging.Info("ResizeAndCenter: bail hwnd=%x rect=(%d,%d,%d,%d) curW=%d curH=%d launchCols=%d launchLines=%d",
			hwnd, r.Left, r.Top, r.Right, r.Bottom, curW, curH, launchCols, launchLines)
		return
	}

	// Compute new size proportionally from current window (round to avoid truncation losing a line)
	width := (curW*cols + launchCols/2) / launchCols
	height := (curH*lines + launchLines/2) / launchLines

	wa := workAreaForWindow(hwnd)
	x := int(wa.Left) + (wa.Width()-width)/2
	y := int(wa.Top) + (wa.Height()-height)/2
	if x < int(wa.Left) {
		x = int(wa.Left)
	}
	if y < int(wa.Top) {
		y = int(wa.Top)
	}

	logging.Info("ResizeAndCenter: %dx%d -> %dx%d (cur=%dx%d, launch=%dx%d, px=%dx%d) work=(%d,%d,%d,%d) pos=(%d,%d)",
		launchCols, launchLines, cols, lines, curW, curH, launchCols, launchLines, width, height,
		wa.Left, wa.Top, wa.Right, wa.Bottom, x, y)

	procSetWindowPos.Call(hwnd, hwndTopmost, uintptr(x), uintptr(y), uintptr(width), uintptr(height), swpShowWindow)

	launchCols = cols
	launchLines = lines
}

// findAncestorWindow walks up the process tree from the current process,
// returning the first visible top-level window it finds. When launchTitle
// is set and a process owns multiple windows (e.g. Windows Terminal), the
// title-matching window is preferred over the largest.
func findAncestorWindow() uintptr {
	pid := os.Getpid()
	// Build a PID→ParentPID map from a process snapshot.
	parentOf := processParentMap()

	for i := 0; i < 8; i++ { // limit depth to avoid infinite loops
		parent, ok := parentOf[pid]
		if !ok || parent == 0 || parent == pid {
			break
		}
		hwnd := findWindowByPID(parent)
		if hwnd != 0 {
			logging.Info("findAncestorWindow: found hwnd=%x at ancestor pid=%d (depth=%d)", hwnd, parent, i)
			return hwnd
		}
		pid = parent
	}
	return 0
}

// processParentMap returns a map of PID → ParentPID for all running processes.
func processParentMap() map[int]int {
	snap, err := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
	if err != nil {
		return nil
	}
	defer windows.CloseHandle(snap)

	m := make(map[int]int)
	var pe windows.ProcessEntry32
	pe.Size = uint32(unsafe.Sizeof(pe))
	if err := windows.Process32First(snap, &pe); err != nil {
		return m
	}
	for {
		m[int(pe.ProcessID)] = int(pe.ParentProcessID)
		if err := windows.Process32Next(snap, &pe); err != nil {
			break
		}
	}
	return m
}

// minWindowArea is the minimum pixel area to consider a window "real" (not a helper).
const minWindowArea = 1000

// findWindowByPID returns the largest visible top-level window belonging to the given PID, or 0.
func findWindowByPID(pid int) uintptr {
	var best uintptr
	var bestArea int
	cb := syscall.NewCallback(func(hwnd, lParam uintptr) uintptr {
		var windowPID uint32
		procGetWindowThreadProcessId.Call(hwnd, uintptr(unsafe.Pointer(&windowPID)))
		if int(windowPID) == pid {
			vis, _, _ := procIsWindowVisible.Call(hwnd)
			if vis != 0 {
				var r rect
				procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&r)))
				area := r.Width() * r.Height()
				if area >= minWindowArea && area > bestArea {
					best = hwnd
					bestArea = area
				}
			}
		}
		return 1
	})
	procEnumWindows.Call(cb, 0)
	return best
}

// HasVisibleWindow returns true if a visible top-level window exists for the given PID.
func HasVisibleWindow(pid int) bool {
	return findWindowByPID(pid) != 0
}

// FindAndCenterByPID finds a visible window belonging to pid, centers it on the
// configured target monitor's work area, and returns the hwnd (0 if not found).
func FindAndCenterByPID(pid int) uintptr {
	hwnd := findWindowByPID(pid)
	if hwnd == 0 {
		logging.Info("FindAndCenterByPID: no window for pid=%d", pid)
		return 0
	}
	logging.Info("FindAndCenterByPID: found hwnd=%x for pid=%d", hwnd, pid)

	var r rect
	procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&r)))
	w := r.Width()
	h := r.Height()
	if w <= 0 || h <= 0 {
		return 0
	}

	var wa rect
	if capturedWorkAreaSet {
		wa = capturedWorkArea
	} else {
		wa = workAreaForBehavior(activeBehavior)
	}
	x := int(wa.Left) + (wa.Width()-w)/2
	y := int(wa.Top) + (wa.Height()-h)/2
	if x < int(wa.Left) {
		x = int(wa.Left)
	}
	if y < int(wa.Top) {
		y = int(wa.Top)
	}

	logging.Info("FindAndCenterByPID: work=(%d,%d,%d,%d) win=%dx%d pos=(%d,%d)",
		wa.Left, wa.Top, wa.Right, wa.Bottom, w, h, x, y)

	// HWND_TOPMOST: prevent the window from being pushed behind other windows
	// while Alacritty finishes initializing.
	procSetWindowPos.Call(hwnd, hwndTopmost, uintptr(x), uintptr(y), 0, 0, swpNoSize|swpShowWindow)
	return hwnd
}

// ── Mouse input / focus ─────────────────────────────────────────────────────

type mouseInput struct {
	Type        uint32
	_           uint32
	Dx          int32
	Dy          int32
	MouseData   uint32
	DwFlags     uint32
	Time        uint32
	_           uint32
	DwExtraInfo uintptr
}

const (
	mouseeventfAbsolute = 0x8000
	mouseeventfMove     = 0x0001
	mouseeventfLeftDown = 0x0002
	mouseeventfLeftUp   = 0x0004
)

// FocusHwnd brings the window to the front and gives it keyboard focus.
//
// Mirrors the PowerToys CmdPal ShowHwnd() sequence as closely as possible for
// a cross-process scenario (we don't own the Alacritty window).
//
// PowerToys exact order (same-process, so SetActiveWindow works directly):
//   ShowWindow → SetForegroundWindow → SetActiveWindow → SetWindowPos(HWND_TOPMOST)
//
// Our adapted order:
//  1. Re-center (Alacritty may have moved the window during init).
//  2. ShowWindow(SW_SHOW) — ensure the window is shown.
//  3. SetForegroundWindow — best-effort; works only if daemon still holds rights.
//  4. AttachThreadInput + SetActiveWindow + SetFocus — cross-process activation.
//     AttachThreadInput couples our input queue to the target thread, satisfying
//     the "must be attached to calling thread's message queue" requirement for
//     both SetActiveWindow and SetFocus across process boundaries.
//  5. SetWindowPos(HWND_TOPMOST, SWP_NOMOVE|SWP_NOSIZE) — after focus calls,
//     matching PowerToys order; ensures window stays on top.
//  6. SendInput click — final OS-level fallback.
func FocusHwnd(hwnd uintptr) {
	// 1. Re-center: re-read rect in case Alacritty moved the window during init.
	var r rect
	procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&r)))
	w := r.Width()
	h := r.Height()
	if w > 0 && h > 0 {
		var wa rect
		if capturedWorkAreaSet {
			wa = capturedWorkArea
		} else {
			wa = workAreaForWindow(hwnd)
		}
		x := int(wa.Left) + (wa.Width()-w)/2
		y := int(wa.Top) + (wa.Height()-h)/2
		if x < int(wa.Left) {
			x = int(wa.Left)
		}
		if y < int(wa.Top) {
			y = int(wa.Top)
		}
		procSetWindowPos.Call(hwnd, 0, uintptr(x), uintptr(y), 0, 0, swpNoSize|swpShowWindow)
		logging.Info("FocusHwnd: hwnd=%x re-centered to (%d,%d)", hwnd, x, y)
	}

	// 2. Show the window (belt+suspenders; Alacritty already shows it, but match
	//    PowerToys' ShowWindow call before any focus operations).
	swRet, _, _ := procShowWindow.Call(hwnd, swShow)
	logging.Info("FocusHwnd: ShowWindow hwnd=%x ret=%d", hwnd, swRet)

	// 3. SetForegroundWindow — best-effort (requires daemon to hold foreground rights,
	//    which may have expired after the Win key-up event).
	sfwRet, _, sfwErr := procSetForegroundWindow.Call(hwnd)
	logging.Info("FocusHwnd: SetForegroundWindow hwnd=%x ret=%d err=%v", hwnd, sfwRet, sfwErr)

	// 4. AttachThreadInput + SetActiveWindow + SetFocus.
	//    Windows requires the window be "attached to the calling thread's message
	//    queue" for SetActiveWindow/SetFocus to work cross-process.
	//    AttachThreadInput satisfies this without foreground rights.
	targetTID, _, _ := procGetWindowThreadProcessId.Call(hwnd, 0)
	myTID, _, _ := procGetCurrentThreadId.Call()
	logging.Info("FocusHwnd: myTID=%d targetTID=%d", myTID, targetTID)
	if targetTID != 0 && targetTID != myTID {
		atiRet, _, _ := procAttachThreadInput.Call(myTID, targetTID, 1)
		logging.Info("FocusHwnd: AttachThreadInput(attach) ret=%d", atiRet)
		sawRet, _, _ := procSetActiveWindow.Call(hwnd)
		logging.Info("FocusHwnd: SetActiveWindow hwnd=%x ret=%x", hwnd, sawRet)
		sfRet, _, _ := procSetFocus.Call(hwnd)
		logging.Info("FocusHwnd: SetFocus hwnd=%x ret=%x", hwnd, sfRet)
		atiDetRet, _, _ := procAttachThreadInput.Call(myTID, targetTID, 0)
		logging.Info("FocusHwnd: AttachThreadInput(detach) ret=%d", atiDetRet)
	}

	// 5. SetWindowPos(HWND_TOPMOST) after focus calls — matches PowerToys order.
	swpRet, _, _ := procSetWindowPos.Call(hwnd, hwndTopmost, 0, 0, 0, 0, swpNoMove|swpNoSize|swpShowWindow)
	logging.Info("FocusHwnd: SetWindowPos(HWND_TOPMOST) hwnd=%x ret=%d", hwnd, swpRet)
}

// findWindowByTitle returns the largest visible top-level window whose title
// matches the given string, or 0.
func findWindowByTitle(title string) uintptr {
	titleU16, _ := syscall.UTF16FromString(title)
	var best uintptr
	var bestArea int
	cb := syscall.NewCallback(func(hwnd, lParam uintptr) uintptr {
		vis, _, _ := procIsWindowVisible.Call(hwnd)
		if vis == 0 {
			return 1
		}
		var buf [256]uint16
		n, _, _ := procGetWindowTextW.Call(hwnd, uintptr(unsafe.Pointer(&buf[0])), 256)
		if n > 0 && n <= 256 {
			match := true
			if int(n) != len(titleU16)-1 { // UTF16FromString includes null terminator
				match = false
			} else {
				for i := 0; i < int(n); i++ {
					if buf[i] != titleU16[i] {
						match = false
						break
					}
				}
			}
			if match {
				var r rect
				procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&r)))
				area := r.Width() * r.Height()
				if area >= minWindowArea && area > bestArea {
					best = hwnd
					bestArea = area
				}
			}
		}
		return 1
	})
	procEnumWindows.Call(cb, 0)
	return best
}

// FindAndCenterByTitle finds a visible window by title, centers it, and returns the hwnd.
func FindAndCenterByTitle(title string) uintptr {
	hwnd := findWindowByTitle(title)
	if hwnd == 0 {
		return 0
	}
	logging.Info("FindAndCenterByTitle: found hwnd=%x for title=%q", hwnd, title)
	centerHwnd(hwnd)
	return hwnd
}

// centerHwnd centers the window on the captured work area (or current monitor).
func centerHwnd(hwnd uintptr) {
	var r rect
	procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&r)))
	w := r.Width()
	h := r.Height()
	if w <= 0 || h <= 0 {
		return
	}

	var wa rect
	if capturedWorkAreaSet {
		wa = capturedWorkArea
	} else {
		wa = workAreaForBehavior(activeBehavior)
	}
	x := int(wa.Left) + (wa.Width()-w)/2
	y := int(wa.Top) + (wa.Height()-h)/2
	if x < int(wa.Left) {
		x = int(wa.Left)
	}
	if y < int(wa.Top) {
		y = int(wa.Top)
	}

	procSetWindowPos.Call(hwnd, hwndTopmost, uintptr(x), uintptr(y), 0, 0, swpNoSize|swpShowWindow)
}

// IsHwndVisible returns true if the given window handle is still visible.
func IsHwndVisible(hwnd uintptr) bool {
	if hwnd == 0 {
		return false
	}
	vis, _, _ := procIsWindowVisible.Call(hwnd)
	return vis != 0
}

// clickCenter injects a left mouse click at the center of hwnd.
func clickCenter(hwnd uintptr) {
	var r rect
	procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&r)))
	cx := (r.Left + r.Right) / 2
	cy := (r.Top + r.Bottom) / 2

	// GetSystemMetrics returns INT (32-bit signed). Cast via int32 to correctly
	// sign-extend before widening to int, avoiding corruption on 64-bit.
	vsWRaw, _, _ := procGetSystemMetrics.Call(smCXVirtualScreen)
	vsHRaw, _, _ := procGetSystemMetrics.Call(smCYVirtualScreen)
	vsXRaw, _, _ := procGetSystemMetrics.Call(smXVirtualScreen)
	vsYRaw, _, _ := procGetSystemMetrics.Call(smYVirtualScreen)
	vsW := int(int32(vsWRaw))
	vsH := int(int32(vsHRaw))
	vsX := int(int32(vsXRaw))
	vsY := int(int32(vsYRaw))
	logging.Info("clickCenter: vsW=%d vsH=%d vsX=%d vsY=%d", vsW, vsH, vsX, vsY)
	if vsW == 0 || vsH == 0 {
		return
	}

	absX := int32((int(cx)-vsX)*65535/vsW)
	absY := int32((int(cy)-vsY)*65535/vsH)

	flags := uint32(mouseeventfAbsolute | mouseeventfMove | mouseeventfLeftDown)
	flagsUp := uint32(mouseeventfAbsolute | mouseeventfMove | mouseeventfLeftUp)

	inputs := [2]mouseInput{
		{Dx: absX, Dy: absY, DwFlags: flags},
		{Dx: absX, Dy: absY, DwFlags: flagsUp},
	}

	n, _, _ := procSendInput.Call(2, uintptr(unsafe.Pointer(&inputs[0])), sizeofInput)
	logging.Info("clickCenter: hwnd=%x pos=%d,%d abs=%d,%d sent=%d", hwnd, cx, cy, absX, absY, n)
}
