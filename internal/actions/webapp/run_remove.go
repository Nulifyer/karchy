package webapp

import (
	"fmt"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/theme"
	"github.com/sahilm/fuzzy"
)

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
	filtered []rmFiltered
	cursor   int
	offset   int
	query    string
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

type rmFiltered struct {
	index   int
	matched []int
}

func newRemoveModel(apps []WebApp) removeModel {
	cfg := config.Load()
	pal := theme.Load(cfg.Theme.Name)

	m := removeModel{
		apps:   apps,
		picked: make(map[int]bool),
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
	m.applyFilter()
	return m
}

func (m *removeModel) applyFilter() {
	if m.query == "" {
		m.filtered = make([]rmFiltered, len(m.apps))
		for i := range m.apps {
			m.filtered[i] = rmFiltered{index: i}
		}
		return
	}
	names := make([]string, len(m.apps))
	for i, a := range m.apps {
		names[i] = a.Name
	}
	matches := fuzzy.Find(m.query, names)
	m.filtered = make([]rmFiltered, len(matches))
	for i, match := range matches {
		m.filtered[i] = rmFiltered{index: match.Index, matched: match.MatchedIndexes}
	}
}

func (m removeModel) visibleLines() int {
	if m.height <= 0 {
		return len(m.filtered)
	}
	v := m.height - 4 // border(2) + search line + blank
	if v < 1 {
		v = 1
	}
	return v
}

func (m *removeModel) ensureCursorVisible() {
	vis := m.visibleLines()
	if m.cursor < m.offset {
		m.offset = m.cursor
	} else if m.cursor >= m.offset+vis {
		m.offset = m.cursor - vis + 1
	}
}

func (m removeModel) Init() tea.Cmd { return nil }

func (m removeModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			m.quitting = true
			return m, tea.Quit
		case "esc":
			if m.query != "" {
				m.query = ""
				m.cursor = 0
				m.offset = 0
				m.applyFilter()
				return m, nil
			}
			m.quitting = true
			return m, tea.Quit

		case "up", "ctrl+k":
			if m.cursor > 0 {
				m.cursor--
			} else if len(m.filtered) > 0 {
				m.cursor = len(m.filtered) - 1
			}
			m.ensureCursorVisible()

		case "down", "ctrl+j":
			if m.cursor < len(m.filtered)-1 {
				m.cursor++
			} else {
				m.cursor = 0
			}
			m.ensureCursorVisible()

		case " ", "tab":
			if m.cursor < len(m.filtered) {
				idx := m.filtered[m.cursor].index
				if m.picked[idx] {
					delete(m.picked, idx)
				} else {
					m.picked[idx] = true
				}
				if m.cursor < len(m.filtered)-1 {
					m.cursor++
					m.ensureCursorVisible()
				}
			}

		case "enter":
			if len(m.picked) > 0 {
				m.selected = make([]WebApp, 0, len(m.picked))
				for idx := range m.picked {
					m.selected = append(m.selected, m.apps[idx])
				}
			} else if m.cursor < len(m.filtered) {
				idx := m.filtered[m.cursor].index
				m.selected = []WebApp{m.apps[idx]}
			}
			m.quitting = true
			return m, tea.Quit

		case "backspace":
			if len(m.query) > 0 {
				m.query = m.query[:len(m.query)-1]
				m.cursor = 0
				m.offset = 0
				m.applyFilter()
			}

		default:
			if len(msg.String()) == 1 && msg.String()[0] >= ' ' {
				m.query += msg.String()
				m.cursor = 0
				m.offset = 0
				m.applyFilter()
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
	if m.query != "" {
		b.WriteString(promptStyle.Render("> ") + queryStyle.Render(m.query))
	} else {
		b.WriteString(promptStyle.Render("> ") + hintStyle.Render("Remove Web Apps"))
	}
	b.WriteString("\n\n")

	if len(m.filtered) == 0 {
		b.WriteString(hintStyle.Render("  no matches"))
	} else {
		vis := m.visibleLines()
		end := m.offset + vis
		if end > len(m.filtered) {
			end = len(m.filtered)
		}

		for i := m.offset; i < end; i++ {
			fi := m.filtered[i]
			isPicked := m.picked[fi.index]
			isCursor := i == m.cursor

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

			label := m.apps[fi.index].Name
			b.WriteString(prefix)
			b.WriteString(renderRmLabel(label, fi.matched, isCursor, selStyle, itemStyle))

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
		rendered = spliceBottomLabel(rendered, fmt.Sprintf(" %d selected ", len(m.picked)), hintStyle, m.border)
	}

	return rendered
}

func renderRmLabel(label string, matched []int, selected bool, selStyle, itemStyle lipgloss.Style) string {
	if len(matched) == 0 {
		if selected {
			return selStyle.Render(label)
		}
		return itemStyle.Render(label)
	}

	matchSet := make(map[int]bool, len(matched))
	for _, idx := range matched {
		matchSet[idx] = true
	}

	runes := []rune(label)
	var sb strings.Builder
	i := 0
	for i < len(runes) {
		isMatch := matchSet[i]
		j := i + 1
		for j < len(runes) && matchSet[j] == isMatch {
			j++
		}
		run := string(runes[i:j])
		if isMatch || selected {
			sb.WriteString(selStyle.Render(run))
		} else {
			sb.WriteString(itemStyle.Render(run))
		}
		i = j
	}
	return sb.String()
}

func spliceBottomLabel(rendered, label string, hintStyle, borderStyle lipgloss.Style) string {
	lines := strings.Split(rendered, "\n")
	if len(lines) == 0 {
		return rendered
	}

	style := borderStyle.GetBorderStyle()
	filler := style.Bottom
	if filler == "" {
		filler = "─"
	}
	accent := borderStyle.GetBorderBottomForeground()
	bc := lipgloss.NewStyle().Foreground(accent)

	plain := rmStripAnsi(string([]rune(lines[len(lines)-1])))
	plainRunes := []rune(plain)
	labelRunes := []rune(label)
	cornerLeft := style.BottomLeft
	cornerRight := style.BottomRight
	innerWidth := len(plainRunes) - len([]rune(cornerLeft)) - len([]rune(cornerRight))
	labelWidth := len(labelRunes)
	fillerCount := innerWidth - labelWidth
	if fillerCount < 0 {
		return rendered
	}

	var sb strings.Builder
	sb.WriteString(bc.Render(cornerLeft))
	for i := 0; i < fillerCount; i++ {
		sb.WriteString(bc.Render(filler))
	}
	sb.WriteString(hintStyle.Render(label))
	sb.WriteString(bc.Render(cornerRight))
	lines[len(lines)-1] = sb.String()
	return strings.Join(lines, "\n")
}

func rmStripAnsi(s string) string {
	var out strings.Builder
	inEsc := false
	for _, r := range s {
		if r == '\x1b' {
			inEsc = true
			continue
		}
		if inEsc {
			if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') {
				inEsc = false
			}
			continue
		}
		out.WriteRune(r)
	}
	return out.String()
}
