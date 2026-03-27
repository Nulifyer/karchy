package terminal

import "fmt"

func init() {
	RegisterBackend(&gnomeTerminalBackend{})
}

type gnomeTerminalBackend struct{}

func (g *gnomeTerminalBackend) Name() string   { return "gnome-terminal" }
func (g *gnomeTerminalBackend) Binary() string { return "gnome-terminal" }

func (g *gnomeTerminalBackend) LaunchArgs(opts LaunchOpts, childArgs []string) []string {
	var args []string

	if opts.Cols > 0 && opts.Lines > 0 {
		geo := fmt.Sprintf("%dx%d", opts.Cols, opts.Lines)
		if opts.PosX != 0 || opts.PosY != 0 {
			geo += fmt.Sprintf("+%d+%d", opts.PosX, opts.PosY)
		}
		args = append(args, "--geometry", geo)
	}
	if opts.Title != "" {
		args = append(args, "--title", opts.Title)
	}
	if len(childArgs) > 0 {
		args = append(args, "--")
		args = append(args, childArgs...)
	}
	return args
}
