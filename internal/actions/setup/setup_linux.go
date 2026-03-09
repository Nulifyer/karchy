//go:build linux

package setup

import "os/exec"

func Audio()     { exec.Command("pavucontrol").Start() }
func WiFi()      { exec.Command("kcmshell6", "kcm_networkmanagement").Start() }
func Bluetooth() { exec.Command("kcmshell6", "kcm_bluetooth").Start() }
func Display()   { exec.Command("kcmshell6", "kcm_kscreen").Start() }
func Power()     { exec.Command("kcmshell6", "kcm_energyinfo").Start() }
func Timezone()  { exec.Command("kcmshell6", "kcm_clock").Start() }
func WinUtil()   {}
