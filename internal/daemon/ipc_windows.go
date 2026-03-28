//go:build windows

package daemon

import (
	"syscall"
	"unsafe"
)

const (
	menuHostShowEventName = `Local\KarchyShowMenu`
	menuHostMutexName     = `Local\KarchyMenuHost`
	workAreaShmName       = `Local\KarchyWorkArea`
	hwndShmName           = `Local\KarchyHwnd`

	waitObject0  = 0x00000000
	waitInfinite = 0xFFFFFFFF

	eventModifyState   = 0x0002
	synchronize        = 0x00100000
	processSynchronize = 0x00100000

	pageReadWrite = 0x04
	fileMapWrite  = 0x0002
	fileMapRead   = 0x0004
)

var (
	procCreateEventW        = kernel32.NewProc("CreateEventW")
	procOpenEventW          = kernel32.NewProc("OpenEventW")
	procSetEvent            = kernel32.NewProc("SetEvent")
	procWaitForSingleObject = kernel32.NewProc("WaitForSingleObject")
	procOpenProcess         = kernel32.NewProc("OpenProcess")

	procCreateFileMappingW = kernel32.NewProc("CreateFileMappingW")
	procOpenFileMappingW   = kernel32.NewProc("OpenFileMappingW")
	procMapViewOfFile      = kernel32.NewProc("MapViewOfFile")
	procUnmapViewOfFile    = kernel32.NewProc("UnmapViewOfFile")
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

// createWorkAreaShm creates a 16-byte named shared-memory block.
// The returned handle must be kept open by the daemon for the lifetime of the process.
func createWorkAreaShm() uintptr {
	namePtr, _ := syscall.UTF16PtrFromString(workAreaShmName)
	h, _, _ := procCreateFileMappingW.Call(
		^uintptr(0), 0, pageReadWrite, 0, 16,
		uintptr(unsafe.Pointer(namePtr)),
	)
	return h
}

// writeWorkAreaToShm writes Left/Top/Right/Bottom (int32) into the shared-memory block.
func writeWorkAreaToShm(h uintptr, left, top, right, bottom int32) {
	if h == 0 {
		return
	}
	addr, _, _ := procMapViewOfFile.Call(h, fileMapWrite, 0, 0, 16)
	if addr == 0 {
		return
	}
	defer procUnmapViewOfFile.Call(addr)
	*(*[4]int32)(unsafe.Pointer(addr)) = [4]int32{left, top, right, bottom}
}

// readWorkAreaFromShm reads the work area written by the daemon.
// Returns ok=false if the mapping does not exist yet.
func readWorkAreaFromShm() (left, top, right, bottom int32, ok bool) {
	namePtr, _ := syscall.UTF16PtrFromString(workAreaShmName)
	h, _, _ := procOpenFileMappingW.Call(fileMapRead, 0, uintptr(unsafe.Pointer(namePtr)))
	if h == 0 {
		return 0, 0, 0, 0, false
	}
	defer procCloseHandle.Call(h)
	addr, _, _ := procMapViewOfFile.Call(h, fileMapRead, 0, 0, 16)
	if addr == 0 {
		return 0, 0, 0, 0, false
	}
	defer procUnmapViewOfFile.Call(addr)
	d := *(*[4]int32)(unsafe.Pointer(addr))
	return d[0], d[1], d[2], d[3], true
}

// isProcessAlive returns true if the process with the given PID is still running.
func isProcessAlive(pid int) bool {
	h, _, _ := procOpenProcess.Call(processSynchronize, 0, uintptr(pid))
	if h == 0 {
		return false
	}
	defer procCloseHandle.Call(h)
	r, _, _ := procWaitForSingleObject.Call(h, 0) // 0 = no wait
	return r != waitObject0                        // waitObject0 means exited
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

// createHwndShm creates an 8-byte named shared-memory block for the terminal HWND.
func createHwndShm() uintptr {
	namePtr, _ := syscall.UTF16PtrFromString(hwndShmName)
	h, _, _ := procCreateFileMappingW.Call(
		^uintptr(0), 0, pageReadWrite, 0, 8,
		uintptr(unsafe.Pointer(namePtr)),
	)
	return h
}

// writeHwndToShm writes the terminal HWND into the named shared-memory block.
// Opens the mapping by name so it works from the menuhost process (which doesn't
// hold the creation handle — that belongs to the daemon).
func writeHwndToShm(hwnd uintptr) {
	namePtr, _ := syscall.UTF16PtrFromString(hwndShmName)
	h, _, _ := procOpenFileMappingW.Call(fileMapWrite, 0, uintptr(unsafe.Pointer(namePtr)))
	if h == 0 {
		return
	}
	defer procCloseHandle.Call(h)
	addr, _, _ := procMapViewOfFile.Call(h, fileMapWrite, 0, 0, 8)
	if addr == 0 {
		return
	}
	defer procUnmapViewOfFile.Call(addr)
	*(*uintptr)(unsafe.Pointer(addr)) = hwnd
}

