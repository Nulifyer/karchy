//go:build windows

package platform

import (
	"strings"
	"syscall"
	"unsafe"

	"github.com/nulifyer/karchy/internal/logging"
)

var (
	shell32            = syscall.NewLazyDLL("shell32.dll")
	kernel32           = syscall.NewLazyDLL("kernel32.dll")
	procShellExecuteEx = shell32.NewProc("ShellExecuteExW")
	procCloseHandle    = kernel32.NewProc("CloseHandle")
)

const (
	seeMaskNocloseprocess = 0x00000040
	seeMaskNoasync        = 0x00000100
	swShowNormal          = 1
)

// shellExecuteInfo mirrors SHELLEXECUTEINFOW (120 bytes on 64-bit).
type shellExecuteInfo struct {
	CbSize       uint32
	FMask        uint32
	Hwnd         uintptr
	LpVerb       *uint16
	LpFile       *uint16
	LpParameters *uint16
	LpDirectory  *uint16
	NShow        int32
	_            [4]byte // padding before pointer-sized HInstApp
	HInstApp     uintptr
	LpIDList     uintptr
	LpClass      *uint16
	HkeyClass    uintptr
	DwHotKey     uint32
	_            [4]byte // padding before union
	HIconMonitor uintptr
	HProcess     uintptr
}

// Open launches a file or URI using ShellExecuteExW.
// Paths containing '!' are treated as AUMIDs (UWP/packaged apps) and routed
// through the shell:AppsFolder namespace.
func Open(path string) {
	logging.Info("Open: %s", path)
	if strings.Contains(path, "!") {
		openAumid(path)
		return
	}

	file, _ := syscall.UTF16PtrFromString(path)
	sei := shellExecuteInfo{
		FMask: seeMaskNocloseprocess | seeMaskNoasync,
		LpFile: file,
		NShow:  swShowNormal,
	}
	sei.CbSize = uint32(unsafe.Sizeof(sei))
	ret, _, _ := procShellExecuteEx.Call(uintptr(unsafe.Pointer(&sei)))
	if ret == 0 {
		logging.Error("Open failed: ShellExecuteEx returned 0 for %s", path)
		return
	}
	if sei.HProcess != 0 {
		procCloseHandle.Call(sei.HProcess)
	}
}

// openAumid launches a packaged/UWP app by Application User Model ID using the
// shell:AppsFolder namespace, which Windows resolves via the activation manager.
func openAumid(aumid string) {
	logging.Info("OpenAumid: %s", aumid)
	file, _ := syscall.UTF16PtrFromString("shell:AppsFolder\\" + aumid)
	sei := shellExecuteInfo{
		FMask: seeMaskNoasync,
		LpFile: file,
		NShow:  swShowNormal,
	}
	sei.CbSize = uint32(unsafe.Sizeof(sei))
	ret, _, _ := procShellExecuteEx.Call(uintptr(unsafe.Pointer(&sei)))
	if ret == 0 {
		logging.Error("OpenAumid failed: ShellExecuteEx returned 0 for %s", aumid)
	}
}
