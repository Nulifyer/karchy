//go:build windows

package daemon

import (
	"runtime"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
)

func runMenuHost() {
	hideConsole()

	// Single-instance guard — exit if another menu host is already running.
	namePtr, _ := syscall.UTF16PtrFromString(menuHostMutexName)
	mh, _, _ := procCreateMutex.Call(0, 1, uintptr(unsafe.Pointer(namePtr)))
	if mh == 0 {
		logging.Info("menuhost: failed to create mutex")
		return
	}
	lastErr, _, _ := procGetLastError.Call()
	if lastErr == errorAlreadyExists {
		logging.Info("menuhost: already running")
		procCloseHandle.Call(mh)
		return
	}
	defer procReleaseMutex.Call(mh)
	defer procCloseHandle.Call(mh)

	// Load config once, up front — all file I/O happens here, not on the
	// daemon's message thread where it would risk dropping the keyboard hook.
	cfg := config.Load()
	terminal.SetMonitorBehavior(terminal.ParseMonitorBehavior(cfg.Window.SummonOn))

	// Create the named auto-reset event the daemon signals on each hotkey press.
	showEvent := createAutoResetEvent(menuHostShowEventName)
	if showEvent == 0 {
		logging.Info("menuhost: failed to create show event")
		return
	}
	defer procCloseHandle.Call(showEvent)

	logging.Info("menuhost: ready, pid=%d", currentPID())

	var (
		mu       sync.Mutex
		termPID  int
		termHwnd uintptr
	)

	for {
		r := waitEvent(showEvent, waitInfinite)
		if r != waitObject0 {
			logging.Info("menuhost: wait returned %d, exiting", r)
			break
		}
		logging.Info("menuhost: show event received")
		// Read the work area the daemon captured at hotkey time (before it called
		// SetForegroundWindow). This ensures all centering uses the correct monitor.
		if wl, wt, wr, wb, ok := readWorkAreaFromShm(); ok {
			terminal.SetCapturedWorkArea(wl, wt, wr, wb)
			logging.Info("menuhost: work area (%d,%d,%d,%d)", wl, wt, wr, wb)
		}
		menuHostShow(&mu, &termPID, &termHwnd)
	}
}

// menuHostShow either brings the existing terminal window to the foreground or
// spawns a fresh one. Called each time the daemon signals the show event.
func menuHostShow(mu *sync.Mutex, termPID *int, termHwnd *uintptr) {
	mu.Lock()
	pid := *termPID
	hwnd := *termHwnd
	mu.Unlock()

	// Try stored HWND first (works for WT where PID may not match the window).
	if hwnd != 0 && terminal.IsHwndVisible(hwnd) {
		runtime.LockOSThread()
		terminal.FocusHwnd(hwnd)
		runtime.UnlockOSThread()
		logging.Info("menuhost: focused existing hwnd=%x", hwnd)
		return
	}

	if pid != 0 {
		found := terminal.FindAndCenterByPID(pid)
		if found != 0 {
			runtime.LockOSThread()
			terminal.FocusHwnd(found)
			runtime.UnlockOSThread()
			mu.Lock()
			*termHwnd = found
			mu.Unlock()
			writeHwndToShm(found)
			logging.Info("menuhost: focused existing hwnd=%x pid=%d", found, pid)
			return
		}
		// No visible window, but the process may still be starting up.
		// Only respawn if the process has actually exited to avoid duplicates.
		if isProcessAlive(pid) {
			logging.Info("menuhost: no window yet for pid=%d, still alive, skipping spawn", pid)
			return
		}
		logging.Info("menuhost: no visible window for pid=%d, process exited, respawning", pid)
	}

	// Spawn a fresh terminal running karchy menu.
	args := []string{}
	if logging.Enabled() {
		args = append(args, "--debug")
	}
	args = append(args, "menu")

	newPID, err := terminal.Launch(40, 14, "Karchy", args...)
	if err != nil {
		logging.Info("menuhost: launch failed: %v", err)
		return
	}

	mu.Lock()
	*termPID = newPID
	*termHwnd = 0
	mu.Unlock()
	logging.Info("menuhost: spawned pid=%d", newPID)

	// Poll for the window to appear, center and focus it, then monitor for exit.
	go menuHostMonitor(newPID, mu, termPID, termHwnd)
}

// menuHostMonitor waits for the terminal window to appear, focuses it, then
// waits for the terminal to exit and clears the PID so the next show triggers
// a fresh spawn.
func menuHostMonitor(pid int, mu *sync.Mutex, termPID *int, termHwnd *uintptr) {
	const launchTitle = "Karchy"

	// Poll for a visible window (up to 2s, 50ms intervals — matches old timer logic).
	// Try PID first, then fall back to title (needed for WT monarch delegation).
	var hwnd uintptr
	for i := 0; i < 40; i++ {
		hwnd = terminal.FindAndCenterByPID(pid)
		if hwnd == 0 {
			hwnd = terminal.FindAndCenterByTitle(launchTitle)
		}
		if hwnd != 0 {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}

	if hwnd == 0 {
		logging.Info("menuhost: window not found after timeout pid=%d", pid)
	} else {
		mu.Lock()
		*termHwnd = hwnd
		mu.Unlock()
		writeHwndToShm(hwnd)

		// Give the terminal 300ms to finish rendering before focusing.
		time.Sleep(300 * time.Millisecond)

		// Re-find: prefer PID, fall back to title, last resort use stored HWND.
		found := terminal.FindAndCenterByPID(pid)
		if found == 0 {
			found = terminal.FindAndCenterByTitle(launchTitle)
		}
		if found != 0 {
			hwnd = found
			mu.Lock()
			*termHwnd = hwnd
			mu.Unlock()
			writeHwndToShm(hwnd)
		}

		if hwnd == 0 {
			logging.Info("menuhost: window gone before focus pid=%d", pid)
		} else {
			runtime.LockOSThread()
			terminal.FocusHwnd(hwnd)
			runtime.UnlockOSThread()
			logging.Info("menuhost: focused new hwnd=%x pid=%d", hwnd, pid)
		}
	}

	// Wait for the terminal to exit. If we have a window handle, poll its
	// visibility (needed for WT where the spawned PID may exit immediately).
	// Otherwise fall back to process-based waiting.
	if hwnd != 0 {
		for terminal.IsHwndVisible(hwnd) {
			time.Sleep(200 * time.Millisecond)
		}
	} else {
		waitForProcessExit(pid)
	}

	mu.Lock()
	if *termPID == pid {
		*termPID = 0
	}
	*termHwnd = 0
	mu.Unlock()
	writeHwndToShm(0)
	logging.Info("menuhost: terminal exited pid=%d", pid)
}

var procGetCurrentProcessId = kernel32.NewProc("GetCurrentProcessId")

func currentPID() int {
	r, _, _ := procGetCurrentProcessId.Call()
	return int(r)
}
