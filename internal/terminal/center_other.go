//go:build !windows

package terminal

func screenSize() (int, int) {
	return 1920, 1080
}

// ResizeAndCenter is a no-op on non-Windows.
func ResizeAndCenter(cols, lines int) {}

// HasVisibleWindow is a no-op on non-Windows; always returns false.
func HasVisibleWindow(pid int) bool { return false }

// FindAndCenterByPID is a no-op on non-Windows; always returns 0.
func FindAndCenterByPID(pid int) uintptr { return 0 }

// FocusHwnd is a no-op on non-Windows.
func FocusHwnd(hwnd uintptr) {}
