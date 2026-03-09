package install

import (
	"strconv"
	"strings"
)

// SemVer represents a parsed semantic version.
type SemVer struct {
	Major      int
	Minor      int
	Patch      int
	Revision   int    // 4th segment (e.g. 1.2.3.4)
	PreRelease string // e.g. "beta.1", "rc.2"
	Raw        string
}

// ParseSemVer parses a version string into a SemVer.
func ParseSemVer(s string) SemVer {
	raw := s

	// Strip build metadata (after '+'), ignored for precedence
	if idx := strings.IndexByte(s, '+'); idx != -1 {
		s = s[:idx]
	}
	// Extract pre-release (after '-')
	pre := ""
	if idx := strings.IndexByte(s, '-'); idx != -1 {
		pre = s[idx+1:]
		s = s[:idx]
	}

	parts := strings.Split(s, ".")
	intAt := func(i int) int {
		if i >= len(parts) {
			return 0
		}
		n, _ := strconv.Atoi(parts[i])
		return n
	}
	return SemVer{
		Major:      intAt(0),
		Minor:      intAt(1),
		Patch:      intAt(2),
		Revision:   intAt(3),
		PreRelease: pre,
		Raw:        raw,
	}
}

// IsNewerThan returns true if v is strictly newer than other.
func (v SemVer) IsNewerThan(other SemVer) bool {
	if v.Major != other.Major {
		return v.Major > other.Major
	}
	if v.Minor != other.Minor {
		return v.Minor > other.Minor
	}
	if v.Patch != other.Patch {
		return v.Patch > other.Patch
	}
	if v.Revision != other.Revision {
		return v.Revision > other.Revision
	}
	// Stable > pre-release
	if v.PreRelease == "" && other.PreRelease != "" {
		return true
	}
	if v.PreRelease != "" && other.PreRelease == "" {
		return false
	}
	return comparePreRelease(v.PreRelease, other.PreRelease) > 0
}

// Equal returns true if v and other represent the same version (ignoring build metadata).
func (v SemVer) Equal(other SemVer) bool {
	return v.Major == other.Major &&
		v.Minor == other.Minor &&
		v.Patch == other.Patch &&
		v.Revision == other.Revision &&
		v.PreRelease == other.PreRelease
}

func comparePreRelease(a, b string) int {
	if a == b {
		return 0
	}
	ap := strings.Split(a, ".")
	bp := strings.Split(b, ".")
	n := len(ap)
	if len(bp) < n {
		n = len(bp)
	}
	for i := 0; i < n; i++ {
		ai, aErr := strconv.Atoi(ap[i])
		bi, bErr := strconv.Atoi(bp[i])
		switch {
		case aErr == nil && bErr == nil:
			if ai != bi {
				if ai > bi {
					return 1
				}
				return -1
			}
		case aErr == nil:
			return -1
		case bErr == nil:
			return 1
		default:
			if ap[i] != bp[i] {
				if ap[i] > bp[i] {
					return 1
				}
				return -1
			}
		}
	}
	if len(ap) > len(bp) {
		return 1
	}
	if len(ap) < len(bp) {
		return -1
	}
	return 0
}

func (v SemVer) IsPreRelease() bool { return v.PreRelease != "" }
func (v SemVer) String() string     { return v.Raw }
