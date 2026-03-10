package tui

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/nulifyer/karchy/internal/actions/apps"
	"github.com/nulifyer/karchy/internal/actions/cleanup"
	"github.com/nulifyer/karchy/internal/actions/fonts"
	"github.com/nulifyer/karchy/internal/actions/install"
	"github.com/nulifyer/karchy/internal/actions/projects"
	"github.com/nulifyer/karchy/internal/actions/setup"
	"github.com/nulifyer/karchy/internal/actions/system"
	"github.com/nulifyer/karchy/internal/actions/wsl"
	"github.com/nulifyer/karchy/internal/config"
	"github.com/nulifyer/karchy/internal/terminal"
	"github.com/nulifyer/karchy/internal/theme"
)

// MenuItem represents a single menu entry.
type MenuItem struct {
	Icon      string
	Label     string
	Detail    string // muted text shown after label
	Checked   bool   // render prefix as green ✓
	Updatable bool   // render prefix as yellow ⬆ (takes priority over Checked)
	Action    func() menuResult
}

type menuResult struct {
	kind    resultKind
	submenu submenuKind
	action  func()
}

type resultKind int

const (
	resultNone resultKind = iota
	resultSubmenu
	resultBack
	resultQuit
	resultAction // quit TUI then run action
)

// TypedMenu defines a data-driven menu with strongly-typed items and handlers.
type TypedMenu[T any] struct {
	OnSelect func(T)   // handler for single selection
	OnBatch  func([]T) // handler for multi-selection
}

// TypedItem is a menu item carrying strongly-typed data.
type TypedItem[T any] struct {
	Label     string
	Detail    string
	Checked   bool
	Updatable bool
	Icon      string
	Data      T
}

// Build converts typed items into untyped MenuItems and handler closures.
func (tm TypedMenu[T]) Build(items []TypedItem[T]) ([]MenuItem, func(int), func(map[int]bool)) {
	menuItems := make([]MenuItem, len(items))
	for i, ti := range items {
		menuItems[i] = MenuItem{
			Label:     ti.Label,
			Detail:    ti.Detail,
			Checked:   ti.Checked,
			Updatable: ti.Updatable,
			Icon:      ti.Icon,
		}
	}

	var onSelect func(int)
	if tm.OnSelect != nil {
		onSelect = func(idx int) { tm.OnSelect(items[idx].Data) }
	}

	var onBatch func(map[int]bool)
	if tm.OnBatch != nil {
		onBatch = func(picked map[int]bool) {
			data := make([]T, 0, len(picked))
			for idx := range picked {
				data = append(data, items[idx].Data)
			}
			tm.OnBatch(data)
		}
	}

	return menuItems, onSelect, onBatch
}

// Async returns a tea.Cmd that loads items asynchronously and sends a menuLoadedMsg.
func (tm TypedMenu[T]) Async(load func() []TypedItem[T]) tea.Cmd {
	return func() tea.Msg {
		items, onSelect, onBatch := tm.Build(load())
		return menuLoadedMsg{items: items, onSelect: onSelect, onBatch: onBatch}
	}
}

type submenuKind int

const (
	menuMain submenuKind = iota
	menuApps
	menuProjects
	menuSetup
	menuInstall
	menuRemove
	menuUpdate
	menuSystem
	menuTheme
	menuEditor
	menuPackages
	menuRemovePackages
	menuWSL
	menuWSLLaunch
	menuWSLInstall
	menuWSLRemove
	menuFonts
	menuRemoveFonts
	menuSetupFont
	menuAUR
	menuPowerProfile
	menuHardwareRestart
)

func submenu(s submenuKind) func() menuResult {
	return func() menuResult { return menuResult{kind: resultSubmenu, submenu: s} }
}

func action(fn func()) func() menuResult {
	return func() menuResult { return menuResult{kind: resultAction, action: fn} }
}

// Menu definitions

func mainMenu() []MenuItem {
	items := []MenuItem{
		{Label: "Apps", Action: submenu(menuApps)},
		{Label: "Projects", Action: submenu(menuProjects)},
		{Label: "Setup", Action: submenu(menuSetup)},
		{Label: "Install", Action: submenu(menuInstall)},
		{Label: "Remove", Action: submenu(menuRemove)},
		{Label: "Update", Action: submenu(menuUpdate)},
		{Label: "System", Action: submenu(menuSystem)},
	}
	if runtime.GOOS == "windows" {
		items = append(items, MenuItem{Label: "WSL", Action: submenu(menuWSL)})
	}
	return items
}

func setupMenu() []MenuItem {
	items := []MenuItem{
		{Label: "Audio", Action: action(setup.Audio)},
		{Label: "Wi-Fi", Action: action(setup.WiFi)},
		{Label: "Bluetooth", Action: action(setup.Bluetooth)},
		{Label: "Display", Action: action(setup.Display)},
		{Label: "Power", Action: action(setup.Power)},
		{Label: "Timezone", Action: action(setup.Timezone)},
	}
	if profiles := setup.PowerProfiles(); len(profiles) > 0 {
		items = append(items, MenuItem{Label: "Power Profile", Action: submenu(menuPowerProfile)})
	}
	if runtime.GOOS == "linux" {
		items = append(items, MenuItem{Label: "Restart Hardware", Action: submenu(menuHardwareRestart)})
	}
	items = append(items,
		MenuItem{Label: "Font", Action: submenu(menuSetupFont)},
		MenuItem{Label: "Theme", Action: submenu(menuTheme)},
	)
	if runtime.GOOS == "windows" {
		items = append(items, MenuItem{Label: "Chris Titus WinUtil", Action: action(setup.WinUtil)})
	}
	return items
}

func appsMenu() []MenuItem {
	entries := apps.Scan()
	items := make([]MenuItem, len(entries))
	for i, entry := range entries {
		e := entry // capture for closure
		items[i] = MenuItem{
			Label:  e.Name,
			Action: action(func() { apps.Launch(e) }),
		}
	}
	return items
}

var projectsMenuDef = TypedMenu[projects.ProjectEntry]{
	OnSelect: projects.Open,
}

func loadProjectItems() []TypedItem[projects.ProjectEntry] {
	home, _ := os.UserHomeDir()
	entries := projects.Scan()
	items := make([]TypedItem[projects.ProjectEntry], len(entries))
	for i, e := range entries {
		items[i] = TypedItem[projects.ProjectEntry]{
			Label:  e.Name,
			Detail: shortenPath(e.Path, home),
			Data:   e,
		}
	}
	return items
}

func shortenPath(path, home string) string {
	if runtime.GOOS == "windows" {
		path = filepath.ToSlash(path)
		home = filepath.ToSlash(home)
	}
	if strings.HasPrefix(path, home) {
		path = "~" + path[len(home):]
	}
	// Show parent dir, not the project dir itself (already in Label)
	return filepath.Dir(path)
}

func editorMenu() []MenuItem {
	current := projects.CurrentEditor()
	available := projects.AvailableEditors()
	items := make([]MenuItem, len(available))
	for i, ed := range available {
		label := ed.Name
		if ed.Command == current {
			label += " (current)"
		}
		cmd := ed.Command
		items[i] = MenuItem{
			Label: label,
			Action: action(func() {
				config.SaveEditor(cmd)
			}),
		}
	}
	return items
}

func installMenu() []MenuItem {
	pkgLabel := "Pacman"
	if runtime.GOOS == "windows" {
		pkgLabel = "Winget"
	}
	items := []MenuItem{
		{Label: pkgLabel, Action: submenu(menuPackages)},
	}
	if runtime.GOOS == "linux" && install.HasAUR() {
		items = append(items, MenuItem{Label: fmt.Sprintf("AUR (%s)", install.AURHelper()), Action: submenu(menuAUR)})
	}
	items = append(items,
		MenuItem{Label: "Web App", Action: action(func() {
			terminal.Launch(70, 25, "Web App", "webapp", "new")
		})},
		MenuItem{Label: "Font", Action: submenu(menuFonts)},
	)
	return items
}

var packagesMenu = TypedMenu[install.PackageEntry]{
	OnSelect: func(pkg install.PackageEntry) { install.BatchInstall([]install.PackageEntry{pkg}) },
	OnBatch:  install.BatchInstall,
}

var aurMenu = TypedMenu[install.PackageEntry]{
	OnSelect: func(pkg install.PackageEntry) { install.AURInstall([]install.PackageEntry{pkg}) },
	OnBatch:  install.AURInstall,
}

func loadAURItems() []TypedItem[install.PackageEntry] {
	entries, installed := install.SearchAUR(), install.AURInstalledIDs()
	items := make([]TypedItem[install.PackageEntry], len(entries))
	for i, e := range entries {
		installedVer, isInstalled := installed[e.ID]
		detail := e.ID
		hasUpdate := false
		if isInstalled && installedVer != "" {
			latest := install.ParseSemVer(e.Version)
			current := install.ParseSemVer(installedVer)
			if latest.IsNewerThan(current) {
				detail = e.ID + "  " + installedVer + " → " + e.Version
				hasUpdate = true
			}
		}
		items[i] = TypedItem[install.PackageEntry]{
			Label:     e.Name,
			Detail:    detail,
			Checked:   isInstalled && !hasUpdate,
			Updatable: hasUpdate,
			Data:      e,
		}
	}
	return items
}

func loadPackageItems() []TypedItem[install.PackageEntry] {
	entries, installed := install.SearchPackages(), install.InstalledIDs()
	items := make([]TypedItem[install.PackageEntry], len(entries))
	for i, e := range entries {
		installedVer, isInstalled := installed[e.ID]
		detail := e.ID
		hasUpdate := false
		if isInstalled && installedVer != "" {
			latest := install.ParseSemVer(e.Version)
			current := install.ParseSemVer(installedVer)
			if latest.IsNewerThan(current) {
				detail = e.ID + "  " + installedVer + " → " + e.Version
				hasUpdate = true
			}
		}
		items[i] = TypedItem[install.PackageEntry]{
			Label:     e.Name,
			Detail:    detail,
			Checked:   isInstalled && !hasUpdate,
			Updatable: hasUpdate,
			Data:      e,
		}
	}
	return items
}

func removeMenu() []MenuItem {
	return []MenuItem{
		{Label: "Package Manager", Action: submenu(menuRemovePackages)},
		{Label: "Web App", Action: action(func() {
			terminal.Launch(60, 25, "Remove Web Apps", "webapp", "remove")
		})},
		{Label: "Font", Action: submenu(menuRemoveFonts)},
	}
}

var removePackagesMenu = TypedMenu[install.InstalledPackage]{
	OnSelect: func(pkg install.InstalledPackage) { install.BatchUninstall([]install.InstalledPackage{pkg}) },
	OnBatch:  install.BatchUninstall,
}

func loadRemovePackageItems() []TypedItem[install.InstalledPackage] {
	entries := install.InstalledPackages()
	items := make([]TypedItem[install.InstalledPackage], len(entries))
	for i, e := range entries {
		detail := ""
		if e.Version != "" {
			detail = "v" + e.Version
		}
		if e.ID != "" {
			if detail != "" {
				detail += "  "
			}
			detail += e.ID
		}
		items[i] = TypedItem[install.InstalledPackage]{
			Label:  e.Name,
			Detail: detail,
			Data:   e,
		}
	}
	return items
}

func updateMenu() []MenuItem {
	items := []MenuItem{
		{Label: "System Update", Action: action(func() { install.SystemUpdate() })},
	}
	if runtime.GOOS == "linux" {
		items = append(items,
			MenuItem{Label: "Mirror Update", Action: action(install.MirrorUpdate)},
			MenuItem{Label: "Firmware Update", Action: action(install.FirmwareUpdate)},
		)
	}
	items = append(items, MenuItem{Label: "Cleanup", Action: action(cleanup.Run)})
	return items
}

func systemMenu() []MenuItem {
	return []MenuItem{
		{Label: "Lock", Action: action(system.Lock)},
		{Label: "Sleep", Action: action(system.Sleep)},
		{Label: "Hibernate", Action: action(system.Hibernate)},
		{Label: "Logout", Action: action(system.Logout)},
		{Label: "Restart", Action: action(system.Restart)},
		{Label: "Shutdown", Action: action(system.Shutdown)},
	}
}

func wslMenu() []MenuItem {
	return []MenuItem{
		{Label: "Launch Distro", Action: submenu(menuWSLLaunch)},
		{Label: "Install Distro", Action: submenu(menuWSLInstall)},
		{Label: "Remove Distro", Action: submenu(menuWSLRemove)},
		{Label: "Shutdown WSL", Action: action(wsl.Shutdown)},
		{Label: "Enable WSL", Action: action(wsl.Enable)},
	}
}

var wslLaunchMenu = TypedMenu[wsl.Distro]{
	OnSelect: wsl.Launch,
}

func loadWSLLaunchItems() []TypedItem[wsl.Distro] {
	distros := wsl.ListInstalled()
	items := make([]TypedItem[wsl.Distro], len(distros))
	for i, d := range distros {
		items[i] = TypedItem[wsl.Distro]{Label: d.Name, Data: d}
	}
	return items
}

var wslInstallMenu = TypedMenu[wsl.Distro]{
	OnSelect: func(d wsl.Distro) { wsl.Install([]wsl.Distro{d}) },
	OnBatch:  wsl.Install,
}

func loadWSLInstallItems() []TypedItem[wsl.Distro] {
	distros := wsl.ListOnline()
	items := make([]TypedItem[wsl.Distro], len(distros))
	for i, d := range distros {
		items[i] = TypedItem[wsl.Distro]{Label: d.Name, Data: d}
	}
	return items
}

var wslRemoveMenu = TypedMenu[wsl.Distro]{
	OnSelect: func(d wsl.Distro) { wsl.Remove([]wsl.Distro{d}) },
	OnBatch:  wsl.Remove,
}

func loadWSLRemoveItems() []TypedItem[wsl.Distro] {
	distros := wsl.ListInstalled()
	items := make([]TypedItem[wsl.Distro], len(distros))
	for i, d := range distros {
		items[i] = TypedItem[wsl.Distro]{Label: d.Name, Data: d}
	}
	return items
}

var fontsMenu = TypedMenu[fonts.Font]{
	OnSelect: func(f fonts.Font) { fonts.Install([]fonts.Font{f}) },
	OnBatch:  fonts.Install,
}

func loadFontItems() []TypedItem[fonts.Font] {
	all := fonts.All()
	installed := fonts.Installed()
	items := make([]TypedItem[fonts.Font], len(all))
	for i, f := range all {
		items[i] = TypedItem[fonts.Font]{
			Label:   f.Name,
			Checked: installed[f.Name],
			Data:    f,
		}
	}
	return items
}

var removeFontsMenu = TypedMenu[fonts.Font]{
	OnSelect: func(f fonts.Font) { fonts.Uninstall([]fonts.Font{f}) },
	OnBatch:  fonts.Uninstall,
}

func loadRemoveFontItems() []TypedItem[fonts.Font] {
	all := fonts.All()
	installed := fonts.Installed()
	var items []TypedItem[fonts.Font]
	for _, f := range all {
		if installed[f.Name] {
			items = append(items, TypedItem[fonts.Font]{
				Label: f.Name,
				Data:  f,
			})
		}
	}
	return items
}

func themeMenu() []MenuItem {
	current := config.Load().Theme.Name
	names := theme.Names()
	sort.Strings(names)

	items := make([]MenuItem, len(names))
	for i, name := range names {
		label := name
		if name == current {
			label += " (current)"
		}
		n := name // capture for closure
		items[i] = MenuItem{
			Label: label,
			Action: action(func() {
				setup.SelectTheme(n)
			}),
		}
	}
	return items
}

var setupFontMenu = TypedMenu[fonts.Font]{
	OnSelect: func(f fonts.Font) { config.SaveFont(f.Family()) },
}

func loadSetupFontItems() []TypedItem[fonts.Font] {
	installed := fonts.Installed()
	current := config.Load().Appearance.FontFamily
	var items []TypedItem[fonts.Font]
	for _, f := range fonts.All() {
		if !installed[f.Name] {
			continue
		}
		label := f.Name
		if f.Family() == current {
			label += " (current)"
		}
		items = append(items, TypedItem[fonts.Font]{
			Label: label,
			Data:  f,
		})
	}
	return items
}

func powerProfileMenu() []MenuItem {
	current := setup.PowerProfile()
	profiles := setup.PowerProfiles()
	items := make([]MenuItem, len(profiles))
	for i, p := range profiles {
		label := p
		if p == current {
			label += " (current)"
		}
		profile := p
		items[i] = MenuItem{
			Label: label,
			Action: action(func() {
				setup.SetPowerProfile(profile)
			}),
		}
	}
	return items
}

func hardwareRestartMenu() []MenuItem {
	return []MenuItem{
		{Label: "Audio (PipeWire)", Action: action(setup.RestartAudio)},
		{Label: "Wi-Fi (NetworkManager)", Action: action(setup.RestartWiFi)},
		{Label: "Bluetooth", Action: action(setup.RestartBluetooth)},
	}
}

// menuSize returns the Alacritty cols×lines for a given menu.
type menuSize struct {
	cols, lines int
}

func getMenuSize(s submenuKind) menuSize {
	switch s {
	case menuPackages, menuRemovePackages, menuAUR:
		return menuSize{80, 35}
	case menuApps, menuProjects, menuEditor:
		return menuSize{60, 25}
	case menuFonts:
		return menuSize{60, 35}
	case menuRemoveFonts, menuSetupFont:
		return menuSize{60, 25}
	case menuWSLLaunch, menuWSLInstall, menuWSLRemove:
		return menuSize{50, 20}
	default:
		return menuSize{40, 14}
	}
}

func getMenu(s submenuKind) ([]MenuItem, string) {
	switch s {
	case menuApps:
		return appsMenu(), "Apps"
	case menuProjects:
		return nil, "Projects" // loaded async via getMenuAsync
	case menuEditor:
		return editorMenu(), "Editor"
	case menuSetup:
		return setupMenu(), "Setup"
	case menuInstall:
		return installMenu(), "Install"
	case menuPackages:
		return nil, "Packages" // loaded async via getMenuAsync
	case menuRemove:
		return removeMenu(), "Remove"
	case menuRemovePackages:
		return nil, "Remove Packages" // loaded async via getMenuAsync
	case menuUpdate:
		return updateMenu(), "Update"
	case menuSystem:
		return systemMenu(), "System"
	case menuTheme:
		return themeMenu(), "Theme"
	case menuFonts:
		return nil, "Fonts"
	case menuRemoveFonts:
		return nil, "Remove Fonts"
	case menuSetupFont:
		return nil, "Font"
	case menuWSL:
		return wslMenu(), "WSL"
	case menuWSLLaunch:
		return nil, "Launch Distro"
	case menuWSLInstall:
		return nil, "Install Distro"
	case menuWSLRemove:
		return nil, "Remove Distro"
	case menuAUR:
		return nil, "AUR Packages"
	case menuPowerProfile:
		return powerProfileMenu(), "Power Profile"
	case menuHardwareRestart:
		return hardwareRestartMenu(), "Restart Hardware"
	default:
		return mainMenu(), "Karchy"
	}
}

// getMenuTitle returns the title for a submenu (used during async loading).
func getMenuTitle(s submenuKind) string {
	_, title := getMenu(s)
	return title
}

// isMultiSelect returns true for menus that support multi-select via space.
func isMultiSelect(s submenuKind) bool {
	return s == menuPackages || s == menuRemovePackages || s == menuAUR || s == menuFonts || s == menuRemoveFonts || s == menuWSLInstall || s == menuWSLRemove
}

// getMenuAsync returns a tea.Cmd loader for menus that load asynchronously, or nil.
func getMenuAsync(s submenuKind) tea.Cmd {
	switch s {
	case menuProjects:
		return projectsMenuDef.Async(loadProjectItems)
	case menuPackages:
		return packagesMenu.Async(loadPackageItems)
	case menuRemovePackages:
		return removePackagesMenu.Async(loadRemovePackageItems)
	case menuFonts:
		return fontsMenu.Async(loadFontItems)
	case menuRemoveFonts:
		return removeFontsMenu.Async(loadRemoveFontItems)
	case menuWSLLaunch:
		return wslLaunchMenu.Async(loadWSLLaunchItems)
	case menuWSLInstall:
		return wslInstallMenu.Async(loadWSLInstallItems)
	case menuWSLRemove:
		return wslRemoveMenu.Async(loadWSLRemoveItems)
	case menuSetupFont:
		return setupFontMenu.Async(loadSetupFontItems)
	case menuAUR:
		return aurMenu.Async(loadAURItems)
	}
	return nil
}
