//go:build windows

package terminal

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"
)

func init() {
	RegisterBackend(&wtBackend{})
}

type wtBackend struct{}

func (w *wtBackend) Name() string   { return "wt" }
func (w *wtBackend) Binary() string { return "wt" }

func (w *wtBackend) LaunchArgs(opts LaunchOpts, childArgs []string) []string {
	args := []string{"-w", "new"}

	if opts.Borderless && opts.Cols > 0 && opts.Lines > 0 {
		args = append(args, "--focus")
		args = append(args, "--size", fmt.Sprintf("%d,%d", opts.Cols, opts.Lines))
		if opts.PosX != 0 || opts.PosY != 0 {
			args = append(args, "--pos", fmt.Sprintf("%d,%d", opts.PosX, opts.PosY))
		}
	}

	// Resolve which WT profile to use:
	// 1. Explicit config override
	// 2. WT_PROFILE_ID env var (set by WT in every session — matches the user's active profile)
	// 3. Default profile from settings.json
	profile := opts.Profile
	if profile == "" {
		profile = wtDetectProfile()
	}

	if opts.Title != "" || profile != "" || len(childArgs) > 0 {
		args = append(args, "new-tab")
		if profile != "" {
			args = append(args, "-p", profile)
		}
		if opts.Title != "" {
			args = append(args, "--title", opts.Title, "--suppressApplicationTitle")
		}
	}

	if len(childArgs) > 0 {
		// Wrap in cmd /c "... & exit 0" so WT always sees exit code 0
		// and closes the tab instead of showing "process exited with code ...".
		quoted := childArgs[0]
		for _, a := range childArgs[1:] {
			quoted += " " + a
		}
		args = append(args, "--", "cmd", "/c", quoted+" & exit 0")
	}

	return args
}

// wtDetectProfile returns the WT profile identifier to use.
// It prefers the WT_PROFILE_ID env var (GUID of the session the daemon was launched from),
// then falls back to reading the defaultProfile from settings.json.
// Returns a GUID string like "{...}" which wt -p accepts directly.
var (
	wtProfileOnce sync.Once
	wtProfileID   string
)

func wtDetectProfile() string {
	wtProfileOnce.Do(func() {
		// First: check if we're running inside a WT session
		if id := os.Getenv("WT_PROFILE_ID"); id != "" {
			wtProfileID = id
			return
		}
		// Fallback: read default profile GUID from settings.json
		wtProfileID = wtDefaultProfileGUID()
	})
	return wtProfileID
}

func wtDefaultProfileGUID() string {
	localAppData := os.Getenv("LOCALAPPDATA")
	if localAppData == "" {
		return ""
	}

	paths := []string{
		filepath.Join(localAppData, "Packages", "Microsoft.WindowsTerminal_8wekyb3d8bbwe", "LocalState", "settings.json"),
		filepath.Join(localAppData, "Packages", "Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe", "LocalState", "settings.json"),
		filepath.Join(localAppData, "Microsoft", "Windows Terminal", "settings.json"),
	}

	for _, p := range paths {
		if guid := parseWTDefaultGUID(p); guid != "" {
			return guid
		}
	}
	return ""
}

func parseWTDefaultGUID(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}

	var settings struct {
		DefaultProfile string `json:"defaultProfile"`
	}
	if err := json.Unmarshal(data, &settings); err != nil {
		return ""
	}
	return settings.DefaultProfile
}
