package webapp

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// sanitizeName removes characters that are invalid in filenames across platforms.
func sanitizeName(name string) string {
	for _, c := range []string{`\`, `/`, `:`, `*`, `?`, `"`, `<`, `>`, `|`} {
		name = strings.ReplaceAll(name, c, "")
	}
	return strings.TrimSpace(name)
}

// WebApp represents a web app shortcut.
type WebApp struct {
	Name    string // Display name
	URL     string // Target URL
	ID      string // URL hash used as filesystem key
	LnkPath string // Full path to the shortcut file (.lnk or .desktop)
	IcoPath string // Full path to the icon file (may be empty)
}

// webAppMeta is the metadata stored alongside each web app.
type webAppMeta struct {
	Name     string `json:"name"`
	URL      string `json:"url"`
	Isolated bool   `json:"isolated,omitempty"`
}

// urlHash returns a short hash of a URL, used as the filesystem key for all web app files.
func urlHash(url string) string {
	return fmt.Sprintf("%x", sha256.Sum256([]byte(url)))[:12]
}

// MetaDir returns the directory for web app metadata files.
func MetaDir() string {
	dir, err := os.UserConfigDir()
	if err != nil {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "karchy", "webapp-meta")
}

// writeMeta writes metadata for a web app, keyed by URL hash.
func writeMeta(id string, meta webAppMeta) error {
	dir := MetaDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("create meta dir: %w", err)
	}
	data, err := json.Marshal(meta)
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, id+".json"), data, 0o644)
}

// readMeta reads metadata for a web app by its ID (URL hash).
func readMeta(id string) (webAppMeta, bool) {
	data, err := os.ReadFile(filepath.Join(MetaDir(), id+".json"))
	if err != nil {
		return webAppMeta{}, false
	}
	var meta webAppMeta
	if err := json.Unmarshal(data, &meta); err != nil {
		return webAppMeta{}, false
	}
	return meta, true
}

// readMetaByURL finds metadata by URL using its hash directly.
func readMetaByURL(url string) (webAppMeta, bool) {
	return readMeta(urlHash(url))
}

// appDataDir returns a per-URL Chrome user data directory under the karchy config dir.
func appDataDir(url string) string {
	dir, err := os.UserConfigDir()
	if err != nil {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "karchy", "webapp-profiles", urlHash(url))
}

// removeMeta deletes metadata and the isolated profile directory (if any) for a web app.
func removeMeta(id string) {
	meta, ok := readMeta(id)
	if ok && meta.Isolated {
		os.RemoveAll(appDataDir(meta.URL))
	}
	os.Remove(filepath.Join(MetaDir(), id+".json"))
}
