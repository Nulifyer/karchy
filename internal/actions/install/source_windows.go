//go:build windows

package install

import (
	"context"
	"os/exec"
	"syscall"
	"time"

	"github.com/nulifyer/karchy/internal/logging"
)

// RefreshSources runs `winget source update` to refresh the local source index
// before reads. Hidden window, bounded timeout. Equivalent to `apt update`.
func RefreshSources() {
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	start := time.Now()
	cmd := exec.CommandContext(ctx, "winget", "source", "update", "--disable-interactivity")
	cmd.SysProcAttr = &syscall.SysProcAttr{CreationFlags: 0x08000000} // CREATE_NO_WINDOW

	out, err := cmd.CombinedOutput()
	elapsed := time.Since(start).Round(time.Millisecond)
	if err != nil {
		logging.Info("RefreshSources: failed after %s: %v: %s", elapsed, err, string(out))
		return
	}
	logging.Info("RefreshSources: ok in %s", elapsed)
}
