package terminal

func init() {
	RegisterBackend(&weztermBackend{})
}

type weztermBackend struct{}

func (w *weztermBackend) Name() string   { return "wezterm" }
func (w *weztermBackend) Binary() string { return "wezterm" }

func (w *weztermBackend) LaunchArgs(opts LaunchOpts, childArgs []string) []string {
	args := []string{"start"}
	if len(childArgs) > 0 {
		args = append(args, "--")
		args = append(args, childArgs...)
	}
	return args
}
