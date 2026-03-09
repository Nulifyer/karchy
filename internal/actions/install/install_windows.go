//go:build windows

package install

import (
	"database/sql"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
	"golang.org/x/sys/windows/registry"
	_ "modernc.org/sqlite"
)

// SearchPackages returns all available packages by reading the winget SQLite index directly.
// Falls back to winget CLI table parsing if the DB is unavailable.
func SearchPackages() []PackageEntry {
	dbPath := findSourceIndex()
	if dbPath != "" {
		entries := querySourceIndex(dbPath)
		if entries != nil {
			logging.Info("SearchPackages: %d packages via SQLite", len(entries))
			return entries
		}
	}
	logging.Info("SearchPackages: SQLite unavailable, falling back to CLI")
	return searchPackagesCLI()
}

// InstalledIDs returns a set of installed package IDs.
// Uses ARP registry as the source of truth — matches ARP entries against
// winget's source index product codes to map them to package IDs.
func InstalledIDs() map[string]string {
	if srcPath := findSourceIndex(); srcPath != "" {
		ids := matchARPInstalled(srcPath)
		if len(ids) > 0 {
			logging.Info("InstalledIDs: %d installed via ARP", len(ids))
			return ids
		}
	}

	logging.Info("InstalledIDs: source index unavailable, falling back to CLI")
	return installedIDsCLI()
}

// --- SQLite paths ---

// findSourceIndex locates the winget source index.db via the Appx package registry.
// The WindowsApps directory blocks directory listing, but files are readable with an exact path.
func findSourceIndex() string {
	const keyPath = `Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages`
	key, err := registry.OpenKey(registry.CURRENT_USER, keyPath, registry.ENUMERATE_SUB_KEYS)
	if err != nil {
		logging.Info("findSourceIndex: open registry key failed: %v", err)
		return ""
	}
	defer key.Close()

	names, err := key.ReadSubKeyNames(-1)
	if err != nil {
		logging.Info("findSourceIndex: enumerate subkeys failed: %v", err)
		return ""
	}

	// Find the latest Microsoft.Winget.Source_* subkey
	var best string
	for _, name := range names {
		if strings.HasPrefix(name, "Microsoft.Winget.Source_") {
			if name > best {
				best = name
			}
		}
	}
	if best == "" {
		logging.Info("findSourceIndex: no Microsoft.Winget.Source package found in registry")
		return ""
	}

	sub, err := registry.OpenKey(registry.CURRENT_USER, keyPath+`\`+best, registry.QUERY_VALUE)
	if err != nil {
		logging.Info("findSourceIndex: open subkey %s failed: %v", best, err)
		return ""
	}
	defer sub.Close()

	root, _, err := sub.GetStringValue("PackageRootFolder")
	if err != nil {
		logging.Info("findSourceIndex: read PackageRootFolder failed: %v", err)
		return ""
	}

	path := filepath.Join(root, "Public", "index.db")
	if _, err := os.Stat(path); err != nil {
		logging.Info("findSourceIndex: %v", err)
		return ""
	}
	logging.Info("findSourceIndex: %s", path)
	return path
}

// --- SQLite queries ---

func querySourceIndex(dbPath string) []PackageEntry {
	db, err := sql.Open("sqlite", dbPath+"?mode=ro")
	if err != nil {
		logging.Info("querySourceIndex: open failed: %v", err)
		return nil
	}
	defer db.Close()

	rows, err := db.Query("SELECT id, name, latest_version FROM packages ORDER BY name")
	if err != nil {
		logging.Info("querySourceIndex: query failed: %v", err)
		return nil
	}
	defer rows.Close()

	var entries []PackageEntry
	for rows.Next() {
		var e PackageEntry
		if err := rows.Scan(&e.ID, &e.Name, &e.Version); err != nil {
			continue
		}
		if e.ID == "" {
			continue
		}
		entries = append(entries, e)
	}
	return entries
}

// matchARPInstalled reads ARP (Add/Remove Programs) registry keys and matches
// them against productcodes2 in the source index to detect programs installed
// outside of winget (e.g. via their own installer).
func matchARPInstalled(sourceDBPath string) map[string]string {
	// Build product code -> package ID map from source index
	db, err := sql.Open("sqlite", sourceDBPath+"?mode=ro")
	if err != nil {
		logging.Info("matchARPInstalled: open failed: %v", err)
		return nil
	}
	defer db.Close()

	rows, err := db.Query("SELECT pc.productcode, p.id FROM productcodes2 pc JOIN packages p ON p.rowid = pc.package")
	if err != nil {
		logging.Info("matchARPInstalled: query failed: %v", err)
		return nil
	}
	defer rows.Close()

	// Map lowercase product code -> package ID
	pcToID := make(map[string]string)
	for rows.Next() {
		var pc, id string
		if err := rows.Scan(&pc, &id); err != nil {
			continue
		}
		pcToID[strings.ToLower(pc)] = id
	}
	logging.Info("matchARPInstalled: %d product codes in index", len(pcToID))

	// Scan ARP registry keys
	arpPaths := []struct {
		root registry.Key
		path string
	}{
		{registry.LOCAL_MACHINE, `SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`},
		{registry.LOCAL_MACHINE, `SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall`},
		{registry.CURRENT_USER, `SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`},
	}

	ids := make(map[string]string)
	for _, arp := range arpPaths {
		key, err := registry.OpenKey(arp.root, arp.path, registry.ENUMERATE_SUB_KEYS)
		if err != nil {
			continue
		}
		subkeys, err := key.ReadSubKeyNames(-1)
		key.Close()
		if err != nil {
			continue
		}
		for _, sk := range subkeys {
			if id, ok := pcToID[strings.ToLower(sk)]; ok {
				// Read DisplayVersion from the ARP entry
				ver := readARPVersion(arp.root, arp.path+`\`+sk)
				ids[id] = ver
			}
		}
	}
	logging.Info("matchARPInstalled: %d ARP matches", len(ids))
	return ids
}

func readARPVersion(root registry.Key, path string) string {
	key, err := registry.OpenKey(root, path, registry.QUERY_VALUE)
	if err != nil {
		return ""
	}
	defer key.Close()
	ver, _, err := key.GetStringValue("DisplayVersion")
	if err != nil {
		return ""
	}
	return ver
}


// --- CLI fallbacks ---

func searchPackagesCLI() []PackageEntry {
	out, err := exec.Command("winget", "search",
		"-q", ".",
		"--disable-interactivity",
		"--accept-source-agreements",
	).Output()
	if err != nil {
		logging.Info("searchPackagesCLI: winget search failed: %v", err)
		return nil
	}
	return parseWingetTable(string(out))
}

func installedIDsCLI() map[string]string {
	out, err := exec.Command("winget", "list",
		"--disable-interactivity",
		"--accept-source-agreements",
	).Output()
	if err != nil {
		logging.Info("installedIDsCLI: winget list failed: %v", err)
		return nil
	}

	entries := parseWingetTable(string(out))
	ids := make(map[string]string, len(entries))
	for _, e := range entries {
		ids[e.ID] = e.Version
	}
	logging.Info("installedIDsCLI: %d installed", len(ids))
	return ids
}

// --- winget table parser (fallback) ---

func parseWingetTable(output string) []PackageEntry {
	lines := strings.Split(output, "\n")

	sepIdx := -1
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if len(trimmed) > 10 && strings.Count(trimmed, "-") == len(trimmed) {
			sepIdx = i
			break
		}
	}
	if sepIdx < 1 || sepIdx+1 >= len(lines) {
		return nil
	}

	header := lines[sepIdx-1]
	idCol := strings.Index(header, "Id")
	versionCol := strings.Index(header, "Version")
	if idCol < 0 {
		return nil
	}

	var entries []PackageEntry
	for _, line := range lines[sepIdx+1:] {
		if len(strings.TrimSpace(line)) == 0 {
			continue
		}

		name := safeSlice(line, 0, idCol)
		var id, version string
		if versionCol > 0 {
			id = safeSlice(line, idCol, versionCol)
			version = safeSlice(line, versionCol, len(line))
		} else {
			id = safeSlice(line, idCol, len(line))
		}

		name = strings.TrimSpace(name)
		id = strings.TrimSpace(id)
		version = strings.TrimSpace(version)

		if id == "" {
			continue
		}

		if sp := strings.IndexByte(version, ' '); sp > 0 {
			version = version[:sp]
		}

		entries = append(entries, PackageEntry{
			Name:    name,
			ID:      id,
			Version: version,
		})
	}

	logging.Info("parseWingetTable: parsed %d packages", len(entries))
	return entries
}

func safeSlice(s string, start, end int) string {
	if start >= len(s) {
		return ""
	}
	if end > len(s) {
		end = len(s)
	}
	return s[start:end]
}

// InstallPackage spawns a new terminal window running winget install for the given package ID.
func InstallPackage(pkg PackageEntry) {
	logging.Info("InstallPackage: %s (%s)", pkg.Name, pkg.ID)
	script := `winget install -e --id ` + pkg.ID + ` --accept-source-agreements --accept-package-agreements & pause`
	terminal.LaunchShell(80, 20, "Installing "+pkg.Name, script)
}

// InstallPackages spawns a single terminal window running winget install for all given packages.
func InstallPackages(pkgs []PackageEntry) {
	if len(pkgs) == 0 {
		return
	}
	if len(pkgs) == 1 {
		InstallPackage(pkgs[0])
		return
	}

	var cmds []string
	var names []string
	for _, p := range pkgs {
		cmds = append(cmds, "winget install -e --id "+p.ID+" --accept-source-agreements --accept-package-agreements")
		names = append(names, p.Name)
	}
	logging.Info("InstallPackages: %d packages: %v", len(pkgs), names)

	script := strings.Join(cmds, " && ") + " & pause"
	terminal.LaunchShell(100, 30, fmt.Sprintf("Installing %d packages", len(pkgs)), script)
}
