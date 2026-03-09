//go:build windows

package terminal

import (
	"os"
	"syscall"
	"unsafe"

	"github.com/nulifyer/karchy/internal/logging"
)

var (
	user32             = syscall.NewLazyDLL("user32.dll")
	procGetSystemMetrics    = user32.NewProc("GetSystemMetrics")
	procGetWindowRect       = user32.NewProc("GetWindowRect")
	procSetWindowPos        = user32.NewProc("SetWindowPos")
	procEnumWindows         = user32.NewProc("EnumWindows")
	procGetWindowThreadProcessId = user32.NewProc("GetWindowThreadProcessId")
	procIsWindowVisible     = user32.NewProc("IsWindowVisible")
	procSendInput           = user32.NewProc("SendInput")
)

const (
	smCXScreen = 0
	smCYScreen = 1

	swpNoSize     = 0x0001
	swpShowWindow = 0x0040

	sizeofInput = 40 // sizeof(INPUT) on 64-bit Windows
)

type rect struct {
	Left, Top, Right, Bottom int32
}

func screenSize() (int, int) {
	w, _, _ := procGetSystemMetrics.Call(smCXScreen)
	h, _, _ := procGetSystemMetrics.Call(smCYScreen)
	return int(w), int(h)
}

// ResizeAndCenter finds the Alacritty window by parent PID, resizes it (cols/lines), centers it, makes it topmost, and gives it focus.
// It derives the actual cell size from the current window dimensions and the launch cols/lines.
func ResizeAndCenter(cols, lines int) {
	ppid := os.Getppid()
	hwnd := findWindowByPID(ppid)
	if hwnd == 0 {
		logging.Info("ResizeAndCenter: no window for ppid=%d", ppid)
		return
	}

	// Get current window size to derive actual cell dimensions
	var r rect
	procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&r)))
	curW := int(r.Right - r.Left)
	curH := int(r.Bottom - r.Top)
	if curW <= 0 || curH <= 0 || launchCols <= 0 || launchLines <= 0 {
		logging.Info("ResizeAndCenter: bail hwnd=%x rect=(%d,%d,%d,%d) curW=%d curH=%d launchCols=%d launchLines=%d",
			hwnd, r.Left, r.Top, r.Right, r.Bottom, curW, curH, launchCols, launchLines)
		return
	}

	// Compute new size proportionally from current window (round to avoid truncation losing a line)
	width := (curW*cols + launchCols/2) / launchCols
	height := (curH*lines + launchLines/2) / launchLines

	logging.Info("ResizeAndCenter: %dx%d -> %dx%d (cur=%dx%d, launch=%dx%d, px=%dx%d)",
		launchCols, launchLines, cols, lines, curW, curH, launchCols, launchLines, width, height)

	sw, sh := screenSize()
	x := max(0, (sw-width)/2)
	y := max(0, (sh-height)/2)

	logging.Info("ResizeAndCenter: screen=%dx%d x=(%d-%d)/2=%d y=(%d-%d)/2=%d",
		sw, sh, sw, width, x, sh, height, y)

	procSetWindowPos.Call(hwnd, 0, uintptr(x), uintptr(y), uintptr(width), uintptr(height), swpShowWindow)

	// Update stored dimensions so subsequent resizes use the new baseline
	launchCols = cols
	launchLines = lines
}

// minWindowArea is the minimum pixel area to consider a window "real" (not a helper).
// Alacritty creates a small 16x16 helper window; this threshold skips it.
const minWindowArea = 1000

// findWindowByPID returns the largest visible top-level window belonging to the given PID, or 0.
// Skips tiny helper windows (area < minWindowArea).
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
				area := int(r.Right-r.Left) * int(r.Bottom-r.Top)
				if area >= minWindowArea && area > bestArea {
					best = hwnd
					bestArea = area
				}
			}
		}
		return 1 // continue (check all windows)
	})
	procEnumWindows.Call(cb, 0)
	return best
}

// HasVisibleWindow returns true if a visible top-level window exists for the given PID.
func HasVisibleWindow(pid int) bool {
	return findWindowByPID(pid) != 0
}

// FindAndCenterByPID finds a visible window belonging to the given PID,
// centers it, and returns the hwnd (0 if not found).
func FindAndCenterByPID(pid int) uintptr {
	hwnd := findWindowByPID(pid)
	if hwnd == 0 {
		logging.Info("FindAndCenterByPID: no window for pid=%d", pid)
		return 0
	}
	logging.Info("FindAndCenterByPID: found hwnd=%x for pid=%d", hwnd, pid)

	var r rect
	procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&r)))
	w := int(r.Right - r.Left)
	h := int(r.Bottom - r.Top)
	if w <= 0 || h <= 0 {
		return 0
	}

	sw, sh := screenSize()
	x := (sw - w) / 2
	y := (sh - h) / 2

	logging.Info("FindAndCenterByPID: screen=%dx%d win=%dx%d x=(%d-%d)/2=%d y=(%d-%d)/2=%d",
		sw, sh, w, h, sw, w, x, sh, h, y)

	// Use HWND_TOP (0) not HWND_TOPMOST — topmost interferes with focus/activation.
	procSetWindowPos.Call(hwnd, 0, uintptr(x), uintptr(y), 0, 0, swpNoSize|swpShowWindow)
	return hwnd
}

// mouseInput represents a Win32 INPUT struct with MOUSEINPUT union (64-bit).
type mouseInput struct {
	Type        uint32   // INPUT_MOUSE = 0
	_           uint32   // padding for union alignment
	Dx          int32    // absolute X (0–65535)
	Dy          int32    // absolute Y (0–65535)
	MouseData   uint32
	DwFlags     uint32
	Time        uint32
	_           uint32   // padding
	DwExtraInfo uintptr
}

const (
	mouseeventfAbsolute = 0x8000
	mouseeventfMove     = 0x0001
	mouseeventfLeftDown = 0x0002
	mouseeventfLeftUp   = 0x0004
)

// clickWindow simulates a mouse click at the center of the given window.
// This forces Windows to activate the window with full keyboard focus.
func clickWindow(hwnd uintptr) {
	var r rect
	procGetWindowRect.Call(hwnd, uintptr(unsafe.Pointer(&r)))
	cx := (r.Left + r.Right) / 2
	cy := (r.Top + r.Bottom) / 2

	sw, sh := screenSize()
	if sw == 0 || sh == 0 {
		return
	}

	// Convert screen coordinates to absolute (0–65535 range)
	absX := int32(int(cx) * 65535 / sw)
	absY := int32(int(cy) * 65535 / sh)

	flags := uint32(mouseeventfAbsolute | mouseeventfMove | mouseeventfLeftDown)
	flagsUp := uint32(mouseeventfAbsolute | mouseeventfMove | mouseeventfLeftUp)

	inputs := [2]mouseInput{
		{Dx: absX, Dy: absY, DwFlags: flags},
		{Dx: absX, Dy: absY, DwFlags: flagsUp},
	}

	n, _, _ := procSendInput.Call(2, uintptr(unsafe.Pointer(&inputs[0])), sizeofInput)
	logging.Info("clickWindow: hwnd=%x pos=%d,%d abs=%d,%d sent=%d", hwnd, cx, cy, absX, absY, n)
}

// FocusHwnd brings a window to the foreground by simulating a click on it.
func FocusHwnd(hwnd uintptr) {
	clickWindow(hwnd)
}

