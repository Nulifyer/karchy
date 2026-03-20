//go:build !windows && !linux

package terminal

// estimateWorkArea returns a hardcoded fallback on unsupported platforms.
func estimateWorkArea() (left, top, w, h int) { return 0, 0, 1920, 1080 }

// ResizeAndCenter is a no-op on non-Windows.
func ResizeAndCenter(cols, lines int) {}

// HasVisibleWindow is a no-op on non-Windows; always returns false.
func HasVisibleWindow(pid int) bool { return false }

// FindAndCenterByPID is a no-op on non-Windows; always returns 0.
func FindAndCenterByPID(pid int) uintptr { return 0 }

// FindAndHideByPID is a no-op on non-Windows; always returns 0.
func FindAndHideByPID(pid int) uintptr { return 0 }

// FocusHwnd is a no-op on non-Windows.
func FocusHwnd(hwnd uintptr) {}
