//go:build linux

package install

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/nulifyer/karchy/internal/ansi"
	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
)

// SearchPackages returns all available packages from pacman sync databases.
func SearchPackages() []PackageEntry {
	out, err := exec.Command("pacman", "-Sl").Output()
	if err != nil {
		logging.Info("SearchPackages: pacman -Sl failed: %v", err)
		return nil
	}

	var entries []PackageEntry
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		// Format: repo package version [installed]
		fields := strings.Fields(scanner.Text())
		if len(fields) < 3 {
			continue
		}
		entries = append(entries, PackageEntry{
			Name:    fields[1],
			ID:      fields[1],
			Version: fields[2],
		})
	}

	logging.Info("SearchPackages: %d packages from pacman", len(entries))
	return entries
}

// InstalledIDs returns installed package names mapped to their version.
func InstalledIDs() map[string]string {
	out, err := exec.Command("pacman", "-Q").Output()
	if err != nil {
		logging.Info("InstalledIDs: pacman -Q failed: %v", err)
		return nil
	}

	ids := make(map[string]string)
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) >= 2 {
			ids[fields[0]] = fields[1]
		}
	}

	logging.Info("InstalledIDs: %d installed", len(ids))
	return ids
}

// shellQuote returns a single-quoted shell-safe string.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\"'\"'") + "'"
}

// InstallPackage installs a single package in a new terminal window.
func InstallPackage(pkg PackageEntry) {
	logging.Info("InstallPackage: %s", pkg.ID)
	script := fmt.Sprintf("sudo pacman -S --noconfirm %s; echo; read -rp 'Press Enter to close...'", shellQuote(pkg.ID))
	terminal.LaunchShell(80, 20, "Installing "+pkg.Name, script)
}

// BatchInstall installs multiple packages with confirmation.
func BatchInstall(pkgs []PackageEntry) {
	if len(pkgs) == 0 {
		return
	}
	if len(pkgs) == 1 {
		InstallPackage(pkgs[0])
		return
	}

	ids := make([]string, len(pkgs))
	for i, p := range pkgs {
		ids[i] = p.ID
	}
	logging.Info("BatchInstall: %d packages: %v", len(pkgs), ids)

	quoted := make([]string, len(ids))
	for i, id := range ids {
		quoted[i] = shellQuote(id)
	}
	script := fmt.Sprintf("sudo pacman -S %s; echo; read -rp 'Press Enter to close...'", strings.Join(quoted, " "))
	terminal.LaunchShell(100, 30, fmt.Sprintf("Installing %d packages", len(pkgs)), script)
}

// AURHelper returns the AUR helper command ("paru" or "yay"), or empty if none found.
func AURHelper() string {
	if _, err := exec.LookPath("paru"); err == nil {
		return "paru"
	}
	if _, err := exec.LookPath("yay"); err == nil {
		return "yay"
	}
	return ""
}

// HasAUR returns true if an AUR helper (paru or yay) is installed.
func HasAUR() bool {
	return AURHelper() != ""
}

// SearchAUR returns all available AUR packages via the installed helper.
func SearchAUR() []PackageEntry {
	helper := AURHelper()
	if helper == "" {
		return nil
	}
	// paru/yay -Sl aur: lists all AUR packages (name version)
	out, err := exec.Command(helper, "-Sl", "aur").Output()
	if err != nil {
		logging.Info("SearchAUR: %s -Sl aur failed: %v", helper, err)
		return nil
	}

	var entries []PackageEntry
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		// Format: "aur pkgname version [installed]" or "pkgname version"
		fields := strings.Fields(scanner.Text())
		if len(fields) < 2 {
			continue
		}
		// Skip the repo name if present
		name, version := fields[0], fields[1]
		if len(fields) >= 3 && (fields[0] == "aur") {
			name, version = fields[1], fields[2]
		}
		entries = append(entries, PackageEntry{
			Name:    name,
			ID:      name,
			Version: version,
		})
	}
	logging.Info("SearchAUR: %d AUR packages", len(entries))
	return entries
}

// AURInstalledIDs returns installed AUR (foreign) package names mapped to versions.
func AURInstalledIDs() map[string]string {
	helper := AURHelper()
	if helper == "" {
		return nil
	}
	out, err := exec.Command(helper, "-Qm").Output()
	if err != nil {
		return nil
	}
	ids := make(map[string]string)
	sc := bufio.NewScanner(strings.NewReader(string(out)))
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) >= 2 {
			ids[fields[0]] = fields[1]
		}
	}
	return ids
}

// AURInstall installs AUR packages via the installed helper.
func AURInstall(pkgs []PackageEntry) {
	helper := AURHelper()
	if helper == "" || len(pkgs) == 0 {
		return
	}
	ids := make([]string, len(pkgs))
	for i, p := range pkgs {
		ids[i] = p.ID
	}
	flags := "--needed"
	switch helper {
	case "paru":
		flags += " --skipreview --cleanafter"
	case "yay":
		flags += " --answerdiff None --answerclean None --answeredit None --cleanafter"
	}
	quoted := make([]string, len(ids))
	for i, id := range ids {
		quoted[i] = shellQuote(id)
	}
	script := fmt.Sprintf("%s -S %s %s; echo; read -rp 'Press Enter to close...'", helper, flags, strings.Join(quoted, " "))
	terminal.LaunchShell(100, 30, fmt.Sprintf("AUR Install (%d)", len(pkgs)), script)
}

// AURSearch searches AUR for packages matching a query term.
func AURSearch(query string) []PackageEntry {
	helper := AURHelper()
	if helper == "" {
		return nil
	}
	out, err := exec.Command(helper, "-Ss", query).Output()
	if err != nil {
		logging.Info("AURSearch: %s -Ss failed: %v", helper, err)
		return nil
	}

	var entries []PackageEntry
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	for i := 0; i < len(lines); i += 2 {
		// Format: repo/name version [installed]
		//         Description text
		fields := strings.Fields(lines[i])
		if len(fields) < 2 {
			continue
		}
		nameParts := strings.SplitN(fields[0], "/", 2)
		name := fields[0]
		if len(nameParts) == 2 {
			name = nameParts[1]
		}
		version := fields[1]
		entries = append(entries, PackageEntry{
			Name:    name,
			ID:      name,
			Version: version,
		})
	}
	logging.Info("AURSearch: %d results for %q", len(entries), query)
	return entries
}

// DirectInstall installs a single package via pacman.
func DirectInstall(pkg PackageEntry) error {
	cmd := exec.Command("sudo", "pacman", "-S", "--noconfirm", pkg.ID)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// BatchVerify checks if packages are available in sync databases.
func BatchVerify(pkgs []PackageEntry) {
	fmt.Printf("\n %s%s:: Verifying packages...%s\n\n", ansi.Bold, ansi.Cyan, ansi.Reset)
	for i, p := range pkgs {
		err := exec.Command("pacman", "-Si", p.ID).Run()
		if err != nil {
			fmt.Printf(" [%d/%d] %s — %snot found%s\n", i+1, len(pkgs), p.Name, ansi.Red, ansi.Reset)
		} else {
			fmt.Printf(" [%d/%d] %s — %sok%s\n", i+1, len(pkgs), p.Name, ansi.Green, ansi.Reset)
		}
	}
}

// InstalledPackage represents a package that can be uninstalled.
type InstalledPackage struct {
	Name    string
	ID      string
	Version string
}

// InstalledPackages returns all explicitly installed packages.
func InstalledPackages() []InstalledPackage {
	out, err := exec.Command("pacman", "-Qe").Output()
	if err != nil {
		logging.Info("InstalledPackages: pacman -Qe failed: %v", err)
		return nil
	}

	var pkgs []InstalledPackage
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 2 {
			continue
		}
		pkgs = append(pkgs, InstalledPackage{
			Name:    fields[0],
			ID:      fields[0],
			Version: fields[1],
		})
	}

	logging.Info("InstalledPackages: %d explicitly installed", len(pkgs))
	return pkgs
}

// UninstallPackage removes a single package.
func UninstallPackage(pkg InstalledPackage) error {
	cmd := exec.Command("sudo", "pacman", "-Rs", "--noconfirm", pkg.ID)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

// BatchUninstall removes multiple packages with confirmation.
func BatchUninstall(pkgs []InstalledPackage) {
	if len(pkgs) == 0 {
		return
	}

	// List packages and confirm
	fmt.Printf("\n Packages (%d)\n\n", len(pkgs))
	for _, pkg := range pkgs {
		if pkg.Version != "" {
			fmt.Printf(" %s  %s%s%s\n", pkg.Name, ansi.Green, pkg.Version, ansi.Reset)
		} else {
			fmt.Printf(" %s\n", pkg.Name)
		}
	}

	fmt.Printf("\n %s%s:: Proceed with removal? [Y/n]%s ", ansi.Bold, ansi.Cyan, ansi.Reset)
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	if len(line) > 0 && (line[0] == 'n' || line[0] == 'N') {
		return
	}

	ids := make([]string, len(pkgs))
	for i, p := range pkgs {
		ids[i] = p.ID
	}

	fmt.Printf("\n %s%s:: Removing packages...%s\n\n", ansi.Bold, ansi.Cyan, ansi.Reset)

	cmd := exec.Command("sudo", append([]string{"pacman", "-Rs", "--noconfirm"}, ids...)...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()

	fmt.Println()
	if err != nil {
		fmt.Printf(" %s%s:: Some packages failed to remove: %v%s\n\n", ansi.Bold, ansi.Red, err, ansi.Reset)
	} else {
		fmt.Printf(" %s%s:: %d package(s) removed successfully.%s\n\n", ansi.Bold, ansi.Green, len(pkgs), ansi.Reset)
	}

	fmt.Print(" Press Enter to close...")
	bufio.NewReader(os.Stdin).ReadBytes('\n')
}
