//go:build linux

package install

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/nulifyer/karchy/internal/logging"
	"github.com/nulifyer/karchy/internal/terminal"
)

const (
	colorGreen = "\033[32m"
	colorRed   = "\033[31m"
	colorCyan  = "\033[36m"
	colorBold  = "\033[1m"
	colorReset = "\033[0m"
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

// InstallPackage installs a single package in a new terminal window.
func InstallPackage(pkg PackageEntry) {
	logging.Info("InstallPackage: %s", pkg.ID)
	script := fmt.Sprintf("sudo pacman -S --noconfirm %s; echo; read -rp 'Press Enter to close...'", pkg.ID)
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

	script := fmt.Sprintf("sudo pacman -S %s; echo; read -rp 'Press Enter to close...'", strings.Join(ids, " "))
	terminal.LaunchShell(100, 30, fmt.Sprintf("Installing %d packages", len(pkgs)), script)
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
	fmt.Printf("\n %s%s:: Verifying packages...%s\n\n", colorBold, colorCyan, colorReset)
	for i, p := range pkgs {
		err := exec.Command("pacman", "-Si", p.ID).Run()
		if err != nil {
			fmt.Printf(" [%d/%d] %s — %snot found%s\n", i+1, len(pkgs), p.Name, colorRed, colorReset)
		} else {
			fmt.Printf(" [%d/%d] %s — %sok%s\n", i+1, len(pkgs), p.Name, colorGreen, colorReset)
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
			fmt.Printf(" %s  %s%s%s\n", pkg.Name, colorGreen, pkg.Version, colorReset)
		} else {
			fmt.Printf(" %s\n", pkg.Name)
		}
	}

	fmt.Printf("\n %s%s:: Proceed with removal? [Y/n]%s ", colorBold, colorCyan, colorReset)
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	if len(line) > 0 && (line[0] == 'n' || line[0] == 'N') {
		return
	}

	ids := make([]string, len(pkgs))
	for i, p := range pkgs {
		ids[i] = p.ID
	}

	fmt.Printf("\n %s%s:: Removing packages...%s\n\n", colorBold, colorCyan, colorReset)

	cmd := exec.Command("sudo", append([]string{"pacman", "-Rs", "--noconfirm"}, ids...)...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()

	fmt.Println()
	if err != nil {
		fmt.Printf(" %s%s:: Some packages failed to remove: %v%s\n\n", colorBold, colorRed, err, colorReset)
	} else {
		fmt.Printf(" %s%s:: %d package(s) removed successfully.%s\n\n", colorBold, colorGreen, len(pkgs), colorReset)
	}

	fmt.Print(" Press Enter to close...")
	bufio.NewReader(os.Stdin).ReadBytes('\n')
}
