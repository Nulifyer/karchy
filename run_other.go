//go:build !windows

package main

import (
	"fmt"
	"os"
	"os/exec"
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

	buf := make([]byte, 1)
	os.Stdin.Read(buf)
}
