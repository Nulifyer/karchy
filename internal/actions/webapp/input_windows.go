//go:build windows

package webapp

import (
	"fmt"
	"os"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	user32              = syscall.NewLazyDLL("user32.dll")
	procOpenClipboard   = user32.NewProc("OpenClipboard")
	procCloseClipboard  = user32.NewProc("CloseClipboard")
	procGetClipboardData = user32.NewProc("GetClipboardData")

	kernel32              = syscall.NewLazyDLL("kernel32.dll")
	procGlobalLock        = kernel32.NewProc("GlobalLock")
	procGlobalUnlock      = kernel32.NewProc("GlobalUnlock")
)

const cfUnicodeText = 13

// readLine reads a line of input with proper Ctrl+V paste and backspace support.
// Reads in raw mode character by character.
func readLine() string {
	con, err := os.Open("CONIN$")
	if err != nil {
		return ""
	}
	defer con.Close()

	h := windows.Handle(con.Fd())
	var origMode uint32
	windows.GetConsoleMode(h, &origMode)
	// Raw mode: no line input, no echo, enable virtual terminal input
	windows.SetConsoleMode(h, windows.ENABLE_PROCESSED_INPUT|windows.ENABLE_VIRTUAL_TERMINAL_INPUT)
	defer windows.SetConsoleMode(h, origMode)

	// Also disable echo on os.Stdin — after bubbletea restores console mode,
	// stdin may still have ENABLE_ECHO_INPUT set on the same input buffer,
	// which causes characters to be echoed twice (system + our manual echo).
	stdinH := windows.Handle(os.Stdin.Fd())
	var stdinMode uint32
	if windows.GetConsoleMode(stdinH, &stdinMode) == nil {
		windows.SetConsoleMode(stdinH, stdinMode&^(windows.ENABLE_ECHO_INPUT|windows.ENABLE_LINE_INPUT))
		defer windows.SetConsoleMode(stdinH, stdinMode)
	}

	var buf []byte
	b := make([]byte, 4)
	for {
		n, err := con.Read(b)
		if err != nil || n == 0 {
			break
		}

		for i := 0; i < n; i++ {
			ch := b[i]
			switch {
			case ch == '\r' || ch == '\n':
				fmt.Print("\n")
				return string(buf)
			case ch == 0x16: // Ctrl+V
				clip := getClipboardText()
				if clip != "" {
					buf = append(buf, []byte(clip)...)
					fmt.Print(clip)
				}
			case ch == 0x1b: // Escape
				fmt.Print("\n")
				return ""
			case ch == 0x08 || ch == 0x7f: // Backspace
				if len(buf) > 0 {
					buf = buf[:len(buf)-1]
					fmt.Print("\b \b")
				}
			case ch >= 32:
				buf = append(buf, ch)
				fmt.Printf("%c", ch)
			}
		}
	}
	return string(buf)
}

func getClipboardText() string {
	ret, _, _ := procOpenClipboard.Call(0)
	if ret == 0 {
		return ""
	}
	defer procCloseClipboard.Call()

	h, _, _ := procGetClipboardData.Call(cfUnicodeText)
	if h == 0 {
		return ""
	}

	ptr, _, _ := procGlobalLock.Call(h)
	if ptr == 0 {
		return ""
	}
	defer procGlobalUnlock.Call(h)

	return syscall.UTF16ToString((*[1 << 20]uint16)(unsafe.Pointer(ptr))[:])
}
