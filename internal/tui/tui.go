package tui

import (
	"fmt"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/mattn/go-runewidth"
	"github.com/nulifyer/karchy/internal/actions/projects"
	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/filterlist"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
	"github.com/nulifyer/karchy/internal/theme"
)

// viewOverhead is the number of lines consumed by border (2), search line (1), and blank line (1).
const viewOverhead = 4

// menuLoadedMsg is sent when an async menu finishes loading.
type menuLoadedMsg struct {
	items    []MenuItem
	onSelect func(int)          // single-select handler (index into items)
	onBatch  func(map[int]bool) // multi-select handler (picked indices)
}

type model struct {
	list        filterlist.List
	menu        submenuKind
	title       string
	stack       []menuState
	styles      styles
	width       int
	height      int
	loading     bool
	quitting    bool
	multiSelect bool
	picked      map[int]bool       // item indices selected in multi-select mode
	onSelect    func(int)          // typed menu: single-select handler
	onBatch     func(map[int]bool) // typed menu: multi-select handler
	postAction  func()
	// menuItems keeps the full MenuItem data (with Action callbacks) alongside filterlist.Items.
	menuItems []MenuItem
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
		menu:      menuMain,
		title:     title,
		styles:    newStyles(pal),
		menuItems: items,
	}
	m.syncFilterItems()
	m.list.ApplyFilter()
	return m
}

// syncFilterItems converts menuItems to filterlist.Items.
func (m *model) syncFilterItems() {
	flItems := make([]filterlist.Item, len(m.menuItems))
	for i, mi := range m.menuItems {
		flItems[i] = filterlist.Item{
			Label:     mi.Label,
			Detail:    mi.Detail,
			Checked:   mi.Checked,
			Updatable: mi.Updatable,
			Icon:      mi.Icon,
		}
	}
	m.list.Items = flItems
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
		m.menuItems = msg.items
		m.onSelect = msg.onSelect
		m.onBatch = msg.onBatch
		m.syncFilterItems()
		m.list.ApplyFilter()
		return m, nil

	case tea.KeyMsg:
		if m.loading {
			if msg.String() == "esc" || msg.String() == "ctrl+c" {
				m.loading = false
				cmd := m.goBack()
				return m, cmd
			}
			return m, nil
		}

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
			if len(m.stack) > 0 {
				cmd := m.goBack()
				return m, cmd
			}
			m.quitting = true
			return m, tea.Quit

		case " ":
			if m.multiSelect && m.list.Cursor < len(m.list.Filtered) {
				idx := m.list.Filtered[m.list.Cursor].Index
				if m.picked == nil {
					m.picked = make(map[int]bool)
				}
				if m.picked[idx] {
					delete(m.picked, idx)
				} else {
					m.picked[idx] = true
				}
				if m.list.Cursor < len(m.list.Filtered)-1 {
					m.list.Cursor++
					m.list.EnsureCursorVisible(m.height, viewOverhead)
				}
				return m, nil
			}
			// Not multi-select: treat as search character
			m.list.Query += " "
			m.list.Cursor = 0
			m.list.Offset = 0
			m.list.ApplyFilter()

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
			if m.list.Cursor < len(m.list.Filtered) {
				idx := m.list.Filtered[m.list.Cursor].Index
				// Typed menu handler takes priority
				if m.onSelect != nil {
					logging.Info("enter: onSelect idx=%d", idx)
					sel := m.onSelect
					m.quitting = true
					m.postAction = func() { sel(idx) }
					return m, tea.Quit
				}
				// Fall back to per-item Action (non-typed menus)
				item := m.menuItems[idx]
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
					cmd := m.goBack()
					return m, cmd
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
			if m.multiSelect && m.list.Cursor < len(m.list.Filtered) {
				idx := m.list.Filtered[m.list.Cursor].Index
				if m.picked == nil {
					m.picked = make(map[int]bool)
				}
				if m.picked[idx] {
					delete(m.picked, idx)
				} else {
					m.picked[idx] = true
				}
				if m.list.Cursor < len(m.list.Filtered)-1 {
					m.list.Cursor++
					m.list.EnsureCursorVisible(m.height, viewOverhead)
				}
				return m, nil
			}

		default:
			if m.list.HandleKey(key, m.height, viewOverhead) {
				return m, nil
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
	if m.list.Query != "" {
		b.WriteString(m.styles.prompt.Render("> ") + m.styles.query.Render(m.list.Query))
	} else if m.loading {
		b.WriteString(m.styles.prompt.Render("> ") + m.styles.hint.Render("loading..."))
	} else {
		b.WriteString(m.styles.prompt.Render("> ") + m.styles.hint.Render(m.title))
	}
	b.WriteString("\n\n")

	if m.loading {
		vis := m.list.VisibleLines(m.height, viewOverhead)
		for i := 0; i < vis; i++ {
			if i > 0 {
				b.WriteString("\n")
			}
			b.WriteString(m.styles.hint.Render("  "))
		}
	} else if len(m.list.Filtered) == 0 {
		b.WriteString(m.styles.hint.Render("  no matches"))
	} else {
		// Determine visible window
		vis := m.list.VisibleLines(m.height, viewOverhead)
		end := m.list.Offset + vis
		if end > len(m.list.Filtered) {
			end = len(m.list.Filtered)
		}
		visible := m.list.Filtered[m.list.Offset:end]

		// Inner content width: total width minus border (2) and padding (2)
		maxContent := m.width - 4
		for i, fi := range visible {
			globalIdx := m.list.Offset + i
			item := m.list.Items[fi.Index]

			isPicked := m.picked[fi.Index]
			var prefix string
			switch {
			case isPicked && globalIdx == m.list.Cursor:
				prefix = "▸" + m.styles.menuPicked.Render("–")
			case isPicked:
				prefix = m.styles.menuPicked.Render("–") + " "
			case item.Updatable && globalIdx == m.list.Cursor:
				prefix = "▸" + m.styles.menuUpdatable.Render("⬆")
			case item.Updatable:
				prefix = m.styles.menuUpdatable.Render("⬆") + " "
			case item.Checked && globalIdx == m.list.Cursor:
				prefix = "▸" + m.styles.menuChecked.Render("✓")
			case item.Checked:
				prefix = m.styles.menuChecked.Render("✓") + " "
			case globalIdx == m.list.Cursor:
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
			matched := fi.MatchedIdx

			if avail > 0 && detail != "" {
				labelW := runewidth.StringWidth(label)
				detailW := runewidth.StringWidth(detail)
				total := labelW + 1 + detailW
				if total > avail {
					labelMax := avail / 2
					if labelMax > labelW {
						labelMax = labelW
					}
					detailMax := avail - labelMax - 1
					if detailMax < 3 {
						detail = ""
						label = truncateText(label, avail)
						matched = filterlist.ClampMatchedIdx(matched, len([]rune(label)))
					} else {
						detail = truncateText(detail, detailMax)
						label = truncateText(label, labelMax)
						matched = filterlist.ClampMatchedIdx(matched, len([]rune(label)))
					}
				}
			} else if avail > 0 {
				label = truncateText(label, avail)
				matched = filterlist.ClampMatchedIdx(matched, len([]rune(label)))
			}

			b.WriteString(prefix)
			b.WriteString(filterlist.RenderLabel(label, matched, globalIdx == m.list.Cursor, m.styles.match, m.styles.selected, m.styles.item))
			if detail != "" {
				b.WriteString(" " + m.styles.hint.Render(detail))
			}
			if i < len(visible)-1 {
				b.WriteString("\n")
			}
		}
	}

	// Size border to fill the terminal
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
		rendered = filterlist.SpliceBottomBorderLabel(rendered, " "+projects.CurrentEditor()+" [ctrl+r] ", m.styles.hint, m.styles.border)
	}
	if m.multiSelect && len(m.picked) > 0 {
		rendered = filterlist.SpliceBottomBorderLabel(rendered, fmt.Sprintf(" %d selected ", len(m.picked)), m.styles.hint, m.styles.border)
	}

	return rendered
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
		if w+rw > maxWidth-1 {
			return string(runes[:i]) + "…"
		}
		w += rw
	}
	return s
}

// openSubmenuCmd is like openSubmenu but returns a tea.Cmd for async loading.
func (m *model) openSubmenuCmd(s submenuKind) tea.Cmd {
	if s == menuMain {
		m.stack = nil
	} else {
		m.stack = append(m.stack, menuState{menu: m.menu, cursor: m.list.Cursor, query: m.list.Query})
	}

	m.menu = s
	m.list.Cursor = 0
	m.list.Offset = 0
	m.list.Query = ""
	m.multiSelect = isMultiSelect(s)
	m.picked = nil
	m.onSelect = nil
	m.onBatch = nil

	sz := getMenuSize(s)
	go terminal.ResizeAndCenter(sz.cols, sz.lines)

	// Check if this menu loads asynchronously
	if loader := getMenuAsync(s); loader != nil {
		m.loading = true
		m.title = getMenuTitle(s)
		m.menuItems = nil
		m.syncFilterItems()
		m.list.ApplyFilter()
		return loader
	}

	items, title := getMenu(s)
	m.menuItems = items
	m.title = title
	m.syncFilterItems()
	m.list.ApplyFilter()
	return nil
}

func (m *model) openSubmenu(s submenuKind) {
	m.openSubmenuCmd(s)
}

func (m *model) goBack() tea.Cmd {
	if len(m.stack) == 0 {
		return nil
	}
	prev := m.stack[len(m.stack)-1]
	m.stack = m.stack[:len(m.stack)-1]
	m.menu = prev.menu
	m.list.Cursor = 0
	m.list.Offset = 0
	m.list.Query = ""
	m.multiSelect = isMultiSelect(prev.menu)
	m.picked = nil
	m.onSelect = nil
	m.onBatch = nil

	sz := getMenuSize(prev.menu)
	go terminal.ResizeAndCenter(sz.cols, sz.lines)

	if loader := getMenuAsync(prev.menu); loader != nil {
		m.loading = true
		m.title = getMenuTitle(prev.menu)
		m.menuItems = nil
		m.syncFilterItems()
		m.list.ApplyFilter()
		return loader
	}

	items, title := getMenu(prev.menu)
	m.menuItems = items
	m.title = title
	m.syncFilterItems()
	m.list.ApplyFilter()
	m.list.EnsureCursorVisible(m.height, viewOverhead)
	return nil
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
