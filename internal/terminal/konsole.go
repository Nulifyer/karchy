package terminal

import "fmt"

func init() {
	RegisterBackend(&konsoleBackend{})
}

type konsoleBackend struct{}

func (k *konsoleBackend) Name() string   { return "konsole" }
func (k *konsoleBackend) Binary() string { return "konsole" }

func (k *konsoleBackend) LaunchArgs(opts LaunchOpts, childArgs []string) []string {
	var args []string

	if opts.Borderless {
		args = append(args, "--hide-menubar", "--hide-tabbar")
	}
	if opts.Cols > 0 && opts.Lines > 0 {
		args = append(args, "-p", fmt.Sprintf("TerminalColumns=%d", opts.Cols))
		args = append(args, "-p", fmt.Sprintf("TerminalRows=%d", opts.Lines))
	}
	if opts.Title != "" {
		args = append(args, "--qwindowtitle", opts.Title)
	}
	// -e must be last as it captures all remaining arguments
	if len(childArgs) > 0 {
		args = append(args, "-e")
		args = append(args, childArgs...)
	}
	return args
}
