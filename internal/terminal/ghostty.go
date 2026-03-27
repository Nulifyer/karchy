package terminal

import "fmt"

func init() {
	RegisterBackend(&ghosttyBackend{})
}

type ghosttyBackend struct{}

func (g *ghosttyBackend) Name() string   { return "ghostty" }
func (g *ghosttyBackend) Binary() string { return "ghostty" }

func (g *ghosttyBackend) LaunchArgs(opts LaunchOpts, childArgs []string) []string {
	var args []string

	if opts.Borderless {
		args = append(args, "--window-decoration=false", "--gtk-titlebar=false")
	}
	if opts.Cols > 0 {
		args = append(args, fmt.Sprintf("--window-width=%d", opts.Cols))
	}
	if opts.Lines > 0 {
		args = append(args, fmt.Sprintf("--window-height=%d", opts.Lines))
	}
	if opts.Title != "" {
		args = append(args, fmt.Sprintf("--title=%s", opts.Title))
	}
	if len(childArgs) > 0 {
		args = append(args, "-e")
		args = append(args, childArgs...)
	}
	return args
}
