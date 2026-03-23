//go:build windows

package daemon

import (
	"syscall"
	"unsafe"
)

const (
	menuHostShowEventName = `Local\KarchyShowMenu`
	menuHostMutexName     = `Local\KarchyMenuHost`

	waitObject0  = 0x00000000
	waitInfinite = 0xFFFFFFFF

	eventModifyState = 0x0002
	synchronize      = 0x00100000
	processSynchronize = 0x00100000
)

var (
	procCreateEventW        = kernel32.NewProc("CreateEventW")
	procOpenEventW          = kernel32.NewProc("OpenEventW")
	procSetEvent            = kernel32.NewProc("SetEvent")
	procWaitForSingleObject = kernel32.NewProc("WaitForSingleObject")
	procOpenProcess         = kernel32.NewProc("OpenProcess")
)

// createAutoResetEvent creates a named auto-reset event (not signaled).
// Auto-reset: exactly one WaitForSingleObject is released per SetEvent call.
func createAutoResetEvent(name string) uintptr {
	namePtr, _ := syscall.UTF16PtrFromString(name)
	h, _, _ := procCreateEventW.Call(0, 0, 0, uintptr(unsafe.Pointer(namePtr)))
	return h
}

// openAutoResetEvent opens an existing named event for signaling/waiting.
// Returns 0 if the event does not exist yet.
func openAutoResetEvent(name string) uintptr {
	namePtr, _ := syscall.UTF16PtrFromString(name)
	h, _, _ := procOpenEventW.Call(eventModifyState|synchronize, 0, uintptr(unsafe.Pointer(namePtr)))
	return h
}

// signalEvent signals the event, waking one waiter.
func signalEvent(h uintptr) {
	procSetEvent.Call(h)
}

// waitEvent blocks until the event is signaled or the timeout elapses.
// Returns waitObject0 (0) when signaled, non-zero on timeout or error.
func waitEvent(h uintptr, timeoutMs uint32) uint32 {
	r, _, _ := procWaitForSingleObject.Call(h, uintptr(timeoutMs))
	return uint32(r)
}

// waitForProcessExit blocks until the process with the given PID exits.
func waitForProcessExit(pid int) {
	h, _, _ := procOpenProcess.Call(processSynchronize, 0, uintptr(pid))
	if h == 0 {
		return
	}
	defer procCloseHandle.Call(h)
	procWaitForSingleObject.Call(h, uintptr(waitInfinite))
}
