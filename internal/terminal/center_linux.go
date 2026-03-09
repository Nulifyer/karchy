//go:build linux

package terminal

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/nulifyer/karchy/internal/logging"
)

// screenSize returns the primary screen resolution via KWin's D-Bus interface.
// Falls back to 1920x1080 if qdbus6/KWin is unavailable (non-KDE desktops).
func screenSize() (int, int) {
	out, err := exec.Command("qdbus6", "org.kde.KWin", "/KWin",
		"org.kde.KWin.supportInformation").Output()
	if err == nil {
		for _, line := range strings.Split(string(out), "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "Geometry:") {
				parts := strings.Fields(line)
				if len(parts) >= 2 {
					geom := parts[len(parts)-1]
					if idx := strings.LastIndex(geom, ","); idx >= 0 {
						wh := geom[idx+1:]
						var w, h int
						if _, err := fmt.Sscanf(wh, "%dx%d", &w, &h); err == nil && w > 0 && h > 0 {
							return w, h
						}
					}
				}
			}
		}
	}
	return 1920, 1080
}

// ResizeAndCenter finds the Alacritty window by PID via a KWin script,
// derives cell size from its current geometry, computes the new pixel size,
// and resizes + centers it. Currently KDE Plasma only (uses qdbus6 + KWin scripting).
func ResizeAndCenter(cols, lines int) {
	if launchCols <= 0 || launchLines <= 0 {
		logging.Info("ResizeAndCenter: no launch dimensions")
		return
	}

	ppid := os.Getppid()
	sw, sh := screenSize()

	// KWin script: find window by PID, compute new size from cell ratio, resize and center.
	// curW/launchCols gives cell width in pixels, multiply by target cols for new width.
	script := fmt.Sprintf(`
var clients = workspace.windowList();
for (var i = 0; i < clients.length; i++) {
    var c = clients[i];
    if (c.pid === %d) {
        var curW = c.frameGeometry.width;
        var curH = c.frameGeometry.height;
        var cellW = curW / %d;
        var cellH = curH / %d;
        var newW = Math.round(cellW * %d);
        var newH = Math.round(cellH * %d);
        var x = Math.max(0, Math.round((%d - newW) / 2));
        var y = Math.max(0, Math.round((%d - newH) / 2));
        c.frameGeometry = {x: x, y: y, width: newW, height: newH};
        console.log("karchy-resize: pid=%d cur=" + curW + "x" + curH + " cell=" + cellW.toFixed(1) + "x" + cellH.toFixed(1) + " new=" + newW + "x" + newH + " pos=" + x + "," + y);
        break;
    }
}
`, ppid, launchCols, launchLines, cols, lines, sw, sh, ppid)

	err := runKWinScript(script)
	if err != nil {
		logging.Info("ResizeAndCenter: kwin script failed: %v", err)
		return
	}

	logging.Info("ResizeAndCenter: %dx%d -> %dx%d via KWin (ppid=%d, screen=%dx%d)",
		launchCols, launchLines, cols, lines, ppid, sw, sh)

	launchCols = cols
	launchLines = lines
}

// runKWinScript writes a temporary JS file, loads it via KWin scripting D-Bus, runs it, then unloads.
func runKWinScript(script string) error {
	tmpFile, err := os.CreateTemp("", "karchy-kwin-*.js")
	if err != nil {
		return err
	}
	defer os.Remove(tmpFile.Name())

	if _, err := tmpFile.WriteString(script); err != nil {
		tmpFile.Close()
		return err
	}
	tmpFile.Close()

	out, err := exec.Command("qdbus6", "org.kde.KWin", "/Scripting",
		"org.kde.kwin.Scripting.loadScript", tmpFile.Name(), "karchy-resize").CombinedOutput()
	if err != nil {
		return fmt.Errorf("loadScript: %w (%s)", err, strings.TrimSpace(string(out)))
	}

	logging.Info("runKWinScript: loaded id=%s", strings.TrimSpace(string(out)))

	_, err = exec.Command("qdbus6", "org.kde.KWin", "/Scripting",
		"org.kde.kwin.Scripting.start").CombinedOutput()
	if err != nil {
		return fmt.Errorf("start: %w", err)
	}

	exec.Command("qdbus6", "org.kde.KWin", "/Scripting",
		"org.kde.kwin.Scripting.unloadScript", "karchy-resize").Run()

	return nil
}

// HasVisibleWindow is not needed on Linux; always returns false.
func HasVisibleWindow(pid int) bool { return false }

// FindAndCenterByPID is not used on Linux; returns 0.
func FindAndCenterByPID(pid int) uintptr { return 0 }

// FocusHwnd is not used on Linux.
func FocusHwnd(hwnd uintptr) {}
