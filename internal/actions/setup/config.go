package setup

import (
	"os/exec"
	"path/filepath"

	"github.com/nulifyer/karchy/internal/actions/projects"
	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/platform"
	cfgterminal "github.com/nulifyer/karchy/internal/terminal"
)

// OpenConfig opens the karchy config file in the user's configured editor.
// If the file does not yet exist, a default one is written to disk first.
// Terminal-based editors (nvim, vim) are launched inside a new terminal
// window whose working directory is the config directory.
func OpenConfig() {
	path, err := config.EnsureExists()
	if err != nil {
		logging.Error("OpenConfig: ensure config: %v", err)
		return
	}

	editor := projects.CurrentEditor()
	ed := projects.FindEditor(editor)
	logging.Info("OpenConfig: %s (terminal=%v) %s", editor, ed.Terminal, path)

	if ed.Terminal {
		cfg := config.Load()
		b := cfgterminal.GetBackend(cfg.Terminal.App)
		childArgs := []string{editor, path}
		cmdArgs := b.LaunchArgs(cfgterminal.LaunchOpts{}, childArgs)

		cmd := exec.Command(b.Binary(), cmdArgs...)
		cmd.Dir = filepath.Dir(path)
		platform.Detach(cmd)
		cmd.Start()
		return
	}

	cmd := exec.Command(editor, path)
	platform.Detach(cmd)
	cmd.Start()
}
