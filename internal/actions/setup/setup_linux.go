//go:build linux

package setup

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/platform"
)

// isKDE returns true if the current desktop session is KDE Plasma.
func isKDE() bool {
	de := os.Getenv("XDG_CURRENT_DESKTOP")
	return de == "KDE" || de == "plasma"
}

// tryRun tries each command in order and runs the first one found on PATH.
// On KDE, it centers the launched window after a short delay.
func tryRun(cmds ...[]string) {
	for _, args := range cmds {
		if _, err := exec.LookPath(args[0]); err == nil {
			cmd := exec.Command(args[0], args[1:]...)
			platform.Detach(cmd)
			if err := cmd.Start(); err != nil {
				return
			}
			if isKDE() {
				centerWindowByPID(cmd.Process.Pid)
			}
			return
		}
	}
}

// centerWindowByPID polls for the window to appear (up to 2s), then centers it via KWin scripting.
func centerWindowByPID(pid int) {
	// The KWin script returns "found" if the window exists and was centered,
	// or nothing if not found yet. We poll until it's found.
	script := fmt.Sprintf(`
var clients = workspace.windowList();
for (var i = 0; i < clients.length; i++) {
    var c = clients[i];
    if (c.pid === %d) {
        var area = workspace.clientArea(0, c);
        var x = Math.round(area.x + (area.width - c.frameGeometry.width) / 2);
        var y = Math.round(area.y + (area.height - c.frameGeometry.height) / 2);
        c.frameGeometry = {x: x, y: y, width: c.frameGeometry.width, height: c.frameGeometry.height};
        break;
    }
}
`, pid)

	tmpFile, err := os.CreateTemp("", "karchy-center-*.js")
	if err != nil {
		return
	}
	defer os.Remove(tmpFile.Name())
	tmpFile.WriteString(script)
	tmpFile.Close()

	out, err := exec.Command("qdbus6", "org.kde.KWin", "/Scripting",
		"org.kde.kwin.Scripting.loadScript", tmpFile.Name(), "karchy-center").CombinedOutput()
	if err != nil {
		logging.Info("centerWindowByPID: loadScript: %v (%s)", err, strings.TrimSpace(string(out)))
		return
	}

	exec.Command("qdbus6", "org.kde.KWin", "/Scripting",
		"org.kde.kwin.Scripting.start").CombinedOutput()

	exec.Command("qdbus6", "org.kde.KWin", "/Scripting",
		"org.kde.kwin.Scripting.unloadScript", "karchy-center").Run()
}

func Audio() {
	if isKDE() {
		tryRun(
			[]string{"kcmshell6", "kcm_pulseaudio"},
		)
	} else {
		tryRun(
			[]string{"gnome-control-center", "sound"},
			[]string{"pavucontrol"},
		)
	}
}

func WiFi() {
	if isKDE() {
		tryRun(
			[]string{"kcmshell6", "kcm_networkmanagement"},
		)
	} else {
		tryRun(
			[]string{"gnome-control-center", "wifi"},
			[]string{"nm-connection-editor"},
		)
	}
}

func Bluetooth() {
	if isKDE() {
		tryRun(
			[]string{"kcmshell6", "kcm_bluetooth"},
		)
	} else {
		tryRun(
			[]string{"gnome-control-center", "bluetooth"},
			[]string{"blueman-manager"},
		)
	}
}

func Display() {
	if isKDE() {
		tryRun(
			[]string{"kcmshell6", "kcm_kscreen"},
		)
	} else {
		tryRun(
			[]string{"gnome-control-center", "display"},
			[]string{"arandr"},
		)
	}
}

func Power() {
	if isKDE() {
		tryRun(
			[]string{"kcmshell6", "kcm_energyinfo"},
		)
	} else {
		tryRun(
			[]string{"gnome-control-center", "power"},
		)
	}
}

func Timezone() {
	if isKDE() {
		tryRun(
			[]string{"kcmshell6", "kcm_clock"},
		)
	} else {
		tryRun(
			[]string{"gnome-control-center", "datetime"},
		)
	}
}

func WinUtil() {}
