//go:build windows

package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/nulifyer/karchy/internal/actions/install"
	"github.com/nulifyer/karchy/internal/logging"
)

func main() {
	logging.Init(true)

	// Parse args: package names/IDs separated by commas or spaces
	// --install to actually install, --verify to download+verify only, otherwise dry run
	mode := "dry"
	var searches []string
	for _, arg := range os.Args[1:] {
		switch arg {
		case "--install":
			mode = "install"
		case "--verify":
			mode = "verify"
		default:
			searches = append(searches, arg)
		}
	}
	if len(searches) == 0 {
		searches = []string{"Bruno"}
	}

	// Load package index
	packages := install.SearchPackages()
	if len(packages) == 0 {
		fmt.Println("No packages found in index")
		os.Exit(1)
	}

	// Find matching packages
	var matched []install.PackageEntry
	for _, search := range searches {
		searchLower := strings.ToLower(search)
		var found *install.PackageEntry

		// Exact match first
		for _, p := range packages {
			if strings.EqualFold(p.ID, search) || strings.EqualFold(p.Name, search) {
				found = &p
				break
			}
		}
		// Fuzzy match
		if found == nil {
			for _, p := range packages {
				if strings.Contains(strings.ToLower(p.ID), searchLower) ||
					strings.Contains(strings.ToLower(p.Name), searchLower) {
					found = &p
					break
				}
			}
		}

		if found == nil {
			fmt.Printf("Package %q not found\n", search)
		} else {
			matched = append(matched, *found)
		}
	}

	if len(matched) == 0 {
		fmt.Println("No packages matched")
		os.Exit(1)
	}

	// Check installed versions
	installed := install.InstalledIDs()

	fmt.Printf("Matched %d package(s):\n", len(matched))
	for _, p := range matched {
		if ver, ok := installed[p.ID]; ok {
			latest := install.ParseSemVer(p.Version)
			current := install.ParseSemVer(ver)
			if latest.IsNewerThan(current) {
				fmt.Printf("  %s (%s)  [installed: %s → %s]\n", p.Name, p.ID, ver, p.Version)
			} else {
				fmt.Printf("  %s (%s) v%s  [installed: %s ✓]\n", p.Name, p.ID, p.Version, ver)
			}
		} else {
			fmt.Printf("  %s (%s) v%s  [not installed]\n", p.Name, p.ID, p.Version)
		}
	}

	switch mode {
	case "dry":
		for _, pkg := range matched {
			manifest, err := install.FetchManifest(pkg.ID, pkg.Version)
			if err != nil {
				fmt.Printf("\n%s: manifest error: %v\n", pkg.Name, err)
				continue
			}
			entry, err := install.SelectInstaller(manifest)
			if err != nil {
				fmt.Printf("\n%s: select error: %v\n", pkg.Name, err)
				continue
			}
			fmt.Printf("\n%s:\n", pkg.Name)
			fmt.Printf("  Type:  %s %s\n", entry.EffectiveType(manifest), entry.Architecture)
			fmt.Printf("  URL:   %s\n", entry.InstallerURL)
			fmt.Printf("  Args:  %q\n", install.SilentArgs(manifest, entry))
		}
		fmt.Println("\n(dry run — pass --install or --verify)")

	case "verify":
		install.BatchVerify(matched)

	case "install":
		install.BatchInstall(matched)
	}
}
