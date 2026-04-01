package theme

import (
	_ "embed"
	"encoding/json"
	"sort"
)

//go:embed colors.json
var colorsJSON []byte

// Theme represents a single color theme from colors.json.
type Theme struct {
	Name          string       `json:"name"`
	Variant       string       `json:"variant"`
	BatTheme      string       `json:"bat_theme"`
	LutgenPalette string       `json:"lutgen_palette"`
	Prompt        PromptColors `json:"prompt"`
	Terminal      Terminal     `json:"terminal"`
}

// PromptColors holds the shell prompt color values (hex without #).
type PromptColors struct {
	OS       string `json:"os"`
	User     string `json:"user"`
	Path     string `json:"path"`
	Git      string `json:"git"`
	OK       string `json:"ok"`
	Err      string `json:"err"`
	Duration string `json:"duration"`
}

// Terminal holds the full terminal color scheme.
type Terminal struct {
	BG        string  `json:"bg"`
	FG        string  `json:"fg"`
	Cursor    string  `json:"cursor"`
	Selection string  `json:"selection"`
	Normal    Palette `json:"normal"`
	Bright    Palette `json:"bright"`
}

// Palette holds the 8 ANSI colors.
type Palette struct {
	Black   string `json:"black"`
	Red     string `json:"red"`
	Green   string `json:"green"`
	Yellow  string `json:"yellow"`
	Blue    string `json:"blue"`
	Magenta string `json:"magenta"`
	Cyan    string `json:"cyan"`
	White   string `json:"white"`
}

var themes map[string]Theme

func init() {
	themes = make(map[string]Theme)
	if err := json.Unmarshal(colorsJSON, &themes); err != nil {
		panic("theme: failed to parse embedded colors.json: " + err.Error())
	}
}

// Load returns a theme by its key name. The second return value indicates
// whether the theme was found.
func Load(name string) (Theme, bool) {
	t, ok := themes[name]
	return t, ok
}

// List returns all theme keys sorted alphabetically.
func List() []string {
	keys := make([]string, 0, len(themes))
	for k := range themes {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// All returns a copy of all themes.
func All() map[string]Theme {
	out := make(map[string]Theme, len(themes))
	for k, v := range themes {
		out[k] = v
	}
	return out
}

// TUIMapping specifies which palette fields to use for TUI style targets.
// Empty strings mean "use the default" (accent=blue, fg=white, dim=bright_black,
// green=green, yellow=yellow).
type TUIMapping struct {
	Accent string // palette field name
	FG     string
	Dim    string
	Green  string
	Yellow string
}

// TUIFieldMap returns the palette field mapping for a theme's TUI colors.
func TUIFieldMap(name string) TUIMapping {
	if m, ok := tuiFieldMap[name]; ok {
		return m
	}
	return TUIMapping{}
}

// ResolveTUI returns the concrete hex colors for the TUI given a theme.
func ResolveTUI(t Theme, m TUIMapping) (accent, fg, dim, green, yellow string) {
	get := func(field, fallback string) string {
		if field == "" {
			field = fallback
		}
		return paletteField(t, field)
	}
	accent = get(m.Accent, "blue")
	fg = get(m.FG, "white")
	dim = get(m.Dim, "bright_black")
	green = get(m.Green, "green")
	yellow = get(m.Yellow, "yellow")
	return
}

func paletteField(t Theme, field string) string {
	switch field {
	case "black":
		return t.Terminal.Normal.Black
	case "red":
		return t.Terminal.Normal.Red
	case "green":
		return t.Terminal.Normal.Green
	case "yellow":
		return t.Terminal.Normal.Yellow
	case "blue":
		return t.Terminal.Normal.Blue
	case "magenta":
		return t.Terminal.Normal.Magenta
	case "cyan":
		return t.Terminal.Normal.Cyan
	case "white":
		return t.Terminal.Normal.White
	case "bright_black":
		return t.Terminal.Bright.Black
	case "bright_red":
		return t.Terminal.Bright.Red
	case "bright_green":
		return t.Terminal.Bright.Green
	case "bright_yellow":
		return t.Terminal.Bright.Yellow
	case "bright_blue":
		return t.Terminal.Bright.Blue
	case "bright_magenta":
		return t.Terminal.Bright.Magenta
	case "bright_cyan":
		return t.Terminal.Bright.Cyan
	case "bright_white":
		return t.Terminal.Bright.White
	case "fg":
		return t.Terminal.FG
	case "bg":
		return t.Terminal.BG
	case "cursor":
		return t.Terminal.Cursor
	case "selection":
		return t.Terminal.Selection
	default:
		return ""
	}
}

// Per-theme palette field mappings. Only overridden fields need to be set.
var tuiFieldMap = map[string]TUIMapping{
	// Gruvbox's identity is warm yellow. green and yellow are too close — use red for "updatable".
	"gruvbox":      {Accent: "yellow", Yellow: "red"},
	"gruvbox_light": {Accent: "yellow", Yellow: "red"},

	// green and yellow are nearly identical olive/gold hues.
	"solarized": {Yellow: "red"},

	// green and yellow are too close (olive/amber).
	"everforest_light": {Yellow: "red"},
	"flexoki_light":    {Yellow: "red"},

	// blue and green are both blue-cyan. Use magenta (iris) as accent.
	"rose_pine":      {Accent: "magenta"},
	"rose_pine_dawn": {Accent: "magenta"},

	// blue and green are both cyan-mint. Use magenta (pink) as accent.
	"horizon": {Accent: "magenta"},

	// "yellow" slot is actually cyan. Use red (pink) for "updatable".
	"carbonfox": {Yellow: "red"},
	"oxocarbon": {Yellow: "red"},

	// blue=green=cyan (identical), magenta=yellow (identical). Remap all three.
	"vesper": {Accent: "yellow", Green: "cyan", Yellow: "red"},
}
