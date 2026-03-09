package apps

import (
	"path/filepath"
	"sort"
	"strings"
)

// AppEntry represents a discovered application.
type AppEntry struct {
	Name string
	Path string
}

// nameFromPath extracts an app name from a file path by stripping the extension.
func nameFromPath(path string) string {
	return strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
}

// dedupSorted removes consecutive duplicate names (case-insensitive).
func dedupSorted(entries []AppEntry) []AppEntry {
	if len(entries) == 0 {
		return entries
	}
	result := []AppEntry{entries[0]}
	for _, e := range entries[1:] {
		if !strings.EqualFold(e.Name, result[len(result)-1].Name) {
			result = append(result, e)
		}
	}
	return result
}

// sortEntries sorts app entries by name (case-insensitive).
func sortEntries(entries []AppEntry) {
	sort.Slice(entries, func(i, j int) bool {
		return strings.ToLower(entries[i].Name) < strings.ToLower(entries[j].Name)
	})
}
