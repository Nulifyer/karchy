package webapp

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// WebApp represents a web app shortcut.
type WebApp struct {
	Name    string // Display name (also the shortcut filename stem)
	URL     string // Target URL
	LnkPath string // Full path to the shortcut file (.lnk or .desktop)
	IcoPath string // Full path to the icon file (may be empty)
}

// webAppMeta is the metadata stored alongside each web app.
type webAppMeta struct {
	URL        string `json:"url"`
	ProfileDir string `json:"profileDir"`
}

// MetaDir returns the directory for web app metadata files.
func MetaDir() string {
	dir, err := os.UserConfigDir()
	if err != nil {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "karchy", "webapp-meta")
}

// writeMeta writes metadata for a web app.
func writeMeta(appName string, meta webAppMeta) error {
	dir := MetaDir()
	os.MkdirAll(dir, 0755)
	data, err := json.Marshal(meta)
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, appName+".json"), data, 0644)
}

// readMeta reads metadata for a web app.
func readMeta(appName string) (webAppMeta, bool) {
	data, err := os.ReadFile(filepath.Join(MetaDir(), appName+".json"))
	if err != nil {
		return webAppMeta{}, false
	}
	var meta webAppMeta
	if err := json.Unmarshal(data, &meta); err != nil {
		return webAppMeta{}, false
	}
	return meta, true
}

// removeMeta deletes metadata and the associated profile directory for a web app.
func removeMeta(appName string) {
	meta, ok := readMeta(appName)
	if ok && meta.ProfileDir != "" {
		os.RemoveAll(meta.ProfileDir)
	}
	os.Remove(filepath.Join(MetaDir(), appName+".json"))
}
