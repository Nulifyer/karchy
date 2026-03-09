//go:build windows

package platform

import (
	"os"
	"syscall"
	"time"
	"unsafe"

	"github.com/nulifyer/karchy/internal/logging"
)

var (
	shell32          = syscall.NewLazyDLL("shell32.dll")
	procShellExecute = shell32.NewProc("ShellExecuteW")
)

// Open launches a file or URI using ShellExecuteW.
func Open(path string) {
	logging.Info("Open: %s", path)
	file, _ := syscall.UTF16PtrFromString(path)
	home, _ := os.UserHomeDir()
	dir, _ := syscall.UTF16PtrFromString(home)
	ret, _, _ := procShellExecute.Call(0, 0, uintptr(unsafe.Pointer(file)), 0, uintptr(unsafe.Pointer(dir)), 1) // NULL verb = default action, SW_SHOWNORMAL=1
	if ret <= 32 {
		logging.Error("Open failed: ShellExecuteW returned %d for %s", ret, path)
		return
	}
	// Give the target window time to appear so it gets focus when Alacritty exits.
	time.Sleep(500 * time.Millisecond)
}
