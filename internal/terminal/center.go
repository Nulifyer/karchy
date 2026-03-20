package terminal

import "github.com/nulifyer/karchy/internal/logging"

// launchCols/launchLines tracks the initial Alacritty dimensions so we can
// derive actual cell size from the rendered window rect.
var (
	launchCols  int
	launchLines int
)

// SetLaunchSize records the initial terminal dimensions for cell-size derivation.
// Called by the TUI process since it runs in a different process than Launch().
func SetLaunchSize(cols, lines int) {
	launchCols = cols
	launchLines = lines
}

// estimateCenter returns an approximate center position for a window
// with the given column/line dimensions. Uses font metric estimates.
// On Windows, the daemon will correct this precisely after the window renders.
func estimateCenter(cols, lines int) (x, y int) {
	// CaskaydiaMono NF at size 13: ~10px wide, ~20px tall; 4px padding each side
	estW := cols*10 + 8
	estH := lines*20 + 8

	waLeft, waTop, waW, waH := estimateWorkArea()

	x = waLeft + max(0, (waW-estW)/2)
	y = waTop + max(0, (waH-estH)/2)

	logging.Info("estimateCenter: cols=%d lines=%d estW=%d estH=%d work=(%d,%d,%dx%d) pos=(%d,%d)",
		cols, lines, estW, estH, waLeft, waTop, waW, waH, x, y)
	return
}
