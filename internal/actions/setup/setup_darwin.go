//go:build darwin

package setup

import "github.com/nulifyer/karchy/internal/platform"

func Audio()     { platform.Open("x-apple.systempreferences:com.apple.preference.sound") }
func WiFi()      { platform.Open("x-apple.systempreferences:com.apple.preference.network") }
func Bluetooth() { platform.Open("x-apple.systempreferences:com.apple.preferences.Bluetooth") }
func Display()   { platform.Open("x-apple.systempreferences:com.apple.preference.displays") }
func Power()     { platform.Open("x-apple.systempreferences:com.apple.preference.energysaver") }
func Timezone()  { platform.Open("x-apple.systempreferences:com.apple.preference.datetime") }
func WinUtil()   {}

func PowerProfile() string        { return "" }
func SetPowerProfile(profile string) {}
func PowerProfiles() []string     { return nil }
func RestartAudio()               {}
func RestartWiFi()                {}
func RestartBluetooth()           {}
