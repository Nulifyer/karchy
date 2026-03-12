package install

import (
	"fmt"
	"io"
	"net/http"
	"runtime"
	"strings"

	"github.com/nulifyer/karchy/internal/logging"
)

const manifestBaseURL = "https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests"

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

	inInstallers := false
	inSwitches := false       // top-level InstallerSwitches
	inEntrySwitches := false  // per-entry InstallerSwitches
	var current *InstallerEntry

	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}

		// Detect sections
		if trimmed == "Installers:" {
			inInstallers = true
			inSwitches = false
			continue
		}
		if trimmed == "InstallerSwitches:" {
			if inInstallers && current != nil {
				inEntrySwitches = true
			} else if !inInstallers {
				inSwitches = true
			}
			continue
		}

		// Top-level fields (before Installers:)
		if !inInstallers {
			if inSwitches {
				if k, v := splitYAML(trimmed); k != "" {
					switch k {
					case "Silent":
						m.Silent = v
					case "SilentWithProgress":
						m.SilentProgress = v
					case "Custom":
						m.Custom = v
					}
				}
				// End switches section on non-indented line
				if !strings.HasPrefix(line, "  ") && !strings.HasPrefix(line, "\t") {
					inSwitches = false
				}
			}
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
				}
			}
			continue
		}

		// Inside Installers: section
		if strings.HasPrefix(trimmed, "- Architecture:") {
			// New installer entry
			entry := InstallerEntry{}
			entry.Architecture = strings.TrimSpace(strings.TrimPrefix(trimmed, "- Architecture:"))
			m.Installers = append(m.Installers, entry)
			current = &m.Installers[len(m.Installers)-1]
			inEntrySwitches = false
			continue
		}

		if current == nil {
			continue
		}

		// Per-entry InstallerSwitches
		if inEntrySwitches {
			if k, v := splitYAML(trimmed); k != "" {
				switch k {
				case "Silent":
					current.Silent = v
				case "SilentWithProgress":
					current.SilentProgress = v
				case "Custom":
					current.Custom = v
				}
			}
			// End entry switches on a line that isn't deeply indented
			// (entry switches are typically indented 6+ spaces)
			if !strings.HasPrefix(line, "      ") && !strings.HasPrefix(line, "\t\t\t") {
				inEntrySwitches = false
			} else {
				continue
			}
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
