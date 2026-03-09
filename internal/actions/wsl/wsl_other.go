//go:build !windows

package wsl

// Distro represents a WSL distribution.
type Distro struct {
	Name string
}

func ListInstalled() []Distro { return nil }
func ListOnline() []Distro   { return nil }
func Launch(d Distro)         {}
func Install(distros []Distro) {}
func Remove(distros []Distro) {}
func Shutdown()                {}
func Enable()                  {}
