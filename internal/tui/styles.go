package tui

import (
	"github.com/charmbracelet/lipgloss"

	"github.com/nulifyer/karchy/internal/config"
)

type styles struct {
	title         lipgloss.Style
	item          lipgloss.Style
	selected      lipgloss.Style
	match         lipgloss.Style
	hint          lipgloss.Style
	prompt        lipgloss.Style
	query         lipgloss.Style
	border        lipgloss.Style
	menuChecked   lipgloss.Style
	menuPicked    lipgloss.Style
	menuUpdatable lipgloss.Style
}

func newStyles(theme config.ThemeConfig) styles {
	a, f, d, g, y := theme.Resolve()
	accent := lipgloss.Color(a)
	fg := lipgloss.Color(f)
	dim := lipgloss.Color(d)
	green := lipgloss.Color(g)
	yellow := lipgloss.Color(y)

	return styles{
		title: lipgloss.NewStyle().
			Foreground(accent).
			Bold(true),
		item: lipgloss.NewStyle().
			Foreground(fg),
		selected: lipgloss.NewStyle().
			Foreground(accent).
			Bold(true),
		match: lipgloss.NewStyle().
			Foreground(accent).
			Bold(true),
		hint: lipgloss.NewStyle().
			Foreground(dim),
		prompt: lipgloss.NewStyle().
			Foreground(accent).
			Bold(true),
		query: lipgloss.NewStyle().
			Foreground(fg),
		border: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(accent).
			Padding(0, 1),
		menuChecked: lipgloss.NewStyle().
			Foreground(green),
		menuPicked: lipgloss.NewStyle().
			Foreground(yellow),
		menuUpdatable: lipgloss.NewStyle().
			Foreground(yellow),
	}
}
