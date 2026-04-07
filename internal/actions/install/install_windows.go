//go:build windows

package install

import (
	"database/sql"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/nulifyer/karchy/internal/logging"
	"golang.org/x/sys/windows/registry"
	_ "modernc.org/sqlite"
)

// SearchPackages returns all available packages by reading the winget SQLite index directly.
func SearchPackages() []PackageEntry {
	dbPath := findSourceIndex()
	if dbPath != "" {
		entries := querySourceIndex(dbPath)
		if entries != nil {
			logging.Info("SearchPackages: %d packages via SQLite", len(entries))
			return entries
		}
	}
	logging.Info("SearchPackages: source index unavailable")
	return nil
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

	logging.Info("InstalledIDs: source index unavailable")
	return nil
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

	pcToID := make(map[string]string)
	for rows.Next() {
		var pc, id string
		if err := rows.Scan(&pc, &id); err != nil {
			continue
		}
		pcToID[strings.ToLower(pc)] = id
	}
	logging.Info("matchARPInstalled: %d product codes in index", len(pcToID))

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

func sourceIndexLastUpdated() time.Time {
	dbPath := findSourceIndex()
	if dbPath == "" {
		return time.Time{}
	}

	db, err := sql.Open("sqlite", dbPath+"?mode=ro")
	if err != nil {
		logging.Info("sourceIndexLastUpdated: open failed: %v", err)
		return time.Time{}
	}
	defer db.Close()

	var raw string
	if err := db.QueryRow("SELECT value FROM metadata WHERE name = 'lastwritetime'").Scan(&raw); err != nil {
		logging.Info("sourceIndexLastUpdated: query failed: %v", err)
		return time.Time{}
	}

	sec, err := strconv.ParseInt(raw, 10, 64)
	if err != nil {
		logging.Info("sourceIndexLastUpdated: parse failed: %v", err)
		return time.Time{}
	}

	return time.Unix(sec, 0)
}

// InstallPackage installs a package via Karchy's native batch pipeline.
func InstallPackage(pkg PackageEntry) {
	logging.Info("InstallPackage: %s (%s)", pkg.Name, pkg.ID)
	batchPipeline([]PackageEntry{pkg}, true)
}

// InstallPackages installs packages via Karchy's native batch pipeline.
func InstallPackages(pkgs []PackageEntry) {
	if len(pkgs) == 0 {
		return
	}
	batchPipeline(pkgs, true)
}

func HasAUR() bool                          { return false }
func AURHelper() string                     { return "" }
func SearchAUR() []PackageEntry             { return nil }
func AURInstalledIDs() map[string]string    { return nil }
func AURInstall(pkgs []PackageEntry)        {}
func AURSearch(query string) []PackageEntry { return nil }
