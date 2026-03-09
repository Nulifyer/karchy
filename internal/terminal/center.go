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

// estimateCenter returns an approximate screen-center position for a window
// with the given column/line dimensions. Uses font metric estimates.
// On Windows, the daemon will correct this precisely after the window renders.
func estimateCenter(cols, lines int) (x, y int) {
	// CaskaydiaMono NF at size 13: ~9px wide, ~22px tall
	estW := cols*9 + 32  // 16px padding each side
	estH := lines*22 + 24 // 12px padding each side

	// Assume 1920x1080 as fallback; platform-specific code can override
	screenW, screenH := screenSize()

	x = max(0, (screenW-estW)/2)
	y = max(0, (screenH-estH)/2)

	logging.Info("estimateCenter: cols=%d lines=%d estW=%d estH=%d screen=%dx%d x=(%d-%d)/2=%d y=(%d-%d)/2=%d",
		cols, lines, estW, estH, screenW, screenH, screenW, estW, x, screenH, estH, y)
	return
}
