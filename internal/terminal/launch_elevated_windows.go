//go:build windows

package terminal

import (
	"fmt"
	"strings"
	"syscall"
	"unsafe"

	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/theme"
)

var (
	shell32dll        = syscall.NewLazyDLL("shell32.dll")
	procShellExecuteW = shell32dll.NewProc("ShellExecuteW")
)

// LaunchProgramElevated opens a terminal running an arbitrary program with UAC elevation.
// The terminal emulator process itself is launched elevated via ShellExecuteW runas,
// so the child program inherits the elevated token.
func LaunchProgramElevated(cols, lines int, title, program string, args ...string) error {
	cfg := config.Load()
	pal := theme.Load(cfg.Theme.Name)
	b := GetBackend(cfg.Terminal.App)
	configFile := b.WriteConfig(cols, lines, 16, 12, pal, cfg.Appearance)

	childArgs := append([]string{program}, args...)
	cmdArgs := b.LaunchArgs(configFile, title, childArgs)

	var parts []string
	for _, a := range cmdArgs {
		parts = append(parts, syscall.EscapeArg(a))
	}
	params := strings.Join(parts, " ")

	verb, _ := syscall.UTF16PtrFromString("runas")
	binary, _ := syscall.UTF16PtrFromString(b.Binary())
	paramsPtr, _ := syscall.UTF16PtrFromString(params)

	ret, _, _ := procShellExecuteW.Call(
		0,
		uintptr(unsafe.Pointer(verb)),
		uintptr(unsafe.Pointer(binary)),
		uintptr(unsafe.Pointer(paramsPtr)),
		0,
		1, // SW_SHOWNORMAL
	)
	if ret <= 32 {
		return fmt.Errorf("ShellExecuteW returned %d", ret)
	}
	logging.Info("LaunchProgramElevated: launched %s (ret=%d)", b.Binary(), ret)
	return nil
}
