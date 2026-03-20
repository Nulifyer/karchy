package terminal

// MonitorBehavior controls which monitor the menu window is centered on.
type MonitorBehavior int

const (
	MonitorMouse        MonitorBehavior = iota // monitor under the cursor (default)
	MonitorPrimary                             // always the primary monitor
	MonitorActiveWindow                        // monitor of the foreground window
)

// activeBehavior is the configured behavior; set via SetMonitorBehavior.
var activeBehavior MonitorBehavior

// SetMonitorBehavior configures which monitor centering uses.
func SetMonitorBehavior(b MonitorBehavior) {
	activeBehavior = b
}

// ParseMonitorBehavior converts a config string to a MonitorBehavior.
// Unknown values fall back to MonitorMouse.
func ParseMonitorBehavior(s string) MonitorBehavior {
	switch s {
	case "primary":
		return MonitorPrimary
	case "active_window":
		return MonitorActiveWindow
	default:
		return MonitorMouse
	}
}
