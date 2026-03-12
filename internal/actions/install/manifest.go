package install

import (
	"fmt"
	"io"
	"net/http"
	"runtime"
	"strconv"
	"strings"

	"github.com/nulifyer/karchy/internal/logging"
)

const manifestBaseURL = "https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests"

// NestedInstallerFile identifies a file inside a ZIP archive to run as the actual installer.
type NestedInstallerFile struct {
	RelativeFilePath string
}

// PackageDependency represents a required package dependency.
type PackageDependency struct {
	PackageIdentifier string
	MinimumVersion    string
}

// Dependencies holds package and OS-level dependencies.
type Dependencies struct {
	PackageDependencies []PackageDependency
	WindowsFeatures     []string
}

// InstallerManifest holds the parsed installer manifest for a package.
type InstallerManifest struct {
	ID      string
	Version string

	// Top-level defaults (can be overridden per-installer)
	InstallerType        string
	Scope                string // "user", "machine", or ""
	ElevationRequirement string // "elevationRequired", "elevatesSelf", "elevationProhibited"
	Silent               string
	SilentProgress       string
	Custom               string
	InstallerSuccessCodes []int
	NestedInstallerType   string
	NestedInstallerFiles  []NestedInstallerFile
	Dependencies          Dependencies

	Installers []InstallerEntry
}

// InstallerEntry represents a single installer variant.
type InstallerEntry struct {
	Architecture         string
	Scope                string // "user", "machine", or ""
	InstallerType        string // overrides top-level if set
	InstallerURL         string
	SHA256               string
	Locale               string
	ElevationRequirement string // overrides top-level if set
	Silent               string // overrides top-level if set
	SilentProgress       string // overrides top-level if set
	Custom               string // overrides top-level if set
	InstallerSuccessCodes []int
	NestedInstallerType   string
	NestedInstallerFiles  []NestedInstallerFile
	Dependencies          Dependencies
}

// EffectiveType returns the entry's type, falling back to the manifest default.
func (e InstallerEntry) EffectiveType(m *InstallerManifest) string {
	if e.InstallerType != "" {
		return e.InstallerType
	}
	return m.InstallerType
}

// EffectiveScope returns the entry's scope, falling back to the manifest default.
func (e InstallerEntry) EffectiveScope(m *InstallerManifest) string {
	if e.Scope != "" {
		return e.Scope
	}
	return m.Scope
}

// EffectiveElevationRequirement returns the entry's elevation requirement,
// falling back to the manifest default.
func (e InstallerEntry) EffectiveElevationRequirement(m *InstallerManifest) string {
	if e.ElevationRequirement != "" {
		return e.ElevationRequirement
	}
	return m.ElevationRequirement
}

// EffectiveSuccessCodes returns the entry's success codes, falling back to the manifest default.
func (e InstallerEntry) EffectiveSuccessCodes(m *InstallerManifest) []int {
	if len(e.InstallerSuccessCodes) > 0 {
		return e.InstallerSuccessCodes
	}
	return m.InstallerSuccessCodes
}

// EffectiveNestedInstallerType returns the entry's nested installer type,
// falling back to the manifest default.
func (e InstallerEntry) EffectiveNestedInstallerType(m *InstallerManifest) string {
	if e.NestedInstallerType != "" {
		return e.NestedInstallerType
	}
	return m.NestedInstallerType
}

// EffectiveNestedInstallerFiles returns the entry's nested installer files,
// falling back to the manifest default.
func (e InstallerEntry) EffectiveNestedInstallerFiles(m *InstallerManifest) []NestedInstallerFile {
	if len(e.NestedInstallerFiles) > 0 {
		return e.NestedInstallerFiles
	}
	return m.NestedInstallerFiles
}

// EffectiveDependencies returns the entry's dependencies, falling back to the manifest default.
func (e InstallerEntry) EffectiveDependencies(m *InstallerManifest) Dependencies {
	if len(e.Dependencies.PackageDependencies) > 0 || len(e.Dependencies.WindowsFeatures) > 0 {
		return e.Dependencies
	}
	return m.Dependencies
}

// NeedsElevation returns true if the installer requires admin privileges.
func (e InstallerEntry) NeedsElevation(m *InstallerManifest) bool {
	req := e.EffectiveElevationRequirement(m)
	// Explicit elevation requirement
	if req == "elevationRequired" {
		return true
	}
	// elevatesSelf means the installer handles its own UAC prompt
	if req == "elevatesSelf" {
		return false
	}
	// Machine-scope installs need elevation
	if e.EffectiveScope(m) == "machine" {
		return true
	}
	return false
}

// FetchManifest downloads and parses the installer manifest for a package.
func FetchManifest(id, version string) (*InstallerManifest, error) {
	url := buildManifestURL(id, version)
	logging.Info("FetchManifest: GET %s", url)

	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("fetch manifest: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("fetch manifest: HTTP %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read manifest: %w", err)
	}

	return parseManifest(string(body))
}

func buildManifestURL(id, version string) string {
	firstLetter := strings.ToLower(id[:1])
	parts := strings.Split(id, ".")
	pathSegments := strings.Join(parts, "/")
	return fmt.Sprintf("%s/%s/%s/%s/%s.installer.yaml",
		manifestBaseURL, firstLetter, pathSegments, version, id)
}

// parseManifest does line-based YAML parsing of the installer manifest.
// The format is well-defined and consistent across winget-pkgs.
func parseManifest(yaml string) (*InstallerManifest, error) {
	m := &InstallerManifest{}
	lines := strings.Split(yaml, "\n")

	// listMode tracks which YAML list section we're currently inside.
	// Empty string means not in any list section.
	type listMode string
	const (
		listNone              listMode = ""
		listSuccessCodes      listMode = "InstallerSuccessCodes"
		listNestedFiles       listMode = "NestedInstallerFiles"
		listDeps              listMode = "Dependencies"
		listPkgDeps           listMode = "PackageDependencies"
		listWinFeatures       listMode = "WindowsFeatures"
		listSwitches          listMode = "InstallerSwitches"
	)

	inInstallers := false
	currentList := listNone // active list section (top-level or per-entry)
	var current *InstallerEntry

	// isEntryLevel returns true if currentList applies to an installer entry
	isEntryLevel := func() bool { return inInstallers && current != nil }

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}

		// Detect major sections
		if trimmed == "Installers:" {
			inInstallers = true
			currentList = listNone
			continue
		}

		// Detect sub-sections that switch list mode
		switch trimmed {
		case "InstallerSwitches:":
			currentList = listSwitches
			continue
		case "InstallerSuccessCodes:":
			currentList = listSuccessCodes
			continue
		case "NestedInstallerFiles:":
			currentList = listNestedFiles
			continue
		case "Dependencies:":
			currentList = listDeps
			continue
		case "PackageDependencies:":
			if currentList == listDeps {
				currentList = listPkgDeps
			}
			continue
		case "WindowsFeatures:":
			if currentList == listDeps {
				currentList = listWinFeatures
			}
			continue
		}

		// Handle list items (lines starting with "- ")
		if strings.HasPrefix(trimmed, "- ") {
			item := strings.TrimSpace(strings.TrimPrefix(trimmed, "- "))

			// New installer entry in the Installers section
			if inInstallers && strings.HasPrefix(trimmed, "- Architecture:") {
				entry := InstallerEntry{}
				entry.Architecture = strings.TrimSpace(strings.TrimPrefix(trimmed, "- Architecture:"))
				m.Installers = append(m.Installers, entry)
				current = &m.Installers[len(m.Installers)-1]
				currentList = listNone
				continue
			}

			switch currentList {
			case listSuccessCodes:
				if code, err := strconv.Atoi(item); err == nil {
					if isEntryLevel() {
						current.InstallerSuccessCodes = append(current.InstallerSuccessCodes, code)
					} else {
						m.InstallerSuccessCodes = append(m.InstallerSuccessCodes, code)
					}
				}
				continue
			case listNestedFiles:
				// Items can be "- RelativeFilePath: path/to/file" or just "- path"
				if k, v := splitYAML(item); k == "RelativeFilePath" {
					nf := NestedInstallerFile{RelativeFilePath: v}
					if isEntryLevel() {
						current.NestedInstallerFiles = append(current.NestedInstallerFiles, nf)
					} else {
						m.NestedInstallerFiles = append(m.NestedInstallerFiles, nf)
					}
				}
				continue
			case listPkgDeps:
				// "- PackageIdentifier: Some.Package"
				if k, v := splitYAML(item); k == "PackageIdentifier" {
					dep := PackageDependency{PackageIdentifier: v}
					if isEntryLevel() {
						current.Dependencies.PackageDependencies = append(current.Dependencies.PackageDependencies, dep)
					} else {
						m.Dependencies.PackageDependencies = append(m.Dependencies.PackageDependencies, dep)
					}
				}
				continue
			case listWinFeatures:
				if isEntryLevel() {
					current.Dependencies.WindowsFeatures = append(current.Dependencies.WindowsFeatures, item)
				} else {
					m.Dependencies.WindowsFeatures = append(m.Dependencies.WindowsFeatures, item)
				}
				continue
			}
			// Not in a known list — fall through to key:value parsing
		}

		// Non-list key:value lines end any active list section
		// (unless they're indented sub-keys of the current list)
		if currentList != listNone && currentList != listSwitches && !strings.HasPrefix(trimmed, "- ") {
			// Check if this is a sub-key of a list item (e.g., MinimumVersion under PackageDependencies)
			if currentList == listPkgDeps {
				if k, v := splitYAML(trimmed); k == "MinimumVersion" {
					if isEntryLevel() && len(current.Dependencies.PackageDependencies) > 0 {
						current.Dependencies.PackageDependencies[len(current.Dependencies.PackageDependencies)-1].MinimumVersion = v
					} else if len(m.Dependencies.PackageDependencies) > 0 {
						m.Dependencies.PackageDependencies[len(m.Dependencies.PackageDependencies)-1].MinimumVersion = v
					}
					continue
				}
			}
			// Check if this is a sub-key under NestedInstallerFiles item
			if currentList == listNestedFiles {
				if k, v := splitYAML(trimmed); k == "RelativeFilePath" {
					nf := NestedInstallerFile{RelativeFilePath: v}
					if isEntryLevel() {
						current.NestedInstallerFiles = append(current.NestedInstallerFiles, nf)
					} else {
						m.NestedInstallerFiles = append(m.NestedInstallerFiles, nf)
					}
					continue
				}
			}
			currentList = listNone
		}

		// InstallerSwitches sub-keys
		if currentList == listSwitches {
			if k, v := splitYAML(trimmed); k != "" {
				if isEntryLevel() {
					switch k {
					case "Silent":
						current.Silent = v
					case "SilentWithProgress":
						current.SilentProgress = v
					case "Custom":
						current.Custom = v
					}
				} else {
					switch k {
					case "Silent":
						m.Silent = v
					case "SilentWithProgress":
						m.SilentProgress = v
					case "Custom":
						m.Custom = v
					}
				}
			}
			// End switches section on non-indented line
			indent := len(line) - len(strings.TrimLeft(line, " \t"))
			if indent < 2 {
				currentList = listNone
			}
			continue
		}

		// Top-level fields (before Installers:)
		if !inInstallers {
			if k, v := splitYAML(trimmed); k != "" {
				switch k {
				case "PackageIdentifier":
					m.ID = v
				case "PackageVersion":
					m.Version = v
				case "InstallerType":
					m.InstallerType = strings.ToLower(v)
				case "Scope":
					m.Scope = strings.ToLower(v)
				case "ElevationRequirement":
					m.ElevationRequirement = v
				case "NestedInstallerType":
					m.NestedInstallerType = strings.ToLower(v)
				}
			}
			continue
		}

		// Per-entry fields
		if current == nil {
			continue
		}

		if k, v := splitYAML(trimmed); k != "" {
			switch k {
			case "Scope":
				current.Scope = strings.ToLower(v)
			case "InstallerType":
				current.InstallerType = strings.ToLower(v)
			case "InstallerUrl":
				current.InstallerURL = v
			case "InstallerSha256":
				current.SHA256 = strings.ToUpper(v)
			case "InstallerLocale":
				current.Locale = strings.ToLower(v)
			case "ElevationRequirement":
				current.ElevationRequirement = v
			case "NestedInstallerType":
				current.NestedInstallerType = strings.ToLower(v)
			}
		}
	}

	if len(m.Installers) == 0 {
		return nil, fmt.Errorf("no installer entries found in manifest")
	}

	logging.Info("FetchManifest: %s v%s — %d installers, type=%s",
		m.ID, m.Version, len(m.Installers), m.InstallerType)
	return m, nil
}

func splitYAML(line string) (key, value string) {
	idx := strings.Index(line, ":")
	if idx < 0 {
		return "", ""
	}
	return strings.TrimSpace(line[:idx]), strings.TrimSpace(line[idx+1:])
}

// SelectInstaller picks the best installer entry for the current system.
// Priority: matching arch → prefer user scope → prefer exe-based types over zip/msix.
func SelectInstaller(m *InstallerManifest) (*InstallerEntry, error) {
	winArch := goArchToWinArch(runtime.GOARCH)

	// Filter to matching architecture, fall back to x86 if no x64 match
	var candidates []InstallerEntry
	for _, e := range m.Installers {
		if strings.EqualFold(e.Architecture, winArch) {
			candidates = append(candidates, e)
		}
	}
	if len(candidates) == 0 && winArch == "x64" {
		// Many packages only ship x86 installers that work on x64
		for _, e := range m.Installers {
			if strings.EqualFold(e.Architecture, "x86") {
				candidates = append(candidates, e)
			}
		}
	}
	if len(candidates) == 0 {
		return nil, fmt.Errorf("no installer for architecture %s", winArch)
	}

	// Filter out msix (needs deployment API) and zip/portable (complex)
	var preferred []InstallerEntry
	for _, e := range candidates {
		t := e.EffectiveType(m)
		if t == "msix" || t == "appx" || t == "zip" || t == "portable" {
			continue
		}
		preferred = append(preferred, e)
	}
	if len(preferred) == 0 {
		// Fall back to all candidates except msix
		for _, e := range candidates {
			t := e.EffectiveType(m)
			if t != "msix" && t != "appx" {
				preferred = append(preferred, e)
			}
		}
	}
	if len(preferred) == 0 {
		preferred = candidates // last resort: use anything
	}

	// Filter by locale: prefer no-locale or en-US
	var localeFiltered []InstallerEntry
	for _, e := range preferred {
		if e.Locale == "" || e.Locale == "en-us" {
			localeFiltered = append(localeFiltered, e)
		}
	}
	if len(localeFiltered) > 0 {
		preferred = localeFiltered
	}

	// Prefer "user" scope, then no-scope, then "machine"
	for _, e := range preferred {
		if e.Scope == "user" {
			return &e, nil
		}
	}
	for _, e := range preferred {
		if e.Scope == "" {
			return &e, nil
		}
	}
	return &preferred[0], nil
}

// SilentArgs returns the silent install arguments for the given installer type.
// Checks per-entry overrides first, then manifest-level, then well-known defaults.
func SilentArgs(m *InstallerManifest, e *InstallerEntry) string {
	// Per-entry switches take highest priority
	if e.Silent != "" {
		args := e.Silent
		if e.Custom != "" {
			args += " " + e.Custom
		}
		return args
	}

	// Then manifest-level switches
	if m.Silent != "" {
		args := m.Silent
		if m.Custom != "" {
			args += " " + m.Custom
		}
		return args
	}

	// Fall back to well-known defaults per installer type
	t := e.EffectiveType(m)
	switch t {
	case "inno":
		return "/SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART"
	case "nullsoft":
		return "/S"
	case "msi", "wix":
		return "/quiet /norestart"
	case "burn":
		return "/quiet /norestart"
	case "exe":
		// EXE installers have no standard — use manifest switches or nothing
		if e.SilentProgress != "" {
			return e.SilentProgress
		}
		if m.SilentProgress != "" {
			return m.SilentProgress
		}
		return ""
	default:
		return ""
	}
}

func goArchToWinArch(goArch string) string {
	switch goArch {
	case "amd64":
		return "x64"
	case "386":
		return "x86"
	case "arm64":
		return "arm64"
	default:
		return goArch
	}
}
