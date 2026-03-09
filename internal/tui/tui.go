package tui

import (
	"fmt"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/mattn/go-runewidth"
	"github.com/nulifyer/karchy/internal/actions/projects"
	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
	"github.com/nulifyer/karchy/internal/theme"
	"github.com/sahilm/fuzzy"
)

// menuLoadedMsg is sent when an async menu finishes loading.
type menuLoadedMsg struct {
	items    []MenuItem
	onSelect func(int)           // single-select handler (index into items)
	onBatch  func(map[int]bool)  // multi-select handler (picked indices)
}

type model struct {
	items       []MenuItem
	filtered    []filteredItem
	menu        submenuKind
	title       string
	cursor      int
	offset      int // scroll offset for viewport
	query       string
	stack       []menuState
	styles      styles
	width       int
	height      int
	loading     bool
	quitting    bool
	multiSelect bool
	picked      map[int]bool        // item indices selected in multi-select mode
	onSelect    func(int)           // typed menu: single-select handler
	onBatch     func(map[int]bool)  // typed menu: multi-select handler
	postAction  func()
}

type filteredItem struct {
	index      int
	matchedIdx []int
}

type menuState struct {
	menu   submenuKind
	cursor int
	query  string
}

func initialModel() model {
	cfg := config.Load()
	pal := theme.Load(cfg.Theme.Name)
	items, title := getMenu(menuMain)

	// Tell the terminal package our initial size so ResizeAndCenter can derive cell dimensions
	sz := getMenuSize(menuMain)
	terminal.SetLaunchSize(sz.cols, sz.lines)

	m := model{
		items:  items,
		menu:   menuMain,
		title:  title,
		styles: newStyles(pal),
	}
	m.applyFilter()
	return m
}

func (m *model) applyFilter() {
	if m.query == "" {
		m.filtered = make([]filteredItem, len(m.items))
		for i := range m.items {
			m.filtered[i] = filteredItem{index: i}
		}
		return
	}

	// Search against label + detail so both name and ID are searchable.
	// Matched indices beyond the label length are clamped during rendering.
	searchable := make([]string, len(m.items))
	for i, item := range m.items {
		if item.Detail != "" {
			searchable[i] = item.Label + " " + item.Detail
		} else {
			searchable[i] = item.Label
		}
	}

	matches := fuzzy.Find(m.query, searchable)
	m.filtered = make([]filteredItem, len(matches))
	for i, match := range matches {
		m.filtered[i] = filteredItem{
			index:      match.Index,
			matchedIdx: match.MatchedIndexes,
		}
	}
}

// visibleLines returns how many menu items fit in the viewport.
// Accounts for border (2), search line (1), and blank line (1).
func (m model) visibleLines() int {
	if m.height <= 0 {
		return len(m.filtered)
	}
	v := m.height - 2 - 2 // border + search + blank
	if v < 1 {
		v = 1
	}
	return v
}

// ensureCursorVisible adjusts scroll offset so the cursor is in view.
func (m *model) ensureCursorVisible() {
	vis := m.visibleLines()
	if m.cursor < m.offset {
		m.offset = m.cursor
	} else if m.cursor >= m.offset+vis {
		m.offset = m.cursor - vis + 1
	}
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		logging.Info("WindowSizeMsg: %dx%d (was %dx%d)", msg.Width, msg.Height, m.width, m.height)
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case menuLoadedMsg:
		logging.Info("menuLoadedMsg: %d items", len(msg.items))
		m.loading = false
		m.items = msg.items
		m.onSelect = msg.onSelect
		m.onBatch = msg.onBatch
		m.applyFilter()
		return m, nil

	case tea.KeyMsg:
		if m.loading {
			if msg.String() == "esc" || msg.String() == "ctrl+c" {
				m.loading = false
				m.goBack()
				return m, nil
			}
			return m, nil
		}
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
			if len(m.stack) > 0 {
				m.goBack()
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

		case " ":
			if m.multiSelect && m.cursor < len(m.filtered) {
				idx := m.filtered[m.cursor].index
				if m.picked == nil {
					m.picked = make(map[int]bool)
				}
				if m.picked[idx] {
					delete(m.picked, idx)
				} else {
					m.picked[idx] = true
				}
				// Advance cursor after toggling
				if m.cursor < len(m.filtered)-1 {
					m.cursor++
					m.ensureCursorVisible()
				}
				return m, nil
			}
			// Not multi-select: fall through to default (search character)
			m.query += " "
			m.cursor = 0
			m.offset = 0
			m.applyFilter()

		case "enter":
			// Multi-select: delegate to batch handler
			if m.multiSelect && len(m.picked) > 0 && m.onBatch != nil {
				logging.Info("enter: batch %d picked items", len(m.picked))
				batch := m.onBatch
				picked := m.picked
				m.quitting = true
				m.postAction = func() { batch(picked) }
				return m, tea.Quit
			}
			// Single item
			if m.cursor < len(m.filtered) {
				idx := m.filtered[m.cursor].index
				// Typed menu handler takes priority
				if m.onSelect != nil {
					logging.Info("enter: onSelect idx=%d", idx)
					sel := m.onSelect
					m.quitting = true
					m.postAction = func() { sel(idx) }
					return m, tea.Quit
				}
				// Fall back to per-item Action (non-typed menus)
				item := m.items[idx]
				logging.Info("enter pressed on %q (action=%v)", item.Label, item.Action != nil)
				if item.Action == nil {
					break
				}
				result := item.Action()
				logging.Info("action result kind=%d", result.kind)
				switch result.kind {
				case resultSubmenu:
					cmd := m.openSubmenuCmd(result.submenu)
					return m, cmd
				case resultBack:
					m.goBack()
					return m, nil
				case resultQuit:
					m.quitting = true
					return m, tea.Quit
				case resultAction:
					logging.Info("resultAction: quitting TUI, postAction set")
					m.quitting = true
					m.postAction = result.action
					return m, tea.Quit
				}
			}

		case "ctrl+r":
			if m.menu == menuProjects {
				cmd := m.openSubmenuCmd(menuEditor)
				return m, cmd
			}

		case "tab":
			if m.multiSelect && m.cursor < len(m.filtered) {
				idx := m.filtered[m.cursor].index
				if m.picked == nil {
					m.picked = make(map[int]bool)
				}
				if m.picked[idx] {
					delete(m.picked, idx)
				} else {
					m.picked[idx] = true
				}
				if m.cursor < len(m.filtered)-1 {
					m.cursor++
					m.ensureCursorVisible()
				}
				return m, nil
			}

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

func (m model) View() string {
	if m.quitting {
		return ""
	}

	var b strings.Builder

	// Search line (always visible)
	if m.query != "" {
		b.WriteString(m.styles.prompt.Render("> ") + m.styles.query.Render(m.query))
	} else if m.loading {
		b.WriteString(m.styles.prompt.Render("> ") + m.styles.hint.Render("loading..."))
	} else {
		b.WriteString(m.styles.prompt.Render("> ") + m.styles.hint.Render(m.title))
	}
	b.WriteString("\n\n")

	if m.loading {
		vis := m.visibleLines()
		for i := 0; i < vis; i++ {
			if i > 0 {
				b.WriteString("\n")
			}
			b.WriteString(m.styles.hint.Render("  "))
		}
	} else if len(m.filtered) == 0 {
		b.WriteString(m.styles.hint.Render("  no matches"))
	} else {
		// Determine visible window
		vis := m.visibleLines()
		end := m.offset + vis
		if end > len(m.filtered) {
			end = len(m.filtered)
		}
		visible := m.filtered[m.offset:end]

		// Menu items
		// Inner content width: total width minus border (2) and padding (2)
		maxContent := m.width - 4
		for i, fi := range visible {
			globalIdx := m.offset + i
			item := m.items[fi.index]

			isPicked := m.picked[fi.index]
			var prefix string
			switch {
			case isPicked && globalIdx == m.cursor:
				prefix = "▸" + m.styles.menuPicked.Render("–")
			case isPicked:
				prefix = m.styles.menuPicked.Render("–") + " "
			case item.Checked && globalIdx == m.cursor:
				prefix = "▸" + m.styles.menuChecked.Render("✓")
			case item.Checked:
				prefix = m.styles.menuChecked.Render("✓") + " "
			case globalIdx == m.cursor:
				prefix = "▸ "
			default:
				prefix = "  "
			}

			if item.Icon != "" {
				prefix += item.Icon + " "
			}
			prefixW := runewidth.StringWidth(prefix)
			avail := maxContent - prefixW
			if avail < 0 {
				avail = 0
			}

			label := item.Label
			detail := item.Detail
			matched := fi.matchedIdx

			if avail > 0 && detail != "" {
				// Reserve space: label + " " + detail
				labelW := runewidth.StringWidth(label)
				detailW := runewidth.StringWidth(detail)
				total := labelW + 1 + detailW
				if total > avail {
					// Truncate detail first, keep at least half for label
					labelMax := avail / 2
					if labelMax > labelW {
						labelMax = labelW
					}
					detailMax := avail - labelMax - 1 // 1 for space
					if detailMax < 3 {
						// Not enough room for detail, drop it
						detail = ""
						label = truncateText(label, avail)
						matched = clampMatchedIdx(matched, len([]rune(label)))
					} else {
						detail = truncateText(detail, detailMax)
						label = truncateText(label, labelMax)
						matched = clampMatchedIdx(matched, len([]rune(label)))
					}
				}
			} else if avail > 0 {
				label = truncateText(label, avail)
				matched = clampMatchedIdx(matched, len([]rune(label)))
			}

			b.WriteString(prefix)
			b.WriteString(m.renderLabel(label, matched, globalIdx == m.cursor))
			if detail != "" {
				b.WriteString(" " + m.styles.hint.Render(detail))
			}
			if i < len(visible)-1 {
				b.WriteString("\n")
			}
		}
	}

	// Size border to fill the terminal (border=2, padding=2 horizontal)
	border := m.styles.border
	if m.width > 0 {
		border = border.Width(m.width - 2)
	}
	if m.height > 0 {
		border = border.Height(m.height - 2)
	}
	rendered := border.Render(b.String())

	// Splice labels into bottom border
	if m.menu == menuProjects {
		rendered = m.spliceBottomBorderLabel(rendered, " "+projects.CurrentEditor()+" [ctrl+r] ")
	}
	if m.multiSelect && len(m.picked) > 0 {
		rendered = m.spliceBottomBorderLabel(rendered, fmt.Sprintf(" %d selected ", len(m.picked)))
	}

	return rendered
}

func (m model) renderLabel(label string, matched []int, selected bool) string {
	if len(matched) == 0 {
		if selected {
			return m.styles.selected.Render(label)
		}
		return m.styles.item.Render(label)
	}

	matchSet := make(map[int]bool, len(matched))
	for _, idx := range matched {
		matchSet[idx] = true
	}

	// Style contiguous runs of matched/unmatched characters together
	// to avoid per-character ANSI sequences that confuse lipgloss width calculation.
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
		if isMatch {
			sb.WriteString(m.styles.match.Render(run))
		} else if selected {
			sb.WriteString(m.styles.selected.Render(run))
		} else {
			sb.WriteString(m.styles.item.Render(run))
		}
		i = j
	}
	return sb.String()
}

func (m model) spliceBottomBorderLabel(rendered string, label string) string {
	lines := strings.Split(rendered, "\n")
	if len(lines) == 0 {
		return rendered
	}

	last := []rune(lines[len(lines)-1])
	labelRunes := []rune(m.styles.hint.Render(label))
	labelPlain := []rune(label)

	// Find how many visible rune positions to replace (count of plain label chars)
	// Place it right-aligned: end before the last border character
	// The bottom border looks like: ╰──────────╯
	// We want: ╰────── editor [tab] ╯
	if len(last) < len(labelPlain)+2 {
		return rendered
	}

	// Find the position of the last border char (╯)
	// Replace border chars before it with styled label
	// Build new last line: keep start, splice styled label, keep end char
	endChar := string(last[len(last)-1])

	// Count ANSI-free rune width of the bottom border
	plain := stripAnsi(string(last))
	plainRunes := []rune(plain)
	if len(plainRunes) < len(labelPlain)+2 {
		return rendered
	}

	// Rebuild: original line up to splice point + styled label + end border char
	// We need to find the byte position to cut. Since the border line has ANSI codes,
	// reconstruct it: border start + filler + label + end
	borderStyle := m.styles.border.GetBorderStyle()
	filler := borderStyle.Bottom
	if filler == "" {
		filler = "─"
	}

	// Build the bottom line manually
	accent := m.styles.border.GetBorderBottomForeground()
	borderColor := lipgloss.NewStyle().Foreground(accent)

	cornerLeft := borderStyle.BottomLeft
	cornerRight := borderStyle.BottomRight

	innerWidth := len(plainRunes) - len([]rune(cornerLeft)) - len([]rune(cornerRight))
	labelWidth := len(labelPlain)
	fillerCount := innerWidth - labelWidth
	if fillerCount < 0 {
		return rendered
	}

	var sb strings.Builder
	sb.WriteString(borderColor.Render(cornerLeft))
	for i := 0; i < fillerCount; i++ {
		sb.WriteString(borderColor.Render(filler))
	}
	sb.WriteString(string(labelRunes))
	sb.WriteString(borderColor.Render(cornerRight))

	_ = endChar
	lines[len(lines)-1] = sb.String()
	return strings.Join(lines, "\n")
}

// clampMatchedIdx removes fuzzy match indices that are beyond the truncated label length.
func clampMatchedIdx(idx []int, maxLen int) []int {
	if len(idx) == 0 {
		return idx
	}
	out := make([]int, 0, len(idx))
	for _, i := range idx {
		if i < maxLen {
			out = append(out, i)
		}
	}
	return out
}

// truncateText truncates a string to fit within maxWidth display cells,
// appending "…" if truncated. Accounts for wide Unicode characters.
func truncateText(s string, maxWidth int) string {
	if maxWidth <= 0 {
		return ""
	}
	if runewidth.StringWidth(s) <= maxWidth {
		return s
	}
	if maxWidth <= 1 {
		return "…"
	}
	runes := []rune(s)
	w := 0
	for i, r := range runes {
		rw := runewidth.RuneWidth(r)
		if w+rw > maxWidth-1 { // reserve 1 cell for "…"
			return string(runes[:i]) + "…"
		}
		w += rw
	}
	return s
}

func stripAnsi(s string) string {
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

// openSubmenuCmd is like openSubmenu but returns a tea.Cmd for async loading.
func (m *model) openSubmenuCmd(s submenuKind) tea.Cmd {
	if s == menuMain {
		m.stack = nil
	} else {
		m.stack = append(m.stack, menuState{menu: m.menu, cursor: m.cursor, query: m.query})
	}

	m.menu = s
	m.cursor = 0
	m.offset = 0
	m.query = ""
	m.multiSelect = isMultiSelect(s)
	m.picked = nil
	m.onSelect = nil
	m.onBatch = nil

	sz := getMenuSize(s)
	go terminal.ResizeAndCenter(sz.cols, sz.lines)
	// Don't set m.width/m.height — let WindowSizeMsg update them after the actual resize

	// Check if this menu loads asynchronously
	if loader := getMenuAsync(s); loader != nil {
		m.loading = true
		m.title = getMenuTitle(s)
		m.items = nil
		m.applyFilter()
		return loader
	}

	items, title := getMenu(s)
	m.items = items
	m.title = title
	m.applyFilter()
	return nil
}

func (m *model) openSubmenu(s submenuKind) {
	m.openSubmenuCmd(s)
}

func (m *model) goBack() {
	if len(m.stack) == 0 {
		return
	}
	prev := m.stack[len(m.stack)-1]
	m.stack = m.stack[:len(m.stack)-1]
	items, title := getMenu(prev.menu)
	m.items = items
	m.menu = prev.menu
	m.title = title
	m.cursor = prev.cursor
	m.offset = 0
	m.query = ""
	m.multiSelect = isMultiSelect(prev.menu)
	m.picked = nil
	m.onSelect = nil
	m.onBatch = nil
	m.applyFilter()
	m.ensureCursorVisible()

	sz := getMenuSize(prev.menu)
	go terminal.ResizeAndCenter(sz.cols, sz.lines)
}

func Run() {
	p := tea.NewProgram(initialModel(), tea.WithAltScreen())
	m, err := p.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	if fm, ok := m.(model); ok && fm.postAction != nil {
		logging.Info("executing postAction")
		fm.postAction()
	}
}
