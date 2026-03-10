// Package filterlist provides a reusable fuzzy-filtered scrolling list
// for bubbletea TUI models. It handles filtering, cursor movement,
// viewport scrolling, and highlighted label rendering.
package filterlist

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/sahilm/fuzzy"
)

// Item represents a single entry in the list.
type Item struct {
	Label     string
	Detail    string // muted text shown after label
	Checked   bool
	Updatable bool
	Icon      string
}

// FilteredEntry maps a filtered result back to the original item index.
type FilteredEntry struct {
	Index      int
	MatchedIdx []int
}

// List manages fuzzy filtering, cursor position, and scroll offset.
type List struct {
	Items    []Item
	Filtered []FilteredEntry
	Cursor   int
	Offset   int
	Query    string
}

// ApplyFilter runs fuzzy search against items using both Label and Detail.
func (l *List) ApplyFilter() {
	if l.Query == "" {
		l.Filtered = make([]FilteredEntry, len(l.Items))
		for i := range l.Items {
			l.Filtered[i] = FilteredEntry{Index: i}
		}
		return
	}

	searchable := make([]string, len(l.Items))
	for i, item := range l.Items {
		if item.Detail != "" {
			searchable[i] = item.Label + " " + item.Detail
		} else {
			searchable[i] = item.Label
		}
	}

	matches := fuzzy.Find(l.Query, searchable)
	l.Filtered = make([]FilteredEntry, len(matches))
	for i, match := range matches {
		l.Filtered[i] = FilteredEntry{
			Index:      match.Index,
			MatchedIdx: match.MatchedIndexes,
		}
	}
}

// VisibleLines returns how many items fit in the viewport.
// overhead is the number of lines consumed by border, search bar, etc.
func (l *List) VisibleLines(height, overhead int) int {
	if height <= 0 {
		return len(l.Filtered)
	}
	v := height - overhead
	if v < 1 {
		v = 1
	}
	return v
}

// EnsureCursorVisible adjusts scroll offset so the cursor is in view.
func (l *List) EnsureCursorVisible(height, overhead int) {
	vis := l.VisibleLines(height, overhead)
	if l.Cursor < l.Offset {
		l.Offset = l.Cursor
	} else if l.Cursor >= l.Offset+vis {
		l.Offset = l.Cursor - vis + 1
	}
}

// HandleKey processes a key event for navigation and search input.
// Returns true if the key was handled by the list.
// Does not handle enter, space (toggle), or esc — those are caller-specific.
func (l *List) HandleKey(key string, height, overhead int) bool {
	switch key {
	case "up", "ctrl+k":
		if l.Cursor > 0 {
			l.Cursor--
		} else if len(l.Filtered) > 0 {
			l.Cursor = len(l.Filtered) - 1
		}
		l.EnsureCursorVisible(height, overhead)
		return true

	case "down", "ctrl+j":
		if l.Cursor < len(l.Filtered)-1 {
			l.Cursor++
		} else {
			l.Cursor = 0
		}
		l.EnsureCursorVisible(height, overhead)
		return true

	case "backspace":
		if len(l.Query) > 0 {
			l.Query = l.Query[:len(l.Query)-1]
			l.Cursor = 0
			l.Offset = 0
			l.ApplyFilter()
			return true
		}
		return false

	default:
		if len(key) == 1 && key[0] >= ' ' {
			l.Query += key
			l.Cursor = 0
			l.Offset = 0
			l.ApplyFilter()
			return true
		}
		return false
	}
}

// Reset clears the query and cursor state.
func (l *List) Reset() {
	l.Query = ""
	l.Cursor = 0
	l.Offset = 0
	l.ApplyFilter()
}

// SetItems replaces items and reapplies the current filter.
func (l *List) SetItems(items []Item) {
	l.Items = items
	l.ApplyFilter()
}

// RenderLabel renders a label with fuzzy match highlighting.
func RenderLabel(label string, matched []int, selected bool, matchStyle, selStyle, itemStyle lipgloss.Style) string {
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
		if isMatch {
			sb.WriteString(matchStyle.Render(run))
		} else if selected {
			sb.WriteString(selStyle.Render(run))
		} else {
			sb.WriteString(itemStyle.Render(run))
		}
		i = j
	}
	return sb.String()
}

// ClampMatchedIdx removes fuzzy match indices beyond the truncated label length.
func ClampMatchedIdx(idx []int, maxLen int) []int {
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

// StripAnsi removes ANSI escape sequences from a string.
func StripAnsi(s string) string {
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

// SpliceBottomBorderLabel replaces the right side of a rendered border's bottom
// line with a styled label (e.g. " 3 selected ").
func SpliceBottomBorderLabel(rendered, label string, labelStyle lipgloss.Style, borderStyle lipgloss.Style) string {
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

	plain := StripAnsi(string([]rune(lines[len(lines)-1])))
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
	sb.WriteString(labelStyle.Render(label))
	sb.WriteString(bc.Render(cornerRight))
	lines[len(lines)-1] = sb.String()
	return strings.Join(lines, "\n")
}
