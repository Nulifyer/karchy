# The Settings window and its commands

`karchy settings [section] [item]` opens the Settings window. `karchy-settings --sections` prints the section names in the window's order: network, bluetooth, displays, sound, input, keybindings, appearance, fonts, notifications, apps, power, storage, datetime, users, security, ssh, about. `karchy settings` with no section opens the first.

Settings is where everything that is set and left lives. The menu (Super+Space) holds actions and launches only (Apps, Packages, Recording, Keybinds, Update, Settings, Reload, Power): there is no Setup or Appearance submenu, and Update opens the Updates window. Searching the menu for a word such as `fingerprint`, `timezone` or `git` offers the Settings page ("Settings › Security"). To send the user to a setting, name the page.

Most sections have a command that reads and saves the same values the page does. Use that command, not the JSON file. The command validates the value, writes the file, and applies the change to the running session. The commands are hidden from `karchy commands`. Call them by their file name: `karchy-settings-input status`.

Every command prints JSON for `status`. Read `status` before a change, and read it again after the change to confirm.

## Sections

| Section | Command | Saved in | Applied through |
| --- | --- | --- | --- |
| Network | no single command | NetworkManager, `/etc` | see [network.md](network.md) |
| Displays | `karchy-settings-displays status \| set <monitor> <setting> <value> \| forget <monitor>` | `~/.config/karchy/displays.json`, one entry for each physical monitor | `~/.local/state/karchy/hypr/displays.lua` |
| Night light (on the Displays page) | `karchy-settings-nightlight status \| on \| off \| toggle \| set <key> <value>` | `~/.config/karchy/nightlight.json` | user unit `karchy-nightlight.service` (hyprsunset) |
| Bluetooth (listed only with an adapter) | no single command | BlueZ (`/var/lib/bluetooth`), the rfkill block | `karchy bluetooth power on\|off\|toggle\|is-on`, `karchy bluetooth device connect\|disconnect\|forget <address>`, `bluetoothctl` |
| Sound | `karchy-settings-sound status \| profile <card> <profile> \| port <output\|input> <port> \| test` | nothing in the home folder: WirePlumber remembers the device, its profile and its port | `pactl`; volumes and the device in use: `karchy audio …`, `wpctl` |
| Input | `karchy-settings-input status \| set <setting> <value> \| reset <setting>\|all` | `~/.config/karchy/input.json` | `~/.local/state/karchy/hypr/input.lua` |
| Keybindings | `karchy-settings-keybindings list [--json] \| conflicts <keys> \| set \| add \| remove \| reset` | `~/.config/karchy/keybindings.json` | `~/.local/state/karchy/hypr/keybindings.lua`; see [keybindings.md](keybindings.md) |
| Appearance | no single command | see [themes.md](themes.md) and the bar section of [hyprland.md](hyprland.md) | `karchy theme`, `karchy bar`, `karchy-hyprland-workspace-layout-default [dwindle\|floating\|scrolling]` (the layout of new and empty workspaces) |
| Fonts | no single command | see [themes.md](themes.md) | `karchy font` (monospace), `karchy font app` (the interface font of the shell and apps), `karchy display text size` |
| Notifications | `karchy-settings-notifications status \| set <app> <allow\|silent\|off> [name] \| dnd <on\|off>` | `~/.config/karchy/notifications.json` | the notification service watches the file |
| Default apps | `karchy-settings-default-apps status \| set <role> <app.desktop>` | `~/.config/mimeapps.list`, `~/.config/xdg-terminals.list` | xdg-mime |
| Power | `karchy-settings-power status \| set <setting> <value> \| reset` | `~/.config/karchy/power.json` (the power profiles: `~/.local/state/karchy/powerprofiles/`) | see [power.md](power.md) |
| Storage | `karchy-settings-storage ...` | nothing in the home folder | see [storage.md](storage.md) |
| Date & Time (section `datetime`) | `karchy-settings-datetime status \| timezones \| timezone <Area/City> \| ntp on\|off \| sync \| clock <format>` | systemd (timezone, automatic time); the clock's format in `~/.config/karchy/shell.json` | timedated over D-Bus; `karchy bar set karchy.clock format` |
| Users | `karchy-settings-users status \| add <name> admin\|standard [full name] \| remove <name> \| full-name <name> [full name] \| role <name> admin\|standard \| reset-password <name> \| autologin on\|off \| password` | `/etc/passwd`, `/etc/group`, `/etc/shadow`, the `[initial_session]` part of `/etc/greetd/config.toml` | see below |
| Security | `karchy-settings-security status` (read only); saved passwords: `karchy-keyring status [--json] \| reset` | `/etc/pam.d`, `/etc/fido2`, the LUKS header; `~/.local/share/keyrings` | see below |
| SSH & Git (section `ssh`) | `karchy-settings-ssh status \| authorized add\|remove ... \| key copy\|new \| agent on\|off` | `~/.ssh`, `~/.gitconfig` | see below |
| About | none | read only | `karchy version`, `karchy channel` |

The valid settings and values for each command are in its header comment. Read it with `sed -n 1,60p /usr/share/karchy/bin/karchy-settings-<area>`.

## Rules these commands follow

- Each JSON file holds only the values that differ from karchy's defaults. A value that was never changed keeps following the defaults. To return a value to the default, use `reset` or `forget`. Do not write the default value into the file.
- The Hyprland values that Settings saves load after karchy's defaults and before `~/.config/hypr`. A rule that the user wrote in `~/.config/hypr/monitors.lua` or `input.lua` wins. If a `set` has no effect, check those files, and tell the user which line overrides the setting.
- Displays are saved for the physical monitor (make, model and serial), not the connector. `set` accepts a connector name such as `DP-1`.
- Idle times, the screensaver's time, dimming before the screen turns off, the screen brightness for each power source and battery warnings are the `idle`, `power.brightness` and `battery` keys of `~/.config/karchy/shell.json`. `karchy-settings-power set` writes them there, one key for each change. A hand edit of those keys is also valid, and it is what `status` reports.
- `~/.config/hypr/hyprsunset.conf`, if the user wrote one, replaces the night-light profiles that Settings generates.
- A page whose area has a file the user may edit by hand links it in its header ("Open config file"): `monitors.lua` (Displays), `input.lua` (Input), `bindings.lua` (Keybindings), `shell.json` (Power, Date & Time, Appearance), `looknfeel.lua` (Appearance), the default terminal's config (Fonts), `mimeapps.list` (Default apps), `~/.ssh/config` and `~/.gitconfig` (SSH & Git), `hyprland.lua` (About). `karchy-launch-config-editor <path>` opens one in the user's editor, and creates a missing one from `/etc/skel` first.

## What needs a password

- Displays, input, night light, notifications, default apps and the user's own SSH keys need none.
- Lid actions, the hibernate delay, hibernation while plugged in and the level and action for a critical battery (`criticalBattery.level`, `criticalBattery.action`) go through the root helper `/usr/lib/karchy/power-settings`. It asks no password from the person at the computer.
- The SSH server is set up and removed in a terminal, with the password: `karchy-setup-security-sshd` and `karchy-remove-security-sshd`. Run them only when the user asked for the server to change. Opening the machine to SSH is a system-level change.
- Trusted networks, DNS and the Wi-Fi country ask for the administrator's password. See [privilege.md](privilege.md).
- The timezone, automatic time and `sync` ask for the password in the shell's dialog (`karchy-settings-datetime`); a dismissed dialog exits 1 with `Canceled.`. The clock's format needs none.
- Every change on the Users page asks for an administrator's password in the shell's dialog, each time: `karchy-settings-users add`, `remove`, `full-name`, `role`, `reset-password` and `autologin` (the root helper `/usr/lib/karchy/users-settings`; see [privilege.md](privilege.md)). Accounts are system-level: make one of these changes only when the user asked for exactly that, and never choose `delete-home` yourself. `add` and `reset-password` read the password from stdin or ask at a terminal; never pass, invent or store one, let the user type it. `karchy-settings-users status` is free to read: it lists each person (`name`, `fullName`, `admin`, `you`, `signedIn`), says in `cannotRemove` and `cannotChangeRole` why a change would be refused (the only administrator, a person who is signed in, the account that is asking), and under `autologin` whether the computer logs in by itself and, in `cannotTurnOn`, why it can't (no disk encryption, or more than one person). A refused change exits 65 with the reason on stderr, before any password is asked. On an encrypted computer, adding the second person turns automatic login off (`autologin=off` on stdout); tell the user that the login screen now follows the disk password and that their own password is still the disk password until they change it (`karchy-settings-users password`, which is `passwd`). `autologin on` may print `autologin=pending` (`autologin.pending` in `status`): automatic login starts after that person next logs in at the login screen, because their saved passwords have to change from the login password to a key of the computer first. `reset-password` leaves that person's saved passwords locked with the old password wherever `status` says `keyringPassword` is true; tell the user that the person resets them in Settings › Security.
- Everything on the Security page runs in a terminal with the user present, because each asks for the password, a touch or a typed secret: `karchy-settings-users password` (the user's own password, through `passwd`), `karchy-drive-password` (the disk's; it says so and changes nothing when the disk is not encrypted), `karchy-setup-security-fingerprint` and `karchy-remove-security-fingerprint` (only with a reader: `karchy-hw-fingerprint`), `karchy-setup-security-fido2` and `karchy-remove-security-fido2`. Never run these for the user unasked, and never type a password for them. `karchy-settings-security status` says what is set up.
- Saved passwords (the login keyring: what Brave, VS Code and other apps keep) open by themselves at login; nothing asks for a keyring password. `karchy-keyring status` prints `open`, `locked` (it could not be opened at login: the password was reset without the old one) or `none` (no keyring; a new one starts at the next login), and `--json` adds `opensWith` (`password` or `key`). `karchy-keyring reset` erases the keyring so apps can save again, after asking (`--yes` skips the question): everything saved in it is gone for good. Run it only when the user asked for exactly that, and say first what is lost. After a reset where the login password opens the keyring, the user has to log out and in before apps can save.
- `karchy-setup-git` sets the git name and email and offers the GitHub sign-in: interactive in a terminal, or `karchy-setup-git --name "…" --email …` with no questions. `karchy-settings-ssh status` shows the result under `git`.

## Examples

```sh
karchy-settings-input set repeatRate 40
karchy-settings-input reset repeatRate          # undo
karchy-settings-displays set DP-1 scale 1.25
karchy-settings-power set lock.ac 600           # lock after 10 minutes on mains power
karchy-settings-power set profile.battery power-saver   # Power saver whenever on battery
karchy-settings-notifications set app:signal silent Signal
karchy-settings-default-apps set browser firefox.desktop
karchy-settings-datetime timezone Europe/Berlin   # the password dialog appears on the desktop
karchy-settings-datetime clock "h:mm AP"
karchy-settings-security status
karchy-settings-users status                      # who has an account, and what can change
```

To show the user where a setting is, open the page: `karchy settings power`. For the network page, an item opens it at one thing: `karchy settings network dns`.
