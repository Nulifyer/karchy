//go:build windows

package webapp

func launchExtraArgs() []string {
	return []string{"--window-size=1280,800"}
}
