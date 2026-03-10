//go:build windows

package assets

import _ "embed"

//go:embed karchy.ico
var IconICO []byte

//go:embed karchy-badge.ico
var IconBadgeICO []byte
