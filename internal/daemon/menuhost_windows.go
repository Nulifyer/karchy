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
		mu      sync.Mutex
		termPID int
	)

	for {
		r := waitEvent(showEvent, waitInfinite)
		if r != waitObject0 {
			logging.Info("menuhost: wait returned %d, exiting", r)
			break
		}
		logging.Info("menuhost: show event received")
		menuHostShow(&mu, &termPID)
	}
}

// menuHostShow either brings the existing terminal window to the foreground or
// spawns a fresh one. Called each time the daemon signals the show event.
func menuHostShow(mu *sync.Mutex, termPID *int) {
	mu.Lock()
	pid := *termPID
	mu.Unlock()

	if pid != 0 {
		hwnd := terminal.FindAndCenterByPID(pid)
		if hwnd != 0 {
			runtime.LockOSThread()
			terminal.FocusHwnd(hwnd)
			runtime.UnlockOSThread()
			logging.Info("menuhost: focused existing hwnd=%x pid=%d", hwnd, pid)
			return
		}
		logging.Info("menuhost: no visible window for pid=%d, respawning", pid)
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
	mu.Unlock()
	logging.Info("menuhost: spawned pid=%d", newPID)

	// Poll for the window to appear, center and focus it, then monitor for exit.
	go menuHostMonitor(newPID, mu, termPID)
}

// menuHostMonitor waits for the terminal window to appear, focuses it, then
// waits for the terminal to exit and clears the PID so the next show triggers
// a fresh spawn.
func menuHostMonitor(pid int, mu *sync.Mutex, termPID *int) {
	// Poll for a visible window (up to 2s, 50ms intervals — matches old timer logic).
	var hwnd uintptr
	for i := 0; i < 40; i++ {
		hwnd = terminal.FindAndCenterByPID(pid)
		if hwnd != 0 {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}

	if hwnd == 0 {
		logging.Info("menuhost: window not found after timeout pid=%d", pid)
	} else {
		// Give the terminal 300ms to finish rendering before focusing.
		time.Sleep(300 * time.Millisecond)

		hwnd = terminal.FindAndCenterByPID(pid)
		if hwnd == 0 {
			logging.Info("menuhost: window gone before focus pid=%d", pid)
		} else {
			runtime.LockOSThread()
			terminal.FocusHwnd(hwnd)
			runtime.UnlockOSThread()
			logging.Info("menuhost: focused new hwnd=%x pid=%d", hwnd, pid)
		}
	}

	// Block until the terminal exits, then clear the PID.
	waitForProcessExit(pid)

	mu.Lock()
	if *termPID == pid {
		*termPID = 0
	}
	mu.Unlock()
	logging.Info("menuhost: terminal exited pid=%d", pid)
}

var procGetCurrentProcessId = kernel32.NewProc("GetCurrentProcessId")

func currentPID() int {
	r, _, _ := procGetCurrentProcessId.Call()
	return int(r)
}
