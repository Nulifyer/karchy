//go:build windows

package setup

import (
	"fmt"
	"os/exec"

	"github.com/nulifyer/karchy/internal/platform"
)

func Audio()     { platform.Open("ms-settings:sound") }
func WiFi()      { platform.Open("ms-settings:network-wifi") }
func Bluetooth() { platform.Open("ms-settings:bluetooth") }
func Display()   { platform.Open("ms-settings:display") }
func Power()     { platform.Open("ms-settings:powersleep") }
func Timezone()  { platform.Open("ms-settings:dateandtime") }

// WinUtil launches the Chris Titus Windows Utility.
// The script handles its own elevation and terminal window.
func WinUtil() {
	fmt.Print("\n Loading Chris Titus WinUtil...")
	exec.Command("powershell", "-Command", "irm https://christitus.com/win | iex").Run()
}

func PowerProfile() string           { return "" }
func SetPowerProfile(profile string) {}
func PowerProfiles() []string        { return nil }
func RestartAudio()                  {}
func RestartWiFi()                   {}
func RestartBluetooth()              {}
