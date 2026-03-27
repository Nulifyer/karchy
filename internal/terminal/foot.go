package terminal

import "fmt"

func init() {
	RegisterBackend(&footBackend{})
}

type footBackend struct{}

func (f *footBackend) Name() string   { return "foot" }
func (f *footBackend) Binary() string { return "foot" }

func (f *footBackend) LaunchArgs(opts LaunchOpts, childArgs []string) []string {
	var args []string

	if opts.Cols > 0 && opts.Lines > 0 {
		args = append(args, fmt.Sprintf("--window-size-chars=%dx%d", opts.Cols, opts.Lines))
	}
	if opts.Title != "" {
		args = append(args, "--title="+opts.Title)
	}
	if len(childArgs) > 0 {
		args = append(args, childArgs...)
	}
	return args
}
