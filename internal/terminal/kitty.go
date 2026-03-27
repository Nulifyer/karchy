package terminal

import "fmt"

func init() {
	RegisterBackend(&kittyBackend{})
}

type kittyBackend struct{}

func (k *kittyBackend) Name() string   { return "kitty" }
func (k *kittyBackend) Binary() string { return "kitty" }

func (k *kittyBackend) LaunchArgs(opts LaunchOpts, childArgs []string) []string {
	var args []string

	if opts.Borderless {
		args = append(args, "-o", "hide_window_decorations=yes")
	}
	if opts.Cols > 0 && opts.Lines > 0 {
		args = append(args, "-o", "remember_window_size=no")
		args = append(args, "-o", fmt.Sprintf("initial_window_width=%dc", opts.Cols))
		args = append(args, "-o", fmt.Sprintf("initial_window_height=%dc", opts.Lines))
	}
	if opts.Title != "" {
		args = append(args, "--title", opts.Title)
	}
	if len(childArgs) > 0 {
		args = append(args, childArgs...)
	}
	return args
}
