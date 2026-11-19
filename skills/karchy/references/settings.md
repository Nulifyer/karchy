# The Settings window and its commands

`karchy settings [section] [item]` opens the Settings window. `karchy-settings --sections` prints the section names: displays, input, power, network, notifications, storage, ssh, appearance, fonts, apps, about.

Most sections have a command that reads and saves the same values the page does. Use that command, not the JSON file. The command validates the value, writes the file, and applies the change to the running session. The commands are hidden from `karchy commands`. Call them by their file name: `karchy-settings-input status`.

Every command prints JSON for `status`. Read `status` before a change, and read it again after the change to confirm.

## Sections

| Section | Command | Saved in | Applied through |
| --- | --- | --- | --- |
| Displays | `karchy-settings-displays status \| set <monitor> <setting> <value> \| forget <monitor>` | `~/.config/karchy/displays.json`, one entry for each physical monitor | `~/.local/state/karchy/hypr/displays.lua` |
| Night light (on the Displays page) | `karchy-settings-nightlight status \| on \| off \| toggle \| set <key> <value>` | `~/.config/karchy/nightlight.json` | user unit `karchy-nightlight.service` (hyprsunset) |
| Input | `karchy-settings-input status \| set <setting> <value> \| reset <setting>\|all` | `~/.config/karchy/input.json` | `~/.local/state/karchy/hypr/input.lua` |
| Power | `karchy-settings-power status \| set <setting> <value> \| reset` | `~/.config/karchy/power.json` | see [power.md](power.md) |
| Notifications | `karchy-settings-notifications status \| set <app> <allow\|silent\|off> [name] \| dnd <on\|off>` | `~/.config/karchy/notifications.json` | the notification service watches the file |
| Storage | `karchy-settings-storage ...` | nothing in the home folder | see [storage.md](storage.md) |
| SSH | `karchy-settings-ssh status \| authorized add\|remove ... \| key copy\|new \| agent on\|off` | `~/.ssh` | see below |
| Default apps | `karchy-settings-default-apps status \| set <role> <app.desktop>` | `~/.config/mimeapps.list`, `~/.config/xdg-terminals.list` | xdg-mime |
| Network | no single command | NetworkManager, `/etc` | see [network.md](network.md) |
| Appearance | no single command | see [themes.md](themes.md) and the bar section of [hyprland.md](hyprland.md) | `karchy theme`, `karchy bar` |
| Fonts | no single command | see [themes.md](themes.md) | `karchy font` (monospace), `karchy font app` (GTK and Qt apps), `karchy display text size` |
| About | none | read only | `karchy version`, `karchy channel` |

The valid settings and values for each command are in its header comment. Read it with `sed -n 1,60p /usr/share/karchy/bin/karchy-settings-<area>`.

## Rules these commands follow

- Each JSON file holds only the values that differ from karchy's defaults. A value that was never changed keeps following the defaults. To return a value to the default, use `reset` or `forget`. Do not write the default value into the file.
- The Hyprland values that Settings saves load after karchy's defaults and before `~/.config/hypr`. A rule that the user wrote in `~/.config/hypr/monitors.lua` or `input.lua` wins. If a `set` has no effect, check those files, and tell the user which line overrides the setting.
- Displays are saved for the physical monitor (make, model and serial), not the connector. `set` accepts a connector name such as `DP-1`.
- Idle times and battery warnings are the `idle` and `battery` keys of `~/.config/karchy/shell.json`. `karchy-settings-power set` writes them there, one key for each change. A hand edit of those keys is also valid, and it is what `status` reports.
- `~/.config/hypr/hyprsunset.conf`, if the user wrote one, replaces the night-light profiles that Settings generates.

## What needs a password

- Displays, input, night light, notifications, default apps and the user's own SSH keys need none.
- Lid actions and the hibernate delay go through the root helper `/usr/lib/karchy/power-settings`. It asks no password from the person at the computer.
- The SSH server is set up and removed in a terminal, with the password: `karchy-setup-security-sshd` and `karchy-remove-security-sshd`. Run them only when the user asked for the server to change. Opening the machine to SSH is a system-level change.
- Trusted networks, DNS and the Wi-Fi country ask for the administrator's password. See [privilege.md](privilege.md).

## Examples

```sh
karchy-settings-input set repeatRate 40
karchy-settings-input reset repeatRate          # undo
karchy-settings-displays set DP-1 scale 1.25
karchy-settings-power set lock.ac 600           # lock after 10 minutes on mains power
karchy-settings-notifications set app:signal silent Signal
karchy-settings-default-apps set browser firefox.desktop
```

To show the user where a setting is, open the page: `karchy settings power`. For the network page, an item opens it at one thing: `karchy settings network dns`.
