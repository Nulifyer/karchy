package tui

import (
	"github.com/charmbracelet/lipgloss"
	"github.com/nulifyer/karchy/internal/theme"
)

type styles struct {
	title       lipgloss.Style
	item        lipgloss.Style
	selected    lipgloss.Style
	match       lipgloss.Style
	hint        lipgloss.Style
	prompt      lipgloss.Style
	query       lipgloss.Style
	border      lipgloss.Style
	menuChecked lipgloss.Style
	menuPicked  lipgloss.Style
}

func newStyles(pal theme.Palette) styles {
	accent := lipgloss.Color(pal.Accent)
	fg := lipgloss.Color(pal.FG)
	dim := lipgloss.Color(pal.Colors[8])
	green := lipgloss.Color(pal.Colors[2])
	yellow := lipgloss.Color(pal.Colors[3])

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
	}
}
