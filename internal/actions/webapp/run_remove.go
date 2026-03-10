package webapp

import (
	"fmt"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/filterlist"
	"github.com/nulifyer/karchy/internal/theme"
)

// viewOverhead for remove model: border(2) + search line + blank
const rmViewOverhead = 4

// RunRemove shows a multi-select pick list of installed web apps and removes selected ones.
func RunRemove() {
	apps := Scan()
	if len(apps) == 0 {
		fmt.Println("\n No web apps installed.")
		fmt.Print("\n Press Enter to close...")
		readLine()
		return
	}

	p := tea.NewProgram(newRemoveModel(apps), tea.WithAltScreen())
	result, err := p.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return
	}
	m := result.(removeModel)
	if len(m.selected) == 0 {
		return
	}

	// Confirmation
	fmt.Printf("\n Web Apps (%d)\n\n", len(m.selected))
	for _, app := range m.selected {
		fmt.Printf(" %s\n", app.Name)
	}
	fmt.Printf("\n \033[1m\033[36m:: Proceed with removal? [Y/n]\033[0m ")
	line := readLine()
	if len(line) > 0 && (line[0] == 'n' || line[0] == 'N') {
		return
	}

	deleteApps(m.selected)
	fmt.Print("\n Press Enter to close...")
	readLine()
}

// removeModel is the bubbletea model for the web app removal pick list.
type removeModel struct {
	apps     []WebApp
	list     filterlist.List
	picked   map[int]bool
	selected []WebApp
	quitting bool
	width    int
	height   int
	pal      rmPalette
	border   lipgloss.Style
}

type rmPalette struct {
	accent, fg, dim, yellow lipgloss.Color
}

func newRemoveModel(apps []WebApp) removeModel {
	cfg := config.Load()
	pal := theme.Load(cfg.Theme.Name)

	items := make([]filterlist.Item, len(apps))
	for i, a := range apps {
		items[i] = filterlist.Item{Label: a.Name}
	}

	m := removeModel{
		apps:   apps,
		picked: make(map[int]bool),
		list:   filterlist.List{Items: items},
		pal: rmPalette{
			accent: lipgloss.Color(pal.Accent),
			fg:     lipgloss.Color(pal.FG),
			dim:    lipgloss.Color(pal.Colors[8]),
			yellow: lipgloss.Color(pal.Colors[3]),
		},
		border: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color(pal.Accent)).
			Padding(0, 1),
	}
	m.list.ApplyFilter()
	return m
}

func (m removeModel) Init() tea.Cmd { return nil }

func (m removeModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case tea.KeyMsg:
		key := msg.String()

		switch key {
		case "ctrl+c":
			m.quitting = true
			return m, tea.Quit
		case "esc":
			if m.list.Query != "" {
				m.list.Reset()
				return m, nil
			}
			m.quitting = true
			return m, tea.Quit

		case " ", "tab":
			if m.list.Cursor < len(m.list.Filtered) {
				idx := m.list.Filtered[m.list.Cursor].Index
				if m.picked[idx] {
					delete(m.picked, idx)
				} else {
					m.picked[idx] = true
				}
				if m.list.Cursor < len(m.list.Filtered)-1 {
					m.list.Cursor++
					m.list.EnsureCursorVisible(m.height, rmViewOverhead)
				}
			}

		case "enter":
			if len(m.picked) > 0 {
				m.selected = make([]WebApp, 0, len(m.picked))
				for idx := range m.picked {
					m.selected = append(m.selected, m.apps[idx])
				}
			} else if m.list.Cursor < len(m.list.Filtered) {
				idx := m.list.Filtered[m.list.Cursor].Index
				m.selected = []WebApp{m.apps[idx]}
			}
			m.quitting = true
			return m, tea.Quit

		default:
			if m.list.HandleKey(key, m.height, rmViewOverhead) {
				return m, nil
			}
		}
	}
	return m, nil
}

func (m removeModel) View() string {
	if m.quitting {
		return ""
	}

	promptStyle := lipgloss.NewStyle().Foreground(m.pal.accent).Bold(true)
	queryStyle := lipgloss.NewStyle().Foreground(m.pal.fg)
	hintStyle := lipgloss.NewStyle().Foreground(m.pal.dim)
	itemStyle := lipgloss.NewStyle().Foreground(m.pal.fg)
	selStyle := lipgloss.NewStyle().Foreground(m.pal.accent).Bold(true)
	pickedStyle := lipgloss.NewStyle().Foreground(m.pal.yellow)

	var b strings.Builder

	// Search line
	if m.list.Query != "" {
		b.WriteString(promptStyle.Render("> ") + queryStyle.Render(m.list.Query))
	} else {
		b.WriteString(promptStyle.Render("> ") + hintStyle.Render("Remove Web Apps"))
	}
	b.WriteString("\n\n")

	if len(m.list.Filtered) == 0 {
		b.WriteString(hintStyle.Render("  no matches"))
	} else {
		vis := m.list.VisibleLines(m.height, rmViewOverhead)
		end := m.list.Offset + vis
		if end > len(m.list.Filtered) {
			end = len(m.list.Filtered)
		}

		for i := m.list.Offset; i < end; i++ {
			fi := m.list.Filtered[i]
			isPicked := m.picked[fi.Index]
			isCursor := i == m.list.Cursor

			var prefix string
			switch {
			case isPicked && isCursor:
				prefix = "▸" + pickedStyle.Render("–")
			case isPicked:
				prefix = pickedStyle.Render("–") + " "
			case isCursor:
				prefix = "▸ "
			default:
				prefix = "  "
			}

			label := m.apps[fi.Index].Name
			b.WriteString(prefix)
			b.WriteString(filterlist.RenderLabel(label, fi.MatchedIdx, isCursor, selStyle, selStyle, itemStyle))

			if i < end-1 {
				b.WriteString("\n")
			}
		}
	}

	// Border
	border := m.border
	if m.width > 0 {
		border = border.Width(m.width - 2)
	}
	if m.height > 0 {
		border = border.Height(m.height - 2)
	}
	rendered := border.Render(b.String())

	// Splice selected count into bottom border
	if len(m.picked) > 0 {
		rendered = filterlist.SpliceBottomBorderLabel(rendered, fmt.Sprintf(" %d selected ", len(m.picked)), hintStyle, m.border)
	}

	return rendered
}
