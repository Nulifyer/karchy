package webapp

import (
	"fmt"
	"os"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/theme"
	"github.com/sahilm/fuzzy"
)

// RunNew launches a bubbletea form for creating a new web app.
func RunNew() {
	p := tea.NewProgram(newNewModel(), tea.WithAltScreen())
	result, err := p.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		return
	}
	m := result.(newModel)
	if m.cancelled {
		return
	}

	// Post-TUI: download icon and create shortcut
	createWebApp(m.appName, m.appURL, m.iconURL, m.isolated)
}

func createWebApp(appName, appURL, iconURL string, isolated bool) {
	id := urlHash(appURL)
	var iconPath string
	if iconURL != "" {
		fmt.Print("\n Downloading icon...")
		var err error
		iconPath, err = DownloadIcon(id, iconURL)
		if err != nil {
			fmt.Printf(" \033[31mfailed: %v\033[0m\n", err)
		} else {
			fmt.Printf(" \033[32mdone\033[0m\n")
		}
	}

	fmt.Print(" Creating shortcut...")
	if err := createShortcut(appName, appURL, iconPath, isolated); err != nil {
		fmt.Printf(" \033[31mfailed: %v\033[0m\n", err)
		fmt.Print("\n Press Enter to close...")
		readLine()
		return
	}
	fmt.Printf(" \033[32mdone\033[0m\n")

	fmt.Printf("\n \033[1m\033[32m:: Web app '%s' created!\033[0m\n", appName)
	fmt.Print("\n Press Enter to close...")
	readLine()
}

// Steps in the new web app form.
type newStep int

const (
	stepName       newStep = iota
	stepURL
	stepIconSource
	stepIconSearch // dashboard icon search
	stepIconURL    // manual icon URL input
	stepIsolated   // isolated profile prompt
)

// Icon source choices.
const (
	srcDashboard = iota
	srcFavicon
	srcManual
)

var iconSourceLabels = []string{"Dashboard Icons", "Favicon (auto)", "Enter URL manually"}

// iconsLoadedMsg is sent when dashboard icons finish loading.
type iconsLoadedMsg struct {
	icons  []DashboardIcon
	commit string
	err    error
}

type newModel struct {
	step      newStep
	cancelled bool
	quitting  bool

	// Text inputs
	nameInput    textinput.Model
	urlInput     textinput.Model
	iconURLInput textinput.Model
	searchInput  textinput.Model

	// Icon source selection
	srcCursor int

	// Dashboard icon data
	allIcons     []DashboardIcon
	commit       string
	iconFiltered []iconMatch
	iconCursor   int
	iconOffset   int
	loadingIcons bool
	loadErr      error

	// Isolated profile selection
	isolatedCursor int

	// Collected results
	appName  string
	appURL   string
	iconURL  string
	isolated bool

	// Display
	width  int
	height int
	pal    rmPalette
	border lipgloss.Style
}

type iconMatch struct {
	index   int
	matched []int
}

func newNewModel() newModel {
	cfg := config.Load()
	pal := theme.Load(cfg.Theme.Name)

	accent := lipgloss.Color(pal.Accent)

	nameIn := textinput.New()
	nameIn.Placeholder = "My App"
	nameIn.Focus()
	nameIn.CharLimit = 64
	nameIn.Cursor.Style = lipgloss.NewStyle().Foreground(accent)

	urlIn := textinput.New()
	urlIn.Placeholder = "https://example.com"
	urlIn.CharLimit = 512
	urlIn.Cursor.Style = lipgloss.NewStyle().Foreground(accent)

	iconURLIn := textinput.New()
	iconURLIn.Placeholder = "https://example.com/icon.png"
	iconURLIn.CharLimit = 512
	iconURLIn.Cursor.Style = lipgloss.NewStyle().Foreground(accent)

	searchIn := textinput.New()
	searchIn.Placeholder = "search..."
	searchIn.CharLimit = 64
	searchIn.Cursor.Style = lipgloss.NewStyle().Foreground(accent)

	return newModel{
		step:         stepName,
		nameInput:    nameIn,
		urlInput:     urlIn,
		iconURLInput: iconURLIn,
		searchInput:  searchIn,
		pal: rmPalette{
			accent: accent,
			fg:     lipgloss.Color(pal.FG),
			dim:    lipgloss.Color(pal.Colors[8]),
			yellow: lipgloss.Color(pal.Colors[3]),
		},
		border: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(accent).
			Padding(0, 1),
	}
}

func (m newModel) Init() tea.Cmd {
	return textinput.Blink
}

func (m newModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case iconsLoadedMsg:
		m.loadingIcons = false
		if msg.err != nil {
			m.loadErr = msg.err
		} else {
			m.allIcons = msg.icons
			m.commit = msg.commit
			m.filterIcons()
		}
		return m, nil

	case tea.KeyMsg:
		// Global quit
		if msg.String() == "ctrl+c" {
			m.cancelled = true
			m.quitting = true
			return m, tea.Quit
		}

		switch m.step {
		case stepName:
			return m.updateName(msg)
		case stepURL:
			return m.updateURL(msg)
		case stepIconSource:
			return m.updateIconSource(msg)
		case stepIconSearch:
			return m.updateIconSearch(msg)
		case stepIconURL:
			return m.updateIconURL(msg)
		case stepIsolated:
			return m.updateIsolated(msg)
		}
	}

	return m, nil
}

func (m newModel) updateName(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.cancelled = true
		m.quitting = true
		return m, tea.Quit
	case "enter":
		val := sanitizeName(m.nameInput.Value())
		if val == "" {
			return m, nil
		}
		m.appName = val
		m.step = stepURL
		m.nameInput.Blur()
		m.urlInput.Focus()
		return m, textinput.Blink
	}

	var cmd tea.Cmd
	m.nameInput, cmd = m.nameInput.Update(msg)
	return m, cmd
}

func (m newModel) updateURL(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.step = stepName
		m.urlInput.Blur()
		m.nameInput.Focus()
		return m, textinput.Blink
	case "enter":
		val := strings.TrimSpace(m.urlInput.Value())
		if val == "" {
			return m, nil
		}
		if !strings.Contains(val, "://") {
			val = "https://" + val
		}
		m.appURL = val
		m.step = stepIconSource
		m.urlInput.Blur()
		return m, nil
	}

	var cmd tea.Cmd
	m.urlInput, cmd = m.urlInput.Update(msg)
	return m, cmd
}

func (m newModel) updateIconSource(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.step = stepURL
		m.urlInput.Focus()
		return m, textinput.Blink
	case "up", "ctrl+k":
		if m.srcCursor > 0 {
			m.srcCursor--
		}
	case "down", "ctrl+j":
		if m.srcCursor < len(iconSourceLabels)-1 {
			m.srcCursor++
		}
	case "enter":
		switch m.srcCursor {
		case srcDashboard:
			m.step = stepIconSearch
			m.loadingIcons = true
			m.loadErr = nil
			m.searchInput.Focus()
			return m, tea.Batch(textinput.Blink, loadDashboardIconsCmd())
		case srcFavicon:
			m.iconURL = FaviconURL(m.appURL)
			m.step = stepIsolated
			return m, nil
		case srcManual:
			m.step = stepIconURL
			m.iconURLInput.Focus()
			return m, textinput.Blink
		}
	}
	return m, nil
}

func (m newModel) updateIconSearch(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if m.loadingIcons {
		if msg.String() == "esc" {
			m.step = stepIconSource
			m.searchInput.Blur()
			m.loadingIcons = false
			return m, nil
		}
		return m, nil
	}

	switch msg.String() {
	case "esc":
		m.step = stepIconSource
		m.searchInput.Blur()
		return m, nil
	case "up", "ctrl+k":
		if m.iconCursor > 0 {
			m.iconCursor--
			m.ensureIconVisible()
		}
		return m, nil
	case "down", "ctrl+j":
		if m.iconCursor < len(m.iconFiltered)-1 {
			m.iconCursor++
			m.ensureIconVisible()
		}
		return m, nil
	case "enter":
		if m.loadErr != nil {
			// Fallback to favicon on error
			m.iconURL = FaviconURL(m.appURL)
			m.step = stepIsolated
			m.searchInput.Blur()
			return m, nil
		}
		if m.iconCursor < len(m.iconFiltered) {
			icon := m.allIcons[m.iconFiltered[m.iconCursor].index]
			m.iconURL = DashboardIconURL(m.commit, icon.Name)
			m.step = stepIsolated
			m.searchInput.Blur()
			return m, nil
		}
		return m, nil
	}

	// Update search input
	prevQuery := m.searchInput.Value()
	var cmd tea.Cmd
	m.searchInput, cmd = m.searchInput.Update(msg)
	if m.searchInput.Value() != prevQuery {
		m.iconCursor = 0
		m.iconOffset = 0
		m.filterIcons()
	}
	return m, cmd
}

func (m newModel) updateIconURL(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.step = stepIconSource
		m.iconURLInput.Blur()
		return m, nil
	case "enter":
		val := strings.TrimSpace(m.iconURLInput.Value())
		if val != "" {
			m.iconURL = val
		}
		m.step = stepIsolated
		m.iconURLInput.Blur()
		return m, nil
	}

	var cmd tea.Cmd
	m.iconURLInput, cmd = m.iconURLInput.Update(msg)
	return m, cmd
}

var isolatedLabels = []string{"No (use default profile with extensions)", "Yes (isolated profile, per-app window sizing)"}

func (m newModel) updateIsolated(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.step = stepIconSource
		return m, nil
	case "up", "ctrl+k":
		if m.isolatedCursor > 0 {
			m.isolatedCursor--
		}
	case "down", "ctrl+j":
		if m.isolatedCursor < len(isolatedLabels)-1 {
			m.isolatedCursor++
		}
	case "enter":
		m.isolated = m.isolatedCursor == 1
		m.quitting = true
		return m, tea.Quit
	}
	return m, nil
}

func (m *newModel) filterIcons() {
	query := strings.TrimSpace(m.searchInput.Value())
	if query == "" {
		m.iconFiltered = make([]iconMatch, len(m.allIcons))
		for i := range m.allIcons {
			m.iconFiltered[i] = iconMatch{index: i}
		}
		return
	}
	names := make([]string, len(m.allIcons))
	for i, ic := range m.allIcons {
		names[i] = ic.Name + " " + ic.DisplayName
	}
	matches := fuzzy.Find(query, names)
	m.iconFiltered = make([]iconMatch, len(matches))
	for i, match := range matches {
		m.iconFiltered[i] = iconMatch{index: match.Index, matched: match.MatchedIndexes}
	}
}

func (m *newModel) ensureIconVisible() {
	vis := m.iconVisibleLines()
	if m.iconCursor < m.iconOffset {
		m.iconOffset = m.iconCursor
	} else if m.iconCursor >= m.iconOffset+vis {
		m.iconOffset = m.iconCursor - vis + 1
	}
}

func (m newModel) iconVisibleLines() int {
	if m.height <= 0 {
		return 20
	}
	v := m.height - 4 // border + search + blank
	if v < 1 {
		v = 1
	}
	return v
}

func loadDashboardIconsCmd() tea.Cmd {
	return func() tea.Msg {
		icons, commit, err := LoadDashboardIcons()
		return iconsLoadedMsg{icons: icons, commit: commit, err: err}
	}
}

// --- View ---

func (m newModel) View() string {
	if m.quitting {
		return ""
	}

	promptStyle := lipgloss.NewStyle().Foreground(m.pal.accent).Bold(true)
	hintStyle := lipgloss.NewStyle().Foreground(m.pal.dim)
	itemStyle := lipgloss.NewStyle().Foreground(m.pal.fg)
	selStyle := lipgloss.NewStyle().Foreground(m.pal.accent).Bold(true)
	labelStyle := lipgloss.NewStyle().Foreground(m.pal.fg).Bold(true)

	var b strings.Builder

	if m.step == stepIconSearch {
		// Full-screen icon search
		return m.viewIconSearch(promptStyle, hintStyle, itemStyle, selStyle)
	}

	// Form view
	b.WriteString(promptStyle.Render("  Create Web App") + "\n\n")

	// Name field
	if m.step == stepName {
		b.WriteString(labelStyle.Render("  Name: ") + m.nameInput.View() + "\n")
	} else {
		b.WriteString(hintStyle.Render("  Name: ") + itemStyle.Render(m.appName) + "\n")
	}

	// URL field
	if m.step >= stepURL {
		if m.step == stepURL {
			b.WriteString(labelStyle.Render("  URL:  ") + m.urlInput.View() + "\n")
		} else {
			b.WriteString(hintStyle.Render("  URL:  ") + itemStyle.Render(m.appURL) + "\n")
		}
	}

	// Icon source
	if m.step >= stepIconSource {
		b.WriteString("\n" + labelStyle.Render("  Icon source:") + "\n")
		for i, label := range iconSourceLabels {
			if m.step == stepIconSource && i == m.srcCursor {
				b.WriteString(selStyle.Render("  ▸ "+label) + "\n")
			} else {
				b.WriteString(hintStyle.Render("    "+label) + "\n")
			}
		}
	}

	// Manual icon URL
	if m.step == stepIconURL {
		b.WriteString("\n" + labelStyle.Render("  Icon URL: ") + m.iconURLInput.View() + "\n")
	}

	// Isolated profile
	if m.step >= stepIsolated {
		b.WriteString("\n" + labelStyle.Render("  Isolate profile?") + "\n")
		for i, label := range isolatedLabels {
			if m.step == stepIsolated && i == m.isolatedCursor {
				b.WriteString(selStyle.Render("  ▸ "+label) + "\n")
			} else {
				b.WriteString(hintStyle.Render("    "+label) + "\n")
			}
		}
	}

	// Hints
	b.WriteString("\n")
	if m.step == stepIconSource || m.step == stepIsolated {
		b.WriteString(hintStyle.Render("  enter select  esc back"))
	} else {
		b.WriteString(hintStyle.Render("  enter next  esc back"))
	}

	border := m.border
	if m.width > 0 {
		border = border.Width(m.width - 2)
	}
	if m.height > 0 {
		border = border.Height(m.height - 2)
	}
	return border.Render(b.String())
}

func (m newModel) viewIconSearch(promptStyle, hintStyle, itemStyle, selStyle lipgloss.Style) string {
	queryStyle := lipgloss.NewStyle().Foreground(m.pal.fg)

	var b strings.Builder

	// Search line
	if m.loadingIcons {
		b.WriteString(promptStyle.Render("> ") + hintStyle.Render("loading icons..."))
	} else if m.loadErr != nil {
		b.WriteString(promptStyle.Render("> ") + hintStyle.Render("failed to load icons (enter for favicon)"))
	} else {
		query := m.searchInput.Value()
		if query != "" {
			b.WriteString(promptStyle.Render("> ") + queryStyle.Render(m.searchInput.View()))
		} else {
			b.WriteString(promptStyle.Render("> ") + m.searchInput.View())
		}
	}
	b.WriteString("\n\n")

	if !m.loadingIcons && m.loadErr == nil {
		if len(m.iconFiltered) == 0 {
			b.WriteString(hintStyle.Render("  no matches"))
		} else {
			vis := m.iconVisibleLines()
			end := m.iconOffset + vis
			if end > len(m.iconFiltered) {
				end = len(m.iconFiltered)
			}

			for i := m.iconOffset; i < end; i++ {
				im := m.iconFiltered[i]
				icon := m.allIcons[im.index]
				isCursor := i == m.iconCursor

				prefix := "  "
				if isCursor {
					prefix = "▸ "
				}

				b.WriteString(prefix)
				if isCursor {
					b.WriteString(selStyle.Render(icon.DisplayName))
				} else {
					b.WriteString(itemStyle.Render(icon.DisplayName))
				}
				b.WriteString(hintStyle.Render(" " + icon.Name))

				if i < end-1 {
					b.WriteString("\n")
				}
			}
		}
	}

	border := m.border
	if m.width > 0 {
		border = border.Width(m.width - 2)
	}
	if m.height > 0 {
		border = border.Height(m.height - 2)
	}
	return border.Render(b.String())
}
