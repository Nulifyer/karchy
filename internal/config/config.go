package config

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"

	"github.com/BurntSushi/toml"
	"github.com/nulifyer/karchy/internal/theme"
)

type Config struct {
	Hotkey   HotkeyConfig   `toml:"hotkey"`
	Terminal TerminalConfig `toml:"terminal"`
	Projects ProjectsConfig `toml:"projects"`
	Window   WindowConfig   `toml:"window"`
	Theme    ThemeConfig    `toml:"theme"`
}

type ThemeConfig struct {
	Name    string `toml:"name,omitempty"`    // theme key from colors.json (e.g. "catppuccin_mocha")
	Variant string `toml:"variant,omitempty"` // "dark" or "light" — auto-set from colors.json

	// TUI-specific overrides (take precedence over theme-derived values)
	Accent string `toml:"accent,omitempty"` // borders, highlights, selected items (default: ANSI 4)
	Fg     string `toml:"fg,omitempty"`     // normal text (default: ANSI 7)
	Dim    string `toml:"dim,omitempty"`    // hints, secondary text (default: ANSI 8)
	Green  string `toml:"green,omitempty"`  // checked/installed indicators (default: ANSI 2)
	Yellow string `toml:"yellow,omitempty"` // picked/updatable indicators (default: ANSI 3)

	// Full theme structure (mirrors colors.json)
	Prompt   ThemePromptConfig   `toml:"prompt,omitempty"`
	Terminal ThemeTerminalConfig `toml:"terminal,omitempty"`
}

type ThemePromptConfig struct {
	OS       string `toml:"os,omitempty"`
	User     string `toml:"user,omitempty"`
	Path     string `toml:"path,omitempty"`
	Git      string `toml:"git,omitempty"`
	OK       string `toml:"ok,omitempty"`
	Err      string `toml:"err,omitempty"`
	Duration string `toml:"duration,omitempty"`
}

type ThemeTerminalConfig struct {
	BG        string             `toml:"bg,omitempty"`
	FG        string             `toml:"fg,omitempty"`
	Cursor    string             `toml:"cursor,omitempty"`
	Selection string             `toml:"selection,omitempty"`
	Normal    ThemePaletteConfig `toml:"normal,omitempty"`
	Bright    ThemePaletteConfig `toml:"bright,omitempty"`
}

type ThemePaletteConfig struct {
	Black   string `toml:"black,omitempty"`
	Red     string `toml:"red,omitempty"`
	Green   string `toml:"green,omitempty"`
	Yellow  string `toml:"yellow,omitempty"`
	Blue    string `toml:"blue,omitempty"`
	Magenta string `toml:"magenta,omitempty"`
	Cyan    string `toml:"cyan,omitempty"`
	White   string `toml:"white,omitempty"`
}

// Resolve returns the effective TUI colors by layering: ANSI defaults → theme → explicit overrides.
func (tc ThemeConfig) Resolve() (accent, fg, dim, green, yellow string) {
	// Start with ANSI defaults
	accent, fg, dim, green, yellow = "4", "7", "8", "2", "3"

	// If a named theme is set, derive from its palette using the field mapping
	if tc.Name != "" {
		if t, ok := theme.Load(tc.Name); ok {
			m := theme.TUIFieldMap(tc.Name)
			accent, fg, dim, green, yellow = theme.ResolveTUI(t, m)
		}
	}

	// Explicit overrides take precedence
	if tc.Accent != "" {
		accent = tc.Accent
	}
	if tc.Fg != "" {
		fg = tc.Fg
	}
	if tc.Dim != "" {
		dim = tc.Dim
	}
	if tc.Green != "" {
		green = tc.Green
	}
	if tc.Yellow != "" {
		yellow = tc.Yellow
	}
	return
}

// WindowConfig controls window placement behavior.
type WindowConfig struct {
	// SummonOn determines which monitor the menu appears on.
	// Values: "mouse" (default), "primary", "active_window"
	SummonOn string `toml:"summon_on"`
}

type HotkeyConfig struct {
	Toggle       string `toml:"toggle"`
	OpenTerminal string `toml:"open_terminal"`
}

type TerminalConfig struct {
	App     string `toml:"app"`
	Profile string `toml:"profile"` // WT profile name (e.g. "PowerShell", "Ubuntu")
}

type ProjectsConfig struct {
	Editor string `toml:"editor"`
}

func defaultTerminalApp() string {
	if runtime.GOOS == "windows" {
		return "wt"
	}
	return ""
}

func Default() Config {
	return Config{
		Hotkey:   HotkeyConfig{Toggle: "Super+Space", OpenTerminal: "Super+Return"},
		Terminal: TerminalConfig{App: defaultTerminalApp()},
		Projects: ProjectsConfig{Editor: "code"},
		Window:   WindowConfig{SummonOn: "mouse"},
	}
}

func Load() Config {
	cfg := Default()
	path := configPath()
	if _, err := os.Stat(path); err != nil {
		return cfg
	}
	if _, err := toml.DecodeFile(path, &cfg); err != nil {
		fmt.Fprintf(os.Stderr, "karchy: warning: config parse error: %v\n", err)
	}
	if cfg.Hotkey.Toggle == "" {
		cfg.Hotkey.Toggle = "Super+Space"
	}
	if cfg.Terminal.App == "" {
		cfg.Terminal.App = defaultTerminalApp()
	}
	if cfg.Projects.Editor == "" {
		cfg.Projects.Editor = "code"
	}
	if cfg.Window.SummonOn == "" {
		cfg.Window.SummonOn = "mouse"
	}
	return cfg
}

// SaveTerminal updates the terminal app in the config file.
func SaveTerminal(app string) error {
	cfg := Load()
	cfg.Terminal.App = app
	return Save(cfg)
}

// SaveEditor updates the editor in the config file.
func SaveEditor(editor string) error {
	cfg := Load()
	cfg.Projects.Editor = editor
	return Save(cfg)
}

// SaveTheme updates the theme name in the config file.
func SaveTheme(name string) error {
	cfg := Load()
	cfg.Theme = ThemeConfig{Name: name}
	return Save(cfg)
}

// Save writes the full config to disk.
func Save(cfg Config) error {
	path := configPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return fmt.Errorf("create config dir: %w", err)
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return toml.NewEncoder(f).Encode(cfg)
}

func configPath() string {
	if dir, err := os.UserConfigDir(); err == nil {
		return filepath.Join(dir, "karchy", "config.toml")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "karchy", "config.toml")
}
