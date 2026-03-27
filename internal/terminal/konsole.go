package terminal

func init() {
	RegisterBackend(&konsoleBackend{})
}

type konsoleBackend struct{}

func (k *konsoleBackend) Name() string   { return "konsole" }
func (k *konsoleBackend) Binary() string { return "konsole" }

func (k *konsoleBackend) LaunchArgs(opts LaunchOpts, childArgs []string) []string {
	var args []string

	if opts.Borderless {
		args = append(args, "--fullscreen", "--hide-tabbar")
	}
	if len(childArgs) > 0 {
		args = append(args, "-e")
		args = append(args, childArgs...)
	}
	return args
}
