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
