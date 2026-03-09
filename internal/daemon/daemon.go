package daemon

import (
	"fmt"
	"os"
	"os/exec"
	"time"

	"github.com/nulifyer/karchy/internal/logging"
)

// Start launches the daemon as a background process.
func Start() {
	if isRunning() {
		fmt.Println("Daemon is already running.")
		return
	}

	exePath, err := os.Executable()
	if err != nil {
		fmt.Println("Failed to get executable path:", err)
		os.Exit(1)
	}

	args := []string{"daemon", "run"}
	if logging.Enabled() {
		args = append([]string{"--debug"}, args...)
	}
	cmd := exec.Command(exePath, args...)
	hideProcess(cmd)

	if err := cmd.Start(); err != nil {
		fmt.Println("Failed to start daemon:", err)
		os.Exit(1)
	}

	fmt.Println("Daemon started.")
}

// Stop kills the running daemon.
func Stop() {
	if !isRunning() {
		fmt.Println("Daemon is not running.")
		return
	}
	stopDaemon()
	fmt.Println("Daemon stopped.")
}

// Restart stops and restarts the daemon.
func Restart() {
	if isRunning() {
		stopDaemon()
		time.Sleep(500 * time.Millisecond)
	}
	Start()
}

// Status prints whether the daemon is running.
func Status() {
	if isRunning() {
		fmt.Println("Daemon is running.")
	} else {
		fmt.Println("Daemon is not running.")
	}
}

// Run is the internal entry point for the daemon process.
// Platform-specific run() is defined in daemon_windows.go / daemon_unix.go.
func Run() {
	run()
}
