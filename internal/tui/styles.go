package tui

import "github.com/charmbracelet/lipgloss"

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

func newStyles() styles {
	accent := lipgloss.Color("4") // terminal blue
	fg := lipgloss.Color("7")     // terminal white
	dim := lipgloss.Color("8")    // terminal bright black
	green := lipgloss.Color("2")  // terminal green
	yellow := lipgloss.Color("3") // terminal yellow

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
