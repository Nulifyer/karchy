package theme

import "fmt"

// Palette holds colors for Alacritty config generation.
type Palette struct {
	BG     string
	FG     string
	Accent string
	Colors [16]string // 0-7 normal, 8-15 bright
}

var builtins = map[string]Palette{
	"catppuccin-mocha": build("#1e1e2e", "#cdd6f4", "#89b4fa", [8]string{
		"#45475a", "#f38ba8", "#a6e3a1", "#f9e2af",
		"#89b4fa", "#cba6f7", "#94e2d5", "#bac2de",
	}),
	"gruvbox-dark": build("#282828", "#ebdbb2", "#d79921", [8]string{
		"#3c3836", "#cc241d", "#98971a", "#d79921",
		"#458588", "#b16286", "#689d6a", "#a89984",
	}),
	"tokyo-night": build("#1a1b26", "#c0caf5", "#7aa2f7", [8]string{
		"#414868", "#f7768e", "#9ece6a", "#e0af68",
		"#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6",
	}),
	"nord": build("#2e3440", "#eceff4", "#88c0d0", [8]string{
		"#3b4252", "#bf616a", "#a3be8c", "#ebcb8b",
		"#81a1c1", "#b48ead", "#88c0d0", "#d8dee9",
	}),
	"dracula": build("#282a36", "#f8f8f2", "#bd93f9", [8]string{
		"#44475a", "#ff5555", "#50fa7b", "#f1fa8c",
		"#bd93f9", "#ff79c6", "#8be9fd", "#bfbfbf",
	}),
	"solarized-dark": build("#002b36", "#839496", "#268bd2", [8]string{
		"#073642", "#dc322f", "#859900", "#b58900",
		"#268bd2", "#d33682", "#2aa198", "#eee8d5",
	}),
	"one-dark": build("#282c34", "#abb2bf", "#61afef", [8]string{
		"#3e4452", "#e06c75", "#98c379", "#e5c07b",
		"#61afef", "#c678dd", "#56b6c2", "#828997",
	}),
	"rose-pine": build("#191724", "#e0def4", "#c4a7e7", [8]string{
		"#26233a", "#eb6f92", "#31748f", "#f6c177",
		"#9ccfd8", "#c4a7e7", "#ebbcba", "#908caa",
	}),
	"everforest-dark": build("#2d353b", "#d3c6aa", "#a7c080", [8]string{
		"#475258", "#e67e80", "#a7c080", "#dbbc7f",
		"#7fbbb3", "#d699b6", "#83c092", "#859289",
	}),
	"kanagawa": build("#1f1f28", "#dcd7ba", "#7e9cd8", [8]string{
		"#2a2a37", "#c34043", "#76946a", "#c0a36e",
		"#7e9cd8", "#957fb8", "#6a9589", "#727169",
	}),
}

func build(bg, fg, accent string, c [8]string) Palette {
	p := Palette{BG: bg, FG: fg, Accent: accent}
	for i := 0; i < 8; i++ {
		p.Colors[i] = c[i]
		p.Colors[i+8] = lighten(c[i], 20)
	}
	p.Colors[15] = fg
	return p
}

func lighten(hex string, amount int) string {
	if len(hex) != 7 || hex[0] != '#' {
		return hex
	}
	var r, g, b int
	fmt.Sscanf(hex, "#%02x%02x%02x", &r, &g, &b)
	r = min(255, r+amount)
	g = min(255, g+amount)
	b = min(255, b+amount)
	return fmt.Sprintf("#%02x%02x%02x", r, g, b)
}

// Load returns the palette for the given theme name.
func Load(name string) Palette {
	if name == "auto" {
		name = "catppuccin-mocha"
	}
	if p, ok := builtins[name]; ok {
		return p
	}
	return builtins["catppuccin-mocha"]
}

// Names returns all available theme names.
func Names() []string {
	names := make([]string, 0, len(builtins))
	for k := range builtins {
		names = append(names, k)
	}
	return names
}
