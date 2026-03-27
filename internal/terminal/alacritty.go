package terminal

import "fmt"

func init() {
	RegisterBackend(&alacrittyBackend{})
}

type alacrittyBackend struct{}

func (a *alacrittyBackend) Name() string   { return "alacritty" }
func (a *alacrittyBackend) Binary() string { return "alacritty" }

func (a *alacrittyBackend) LaunchArgs(opts LaunchOpts, childArgs []string) []string {
	var args []string

	if opts.Borderless {
		args = append(args, "-o", `window.decorations="None"`)
	}
	if opts.Cols > 0 && opts.Lines > 0 {
		args = append(args, "-o", fmt.Sprintf("window.dimensions={columns=%d, lines=%d}", opts.Cols, opts.Lines))
	}
	if opts.PosX != 0 || opts.PosY != 0 {
		args = append(args, "-o", fmt.Sprintf("window.position={x=%d, y=%d}", opts.PosX, opts.PosY))
	}
	if opts.Title != "" {
		args = append(args, "--title", opts.Title)
	}
	if len(childArgs) > 0 {
		args = append(args, "-e")
		args = append(args, childArgs...)
	}
	return args
}
