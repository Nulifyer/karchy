package projects

import (
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/set"
	"github.com/nulifyer/karchy/internal/platform"
)

type ProjectEntry struct {
	Name string
	Path string
}

// Markers that indicate a directory is a project root.
// If found, we add the directory and stop recursing into it.
var projectMarkers = set.New(
	// VCS
	".git",
	// IDE/Editor
	".vscode",
	".idea",
	// Go
	"go.mod",
	// Rust
	"Cargo.toml",
	// JS/TS
	"package.json",
	"deno.json",
	// Python
	"pyproject.toml",
	// PHP
	"composer.json",
	// Ruby
	"Gemfile",
	// Elixir
	"mix.exs",
	// Dart/Flutter
	"pubspec.yaml",
	// .NET
	".sln",
	// Java
	"pom.xml",
	"build.gradle",
	// C/C++
	"CMakeLists.txt",
	// Nix
	"flake.nix",
	// Unity
	"ProjectSettings",
)

// Directories to always skip when scanning.
// Note: all dot-prefixed dirs are already skipped by the HasPrefix(".") check.
var skipDirs = set.New(
	// JS / Node
	"node_modules",
	// Python
	"__pycache__",
	"venv",
	// Rust / Java
	"target",
	// .NET
	"bin",
	"obj",
	"packages",
	// Go
	"vendor",
	// Build output
	"dist",
	"build",
	// Unity
	"Library",
	"Temp",
	"Logs",
	"PackageCache",
	// Windows
	"AppData",
)

// Directories to skip only at the scan root (depth 1 from home).
// These are common home-level folders that aren't project containers.
var skipRootDirs = set.New(
	// Go SDK
	"go",
	// Windows user folders
	"Music",
	"Videos",
	"Pictures",
	"Downloads",
	"Desktop",
	"Favorites",
	"Contacts",
	"Links",
	"Saved Games",
	"Searches",
	"3D Objects",
	"OneDrive",
	// macOS
	"Library",
	"Applications",
	"Movies",
	"Public",
	// Linux
	"snap",
	// Package managers
	"scoop",
	"miniconda3",
	"anaconda3",
)

// maxDepth limits how deep we recurse from each scan root.
const maxDepth = 50

// Scan discovers project directories by scanning from $HOME.
func Scan() []ProjectEntry {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil
	}

	seen := set.New[string]()
	var entries []ProjectEntry
	scanProjects(home, 0, seen, &entries)

	sort.Slice(entries, func(i, j int) bool {
		return strings.ToLower(entries[i].Name) < strings.ToLower(entries[j].Name)
	})
	return entries
}

func scanProjects(dir string, depth int, seen set.Set[string], entries *[]ProjectEntry) {
	if depth > maxDepth {
		return
	}

	if seen.Contains(dir) {
		return
	}

	// Don't treat scan roots (depth 0) as projects — e.g. ~ has .vscode
	if depth > 0 && isProject(dir) {
		seen.Add(dir)
		name := filepath.Base(dir)
		*entries = append(*entries, ProjectEntry{Name: name, Path: dir})
		return // don't recurse into project subdirectories
	}

	children, err := os.ReadDir(dir)
	if err != nil {
		return
	}

	for _, child := range children {
		if !child.IsDir() {
			continue
		}
		name := child.Name()
		if strings.HasPrefix(name, ".") {
			continue
		}
		if skipDirs.Contains(name) {
			continue
		}
		if depth == 0 && skipRootDirs.Contains(name) {
			continue
		}
		scanProjects(filepath.Join(dir, name), depth+1, seen, entries)
	}
}

func isProject(dir string) bool {
	children, err := os.ReadDir(dir)
	if err != nil {
		return false
	}
	for _, child := range children {
		if projectMarkers.Contains(child.Name()) {
			return true
		}
	}
	return false
}

// Open launches the project in the configured editor.
func Open(entry ProjectEntry) {
	editor := CurrentEditor()
	ed := findEditor(editor)
	logging.Info("projects.Open: %s (terminal=%v) %s", editor, ed.Terminal, entry.Path)

	if ed.Terminal {
		openInTerminal(editor, entry.Path)
	} else {
		cmd := exec.Command(editor, entry.Path)
		platform.Detach(cmd)
		cmd.Start()
	}
}

func openInTerminal(editor, path string) {
	cfg := config.Load()
	terminal := cfg.Terminal.App
	if terminal == "" {
		terminal = "alacritty"
	}

	var cmd *exec.Cmd
	switch terminal {
	case "alacritty":
		cmd = exec.Command(terminal, "-e", editor, path)
	case "wezterm":
		cmd = exec.Command(terminal, "start", "--", editor, path)
	case "wt":
		cmd = exec.Command(terminal, "new-tab", "--", editor, path)
	case "kitty":
		cmd = exec.Command(terminal, editor, path)
	default:
		cmd = exec.Command(terminal, "-e", editor, path)
	}
	cmd.Dir = path
	cmd.Start()
}

func findEditor(command string) Editor {
	for _, ed := range AllEditors {
		if ed.Command == command {
			return ed
		}
	}
	return Editor{Name: command, Command: command}
}

// Editor represents a known code editor.
type Editor struct {
	Name     string
	Command  string
	Terminal bool // true if the editor runs inside a terminal
}

// AllEditors is the full list of known editors.
var AllEditors = []Editor{
	{"VS Code", "code", false},
	{"Cursor", "cursor", false},
	{"Zed", "zed", false},
	{"Neovim", "nvim", true},
	{"Vim", "vim", true},
	{"Sublime Text", "subl", false},
	{"IntelliJ IDEA", "idea", false},
	{"GoLand", "goland", false},
	{"WebStorm", "webstorm", false},
	{"Fleet", "fleet", false},
}

// IsAvailable checks if a command exists on PATH.
func IsAvailable(command string) bool {
	_, err := exec.LookPath(command)
	return err == nil
}

// AvailableEditors returns only editors found on PATH.
func AvailableEditors() []Editor {
	var available []Editor
	for _, ed := range AllEditors {
		if IsAvailable(ed.Command) {
			available = append(available, ed)
		}
	}
	return available
}

// DefaultEditor returns the first available editor command, or "code" as fallback.
func DefaultEditor() string {
	for _, ed := range AllEditors {
		if IsAvailable(ed.Command) {
			return ed.Command
		}
	}
	return "code"
}

// CurrentEditor returns the configured editor, falling back to the first available one.
func CurrentEditor() string {
	cfg := config.Load()
	if cfg.Projects.Editor != "" && IsAvailable(cfg.Projects.Editor) {
		return cfg.Projects.Editor
	}
	return DefaultEditor()
}
