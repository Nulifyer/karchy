//go:build !windows

package platform

// ShortcutOptions configures a shortcut file.
type ShortcutOptions struct {
	LnkPath     string
	TargetPath  string
	Arguments   string
	WorkingDir  string
	Description string
	IconPath    string
}

// CreateShortcut is a no-op on non-Windows platforms.
func CreateShortcut(opts ShortcutOptions) error {
	return nil
}
