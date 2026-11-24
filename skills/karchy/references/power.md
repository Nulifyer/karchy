# Power, idle, sleep and notifications

Read this before you change idle times, screen dimming, the lid or power button, hibernation, the power profile, screen brightness on battery or plugged in, battery warnings, or notification settings.

## Power settings

`karchy-settings-power` is the Settings › Power page's command. `karchy settings power` opens the page.

- `karchy-settings-power status` prints JSON: what the machine has (`battery`, `lid`, `hibernation`, `backlight`, and the power `profiles`), each value in effect (`values`; for `empty.action` that is what the running UPower answers), what Settings recorded (`saved`), settings that something else decides (`foreign`), the power source in use (`source`: `battery` or `ac`) and the profile running now (`profile`). Read it before a change.
- `karchy-settings-power set <setting> <value>` changes one setting. `karchy-settings-power reset` forgets every choice made here.

| Setting | Value |
| --- | --- |
| `profile.battery`, `profile.ac` | `power-saver`, `balanced`, `performance` (those in `profiles`) |
| `brightness.battery`, `brightness.ac` | `keep`, or percent (1 to 100) |
| `screenOff.battery`, `screenOff.ac`, `lock.battery`, `lock.ac`, `sleep.battery`, `sleep.ac` | `never`, or seconds idle (10 to 86400) |
| `dim.battery`, `dim.ac` | `never`, or seconds (5 to 600) before the screen turns off |
| `battery.low`, `battery.critical` | percent (low 5 to 50, critical 3 to 30 and under low; both above `empty.level`) |
| `battery.saver` | `on` (the default), `off` |
| `empty.level` | percent (2 to 20, under the last battery warning that is on) |
| `empty.action` | `hibernate` (the default where the machine can hibernate), `poweroff` |
| `powerKey` | `menu`, `sleep`, `hibernate`, `shutdown`, `nothing` |
| `lid.battery`, `lid.ac`, `lid.docked` | `sleep`, `ignore`, `poweroff`, `hibernate` |
| `hibernateAfter` | `never`, or minutes asleep (5 to 1440) |
| `hibernate.ac` | `never` (plugged in, stay asleep; the time counts from when the charger is pulled), `same` (hibernate after `hibernateAfter` plugged in too) |

A desktop uses only the `.ac` settings. Example: `karchy-settings-power set lock.ac 600`.

What the `.battery` and `.ac` settings do when the power source changes:

- The idle times follow the source at once, also during an idle stretch.
- `dim.*` dims the built-in screen that long before it turns off: before the screen-off time, before the lock where that comes first, or before sleep. The default is 30 seconds on both sources. The screen goes to 10% (`idle.dimBrightness` in `shell.json`) and gets its level back at the first key or pointer movement. A screen already darker is not touched. A machine without a built-in screen has no such setting in effect.
- `profile.*` is the power profile the source switches to. Setting the one for the source in use switches now. Setting the other one waits for that source.
- `brightness.*` sets the built-in screen once, when the charger goes in or out. `keep` (the default) leaves the screen as it is. The brightness keys work as before afterwards. Setting the one for the source in use changes the screen now.
- `battery.saver on`, the default, switches to `power-saver` at the first battery warning of a discharge. It ends when the charger goes in or when a profile is picked by hand. The battery's own profile stays remembered. `battery.saver off` keeps the battery's profile at any charge.

## Where each value is stored

Use `set` so that each value lands where the system reads it. The files matter when a value does not take effect.

- Idle times, dimming, screen brightness and battery warnings are the `idle`, `power.brightness` and `battery` keys of `~/.config/karchy/shell.json`. The user can edit that file. A value there is what runs.
- The power profile of each source is in `~/.local/state/karchy/powerprofiles/ac` and `battery`. `karchy-powerprofiles-set` writes them, for Settings and for the bar's power panel alike. `power.json` does not record them.
- The power button is a binding in `~/.local/state/karchy/hypr/power.lua`. A binding for the key in `~/.config/hypr` wins.
- The lid, the hibernate delay and hibernation while plugged in are in `/etc/systemd/logind.conf.d/60-karchy-settings.conf` and `/etc/systemd/sleep.conf.d/60-karchy-settings.conf`. The level and action for a nearly empty battery are in `/etc/UPower/UPower.conf.d/60-karchy-settings.conf`. The root helper `/usr/lib/karchy/power-settings` writes all three through pkexec, with no password for the person at the computer, and restarts `upower.service` when its file changed. Do not write those three files by hand.
- A drop-in that sorts later, such as `90-mine.conf`, wins over Settings. `status` reports such a setting under `foreign`. If a value does not take effect, look there first.
- `~/.config/karchy/power.json` records what Settings changed. Do not edit it. Change the setting with `set`.

## Sleep and hibernation

- A laptop suspends when the lid closes and hibernates after 2 hours asleep on battery. Plugged in it stays asleep, and the 2 hours start when the charger is pulled (`hibernate.ac`). Docked with an external display, the lid does nothing.
- `karchy-hibernation-available` exits 0 when the machine can hibernate. Check it before you offer hibernation. On NVIDIA machines karchy turns hibernation off on purpose. Do not turn it back on.
- To turn hibernation off, create `/etc/systemd/sleep.conf.d/90-no-hibernate.conf` with `AllowHibernation=no`, `AllowSuspendThenHibernate=no` and `AllowHybridSleep=no` under `[Sleep]`. This is a `/etc` change: get the user's agreement. Warn that a closed laptop then drains its battery over days. Delete the file to undo.
- `karchy-toggle suspend-off on` hides Suspend from the menu and stops idle sleep for this user. `karchy-toggle suspend-off off` brings them back. `karchy-toggle-enabled suspend-off` tests the flag.
- The session locks before every sleep (`karchy-sleep-lock.service`). Do not disable it.
- If the computer does not sleep or the screen does not lock, run `karchy system idle-inhibit` first. It lists what holds the screen or sleep.

## Session commands

- `karchy system lock` locks and turns off the display. `karchy system wake` wakes the displays.
- `karchy-brightness-display dim <percent>` and `karchy-brightness-display undim` are the idle service's. Do not call `dim` yourself. If the built-in screen stays dark after an idle stretch, `karchy-brightness-display undim` puts back the level noted in `$XDG_RUNTIME_DIR/karchy-brightness-display-dim`, and `karchy-shell idle status` shows `dimAfter` (seconds idle before dimming, 0 for never) and `dimmed`.
- `karchy system logout`, `karchy system reboot` and `karchy system shutdown` close applications first. Never run reboot, shutdown or logout without the user's request in the same turn. They end the session that runs the agent.

## Power profiles

Power profiles exist where `power-profiles-daemon` is installed, which karchy does on laptops.

- `karchy-powerprofiles-list` lists the profiles this machine has.
- `karchy-powerprofiles-set ac|battery <power-saver|balanced|performance>` remembers the profile for that power source and switches to it when that source is the one in use. The default is `balanced` on both. `karchy-settings-power set profile.ac|profile.battery` does the same.
- `karchy-powerprofiles-set ac|battery` without a profile switches to the remembered one. On battery at or under the first battery warning it switches to `power-saver` instead, unless `battery.saver` is off. `karchy-battery-running-low` is that test: it exits 0 on battery at or under the first warning level.
- `karchy-power-source ac|battery` applies a source's profile and screen brightness. The shell's battery service runs it when the charger goes in or out. Do not run it on a timer.
- If the profile running now (`profile` in `status`) is not the one set for the source in use, a low battery (`battery.saver`), an app holding a profile, or `powerprofilesctl` run by hand set it.

## Battery warnings

- The shell warns at `battery.low` (default 15) and `battery.critical` (default 5).
- On battery at or under the first warning the battery counts as low (`karchy-battery-running-low` exits 0). Two things follow: Power saver (unless `battery.saver` is off) and no screensaver. The idle cycle still dims, locks and sleeps. Nothing turns the screensaver rule off; `karchy-launch-screensaver force` starts the screensaver anyway.
- A little below the critical level UPower hibernates the machine, or powers it off where it cannot hibernate. The level is `empty.level` (3 by default) and the action `empty.action`. `set` refuses an `empty.level` at or above the last warning, and a warning at or under `empty.level`: change the other one first. Only a hand edit of `shell.json` can put a warning under the level; the page then says so.
- UPower reads `/etc/UPower/UPower.conf`, then the files in `/etc/UPower/UPower.conf.d` named two digits, a dash, then letters, digits, dashes or underscores, then `.conf`. A drop-in overrides only keys the main file has. If `PercentageLow`, `PercentageCritical` and `PercentageAction` do not descend, UPower uses 20, 5 and 2 for all three. It reads its files only when it starts: after a hand edit run `sudo systemctl try-restart upower.service`, with the user's agreement. `busctl call org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower GetCriticalAction` prints what the running UPower will do.
- `karchy-battery-status` prints the charge and the power draw.

## Feature toggles

`karchy-toggle <flag> [toggle|on|off]` creates or removes a flag file in `~/.local/state/karchy/toggles/`. It is a small, reversible change. Flags that karchy reads include `suspend-off` and `screensaver-off`. A flag that nothing reads does nothing, so check that the flag name appears in `/usr/share/karchy` before you set it.

## Notifications

`karchy-settings-notifications` is the Settings › Notifications page's command.

- `karchy-settings-notifications status` prints Do Not Disturb and every app that has sent a notification, with its mode.
- `karchy-settings-notifications set <app> <allow|silent|off> [name]` sets one app. `silent` keeps the notification in the panel without a popup. `off` drops it. Take the app key from `status`: `app:<name>` or `web:<host>`.
- `karchy-settings-notifications dnd <on|off>` switches Do Not Disturb.
- The settings are in `~/.config/karchy/notifications.json`, which the notification service watches. Only `silent` and `off` entries are written.
- To send a notification from a script, use `karchy-notification-send`. Read its header for the options.
