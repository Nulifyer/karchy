package install

// PackageEntry represents a package from a package manager.
type PackageEntry struct {
	Name    string // Human-readable name
	ID      string // Package identifier (e.g. winget ID, pacman package name)
	Version string // Latest available version
}
