//go:build windows

package main

import (
	"fmt"
	"os"
	"os/exec"

	"golang.org/x/sys/windows"
)

// runAndWait executes a command with stdout/stderr attached, then waits for a keypress.
func runAndWait(args []string) {
	if len(args) == 0 {
		fmt.Println("Usage: karchy install-run <command> [args...]")
		os.Exit(1)
	}

	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	err := cmd.Run()
	if err != nil {
		fmt.Printf("\n\033[31mFailed: %v\033[0m\n", err)
	} else {
		fmt.Print("\n\033[32mDone! Press any key...\033[0m")
	}

	// Open CONIN$ directly — works reliably in conpty/Alacritty
	// unlike os.Stdin which may be in a broken state after child process
	con, cerr := os.Open("CONIN$")
	if cerr != nil {
		return
	}
	defer con.Close()
	h := windows.Handle(con.Fd())
	var mode uint32
	if windows.GetConsoleMode(h, &mode) == nil {
		windows.SetConsoleMode(h, mode&^(windows.ENABLE_LINE_INPUT|windows.ENABLE_ECHO_INPUT))
		defer windows.SetConsoleMode(h, mode)
	}
	buf := make([]byte, 1)
	con.Read(buf)
}
