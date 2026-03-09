//go:build !windows && !linux

package install

// SearchPackages returns available packages from the system package manager.
func SearchPackages() []PackageEntry {
	// TODO: pacman -Slq / brew formulae
	return nil
}

// InstalledIDs returns installed package IDs mapped to their installed version.
func InstalledIDs() map[string]string {
	// TODO: pacman -Qq / brew list
	return nil
}

// InstallPackage installs a package using the system package manager.
func InstallPackage(pkg PackageEntry) {
	// TODO: sudo pacman -S / brew install
}

// BatchInstall installs multiple packages with progress display.
func BatchInstall(pkgs []PackageEntry) {
	// TODO: pacman -S / brew install
}

// DirectInstall installs a single package directly.
func DirectInstall(pkg PackageEntry) error {
	// TODO
	return nil
}

// BatchVerify downloads and verifies packages without installing.
func BatchVerify(pkgs []PackageEntry) {
	// TODO
}

// InstalledPackage represents a package that can be uninstalled.
type InstalledPackage struct {
	Name    string
	ID      string
	Version string
}

// InstalledPackages returns all removable packages.
func InstalledPackages() []InstalledPackage {
	// TODO: pacman -Qq / brew list
	return nil
}

// UninstallPackage removes a single package.
func UninstallPackage(pkg InstalledPackage) error {
	// TODO
	return nil
}

// BatchUninstall removes multiple packages.
func BatchUninstall(pkgs []InstalledPackage) {
	// TODO
}

