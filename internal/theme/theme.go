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

// TUIColors holds the resolved colors for the TUI style targets.
type TUIColors struct {
	Accent string
	FG     string
	Dim    string
	Green  string
	Yellow string
}

// TUIOverrides returns per-theme TUI color corrections for themes where the
// default mapping (accent=blue, fg=white, dim=bright.black, green=green,
// yellow=yellow) produces clashing or semantically wrong colors.
// Only the overridden fields are non-empty.
func TUIOverrides(name string) TUIColors {
	o, _ := tuiOverrides[name]
	return o
}

var tuiOverrides = map[string]TUIColors{
	// green (#A9B665) and yellow (#D8A657) are both warm olive/amber — too close.
	// Use red for the "updatable" indicator.
	"gruvbox": {Yellow: "#EA6962"},

	// Same olive/gold clash as gruvbox dark.
	"gruvbox_light": {Yellow: "#CC241D"},

	// green (#859900 olive) and yellow (#B58900 gold) are nearly identical hues.
	"solarized": {Yellow: "#DC322F"},

	// green (#8DA101 olive) and yellow (#DFA000 amber) are too close.
	"everforest_light": {Yellow: "#F85552"},

	// green (#66800B) and yellow (#AD8301) — both dark olive/brown.
	"flexoki_light": {Yellow: "#AF3029"},

	// blue (#31748F) and green (#9CCFD8) are both blue-cyan.
	// Use iris (magenta) as accent — it's Rosé Pine's identity color.
	"rose_pine": {Accent: "#C4A7E7"},

	// Same blue-teal clash as rose_pine dark.
	"rose_pine_dawn": {Accent: "#907AA9"},

	// blue (#26BBD9) and green (#29D398) are both cyan-mint.
	// Use the pink as accent — it's Horizon's signature.
	"horizon": {Accent: "#EE64AC"},

	// "yellow" (#08BDBA) is actually cyan — doesn't read as "needs attention".
	"carbonfox": {Yellow: "#EE5396"},

	// Same cyan-as-yellow issue as carbonfox.
	"oxocarbon": {Yellow: "#EE5396"},

	// blue, green, and cyan are all #99FFE4 (identical).
	// magenta and yellow are both #FFC799. Only 3 distinct colors total.
	"vesper": {Accent: "#FFC799", Green: "#99FFE4", Yellow: "#FF8080"},
}
