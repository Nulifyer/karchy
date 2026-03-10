//go:build windows

package webapp

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/platform"
	"github.com/nulifyer/karchy/internal/terminal"
)

const (
	colorGreen = "\033[32m"
	colorRed   = "\033[31m"
	colorCyan  = "\033[36m"
	colorBold  = "\033[1m"
	colorReset = "\033[0m"

	dashboardIconFmt = "png"
)

// ShortcutDir returns the Start Menu folder for Karchy web apps.
func ShortcutDir() string {
	return filepath.Join(os.Getenv("APPDATA"), `Microsoft\Windows\Start Menu\Programs\Karchy Web Apps`)
}

// IconDir returns the directory where web app icons are stored.
func IconDir() string {
	dir, err := os.UserConfigDir()
	if err != nil {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "karchy", "webapp-icons")
}

// convertIcon converts a downloaded image to .ico format.
func convertIcon(id, tmpPath, sourceURL string) (string, error) {
	icoPath := filepath.Join(IconDir(), id+".ico")

	// If already .ico, just move it
	if strings.HasSuffix(strings.ToLower(sourceURL), ".ico") {
		if err := os.Rename(tmpPath, icoPath); err != nil {
			return "", err
		}
		return icoPath, nil
	}

	// Read PNG and wrap in ICO
	data, err := os.ReadFile(tmpPath)
	if err != nil {
		return "", err
	}
	if err := pngToICO(data, icoPath); err != nil {
		return "", err
	}
	return icoPath, nil
}

// Scan returns all installed web app shortcuts.
func Scan() []WebApp {
	dir := ShortcutDir()
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}

	var apps []WebApp
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(strings.ToLower(e.Name()), ".lnk") {
			continue
		}
		lnkPath := filepath.Join(dir, e.Name())
		desc, err := platform.ReadShortcutDescription(lnkPath)
		if err != nil || !strings.HasPrefix(desc, "karchy:") {
			continue
		}
		id := strings.TrimPrefix(desc, "karchy:")
		meta, ok := readMeta(id)
		if !ok {
			continue
		}
		apps = append(apps, WebApp{
			Name:    meta.Name,
			URL:     meta.URL,
			ID:      id,
			LnkPath: lnkPath,
		})
	}
	return apps
}

// Remove deletes web app shortcuts and their icons.
func Remove(apps []WebApp) {
	if len(apps) == 0 {
		return
	}

	terminal.ResizeAndCenter(60, 16)

	fmt.Printf("\n Web Apps (%d)\n\n", len(apps))
	for _, app := range apps {
		fmt.Printf(" %s\n", app.Name)
	}

	fmt.Printf("\n %s%s:: Proceed with removal? [Y/n]%s ", colorBold, colorCyan, colorReset)
	line := readLine()
	if len(line) > 0 && (line[0] == 'n' || line[0] == 'N') {
		return
	}

	fmt.Printf("\n %s%s:: Removing web apps...%s\n\n", colorBold, colorCyan, colorReset)

	iconDir := IconDir()
	for _, app := range apps {
		// Remove shortcut
		if err := os.Remove(app.LnkPath); err != nil {
			fmt.Printf(" %s  %sfailed: %v%s\n", app.Name, colorRed, err, colorReset)
			continue
		}
		// Remove icon (try common extensions)
		for _, ext := range []string{".ico", ".png", ".svg"} {
			os.Remove(filepath.Join(iconDir, app.ID+ext))
		}
		removeMeta(app.ID)
		fmt.Printf(" %s  %sremoved%s\n", app.Name, colorGreen, colorReset)
	}

	fmt.Printf("\n %s%s:: Done.%s\n\n", colorBold, colorGreen, colorReset)
	fmt.Print(" Press Enter to close...")
	readLine()
}

// deleteApps removes shortcut files and their icons, printing results.
func deleteApps(apps []WebApp) {
	fmt.Printf("\n %s%s:: Removing web apps...%s\n\n", colorBold, colorCyan, colorReset)
	iconDir := IconDir()
	for _, app := range apps {
		if err := os.Remove(app.LnkPath); err != nil {
			fmt.Printf(" %s  %sfailed: %v%s\n", app.Name, colorRed, err, colorReset)
			continue
		}
		for _, ext := range []string{".ico", ".png", ".svg"} {
			os.Remove(filepath.Join(iconDir, app.ID+ext))
		}
		fmt.Printf(" %s  %sremoved%s\n", app.Name, colorGreen, colorReset)
	}
	fmt.Printf("\n %s%s:: Done.%s\n", colorBold, colorGreen, colorReset)
}

// Create interactively prompts for name, URL, icon choice, then creates a shortcut.
func Create() {
	terminal.ResizeAndCenter(80, 25)

	fmt.Printf("\n %s%s:: Create a new web app%s\n\n", colorBold, colorCyan, colorReset)

	// Name
	fmt.Print(" Name: ")
	appName := sanitizeName(readLine())
	if appName == "" {
		return
	}

	// URL
	fmt.Print(" URL: ")
	appURL := readLine()
	if appURL == "" {
		return
	}
	if !strings.Contains(appURL, "://") {
		appURL = "https://" + appURL
	}

	id := urlHash(appURL)

	// Icon source
	fmt.Println("\n Icon source:")
	fmt.Println("  1) Search dashboard icons")
	fmt.Println("  2) Auto-detect favicon")
	fmt.Println("  3) Enter URL manually")
	fmt.Print(" Choose (1-3): ")
	choice := readLine()

	var iconURL string
	switch choice {
	case "1":
		fmt.Printf("\n Loading dashboard icons...")
		icons, commit, err := LoadDashboardIcons()
		if err != nil {
			fmt.Printf(" %sfailed: %v%s\n", colorRed, err, colorReset)
			fmt.Println(" Falling back to favicon.")
			iconURL = FaviconURL(appURL)
		} else {
			fmt.Printf(" %d icons available.\n", len(icons))
			fmt.Print(" Search: ")
			query := strings.ToLower(readLine())

			var matches []DashboardIcon
			for _, ic := range icons {
				if strings.Contains(strings.ToLower(ic.Name), query) ||
					strings.Contains(strings.ToLower(ic.DisplayName), query) {
					matches = append(matches, ic)
				}
			}

			if len(matches) == 0 {
				fmt.Println(" No matches. Using favicon.")
				iconURL = FaviconURL(appURL)
			} else {
				limit := len(matches)
				if limit > 10 {
					limit = 10
				}
				fmt.Println()
				for i, m := range matches[:limit] {
					fmt.Printf("  %d) %s\n", i+1, m.DisplayName)
				}
				if len(matches) > 10 {
					fmt.Printf("  ... and %d more\n", len(matches)-10)
				}
				fmt.Print(" Pick (number): ")
				pick := readLine()
				var idx int
				fmt.Sscanf(pick, "%d", &idx)
				if idx >= 1 && idx <= limit {
					iconURL = DashboardIconURL(commit, matches[idx-1].Name)
				} else {
					iconURL = FaviconURL(appURL)
				}
			}
		}
	case "3":
		fmt.Print(" Icon URL: ")
		iconURL = readLine()
	default:
		iconURL = FaviconURL(appURL)
	}

	// Download icon
	var iconPath string
	if iconURL != "" {
		fmt.Print("\n Downloading icon...")
		var err error
		iconPath, err = DownloadIcon(id, iconURL)
		if err != nil {
			fmt.Printf(" %sfailed: %v%s\n", colorRed, err, colorReset)
		} else {
			fmt.Printf(" %sdone%s\n", colorGreen, colorReset)
		}
	}

	// Create shortcut
	fmt.Print(" Creating shortcut...")
	if err := createShortcut(appName, appURL, iconPath, false); err != nil {
		fmt.Printf(" %sfailed: %v%s\n", colorRed, err, colorReset)
		fmt.Print("\n Press Enter to close...")
		readLine()
		return
	}
	fmt.Printf(" %sdone%s\n", colorGreen, colorReset)

	fmt.Printf("\n %s%s:: Web app '%s' created!%s\n", colorBold, colorGreen, appName, colorReset)
	fmt.Printf(" You can find it in Start Menu > Karchy Web Apps\n\n")
	fmt.Print(" Press Enter to close...")
	readLine()
}

// createShortcut creates a .lnk file that runs `karchy webapp launch <url>`.
func createShortcut(appName, appURL, iconPath string, isolated bool) error {
	id := urlHash(appURL)
	dir := ShortcutDir()
	os.MkdirAll(dir, 0755)
	lnkPath := filepath.Join(dir, appName+".lnk")

	self, err := os.Executable()
	if err != nil {
		return fmt.Errorf("find executable: %w", err)
	}

	arguments := fmt.Sprintf(`webapp launch "%s"`, appURL)
	logging.Info("createShortcut: %s → %s %s", lnkPath, self, arguments)

	if err := platform.CreateShortcut(platform.ShortcutOptions{
		LnkPath:     lnkPath,
		TargetPath:  self,
		Arguments:   arguments,
		Description: "karchy:" + id,
		IconPath:    iconPath,
	}); err != nil {
		return err
	}
	if err := writeMeta(id, webAppMeta{Name: appName, URL: appURL, Isolated: isolated}); err != nil {
		logging.Info("writeMeta failed: %v", err)
	}
	return nil
}
