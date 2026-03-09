package config

import (
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
)

type Config struct {
	Hotkey     HotkeyConfig     `toml:"hotkey"`
	Appearance AppearanceConfig `toml:"appearance"`
	Theme      ThemeConfig      `toml:"theme"`
	Terminal   TerminalConfig   `toml:"terminal"`
	Projects   ProjectsConfig   `toml:"projects"`
}

type HotkeyConfig struct {
	Toggle string `toml:"toggle"`
}

type AppearanceConfig struct {
	FontFamily string  `toml:"font_family"`
	FontSize   float64 `toml:"font_size"`
}

type ThemeConfig struct {
	Name string `toml:"name"`
}

type TerminalConfig struct {
	App string `toml:"app"`
}

type ProjectsConfig struct {
	Editor string   `toml:"editor"`
	Dirs   []string `toml:"dirs"`
}

func Default() Config {
	return Config{
		Hotkey:     HotkeyConfig{Toggle: "Super+Space"},
		Appearance: AppearanceConfig{FontFamily: "CaskaydiaMono NF", FontSize: 13},
		Theme:      ThemeConfig{Name: "catppuccin-mocha"},
		Terminal:   TerminalConfig{App: "alacritty"},
		Projects:   ProjectsConfig{Editor: "code"},
	}
}

func Load() Config {
	cfg := Default()
	path := configPath()
	if _, err := os.Stat(path); err != nil {
		return cfg
	}
	_, _ = toml.DecodeFile(path, &cfg)
	if cfg.Hotkey.Toggle == "" {
		cfg.Hotkey.Toggle = "Super+Space"
	}
	if cfg.Theme.Name == "" {
		cfg.Theme.Name = "catppuccin-mocha"
	}
	if cfg.Terminal.App == "" {
		cfg.Terminal.App = "alacritty"
	}
	if cfg.Appearance.FontFamily == "" {
		cfg.Appearance.FontFamily = "CaskaydiaMono NF"
	}
	if cfg.Appearance.FontSize == 0 {
		cfg.Appearance.FontSize = 13
	}
	if cfg.Projects.Editor == "" {
		cfg.Projects.Editor = "code"
	}
	return cfg
}

// SaveTheme updates the theme name in the config file.
func SaveTheme(name string) error {
	cfg := Load()
	cfg.Theme.Name = name
	return Save(cfg)
}

// SaveFont updates the font family in the config file.
func SaveFont(family string) error {
	cfg := Load()
	cfg.Appearance.FontFamily = family
	return Save(cfg)
}

// SaveEditor updates the editor in the config file.
func SaveEditor(editor string) error {
	cfg := Load()
	cfg.Projects.Editor = editor
	return Save(cfg)
}

// SaveProjectDirs updates the project scan directories in the config file.
func SaveProjectDirs(dirs []string) error {
	cfg := Load()
	cfg.Projects.Dirs = dirs
	return Save(cfg)
}

// Save writes the full config to disk.
func Save(cfg Config) error {
	path := configPath()
	os.MkdirAll(filepath.Dir(path), 0o755)
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
