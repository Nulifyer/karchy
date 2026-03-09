package webapp

// WebApp represents a web app shortcut.
type WebApp struct {
	Name    string // Display name (also the shortcut filename stem)
	URL     string // Target URL
	LnkPath string // Full path to the shortcut file (.lnk or .desktop)
	IcoPath string // Full path to the icon file (may be empty)
}
