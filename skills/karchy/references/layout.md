# Where things live and what is safe to edit

Use this file to decide where a change goes and whether it survives an update.

## The three layers

| Layer | Path | Owner | Edit it? |
| --- | --- | --- | --- |
| Packaged | `/usr/share/karchy` (`$KARCHY_PATH`), `/usr/bin/karchy-*`, `/usr/lib/karchy`, `/usr/lib/systemd` | pacman | Never. Read only. Updates replace it |
| User config | `~/.config/karchy`, `~/.config/hypr`, other `~/.config` folders | the user | Yes. Updates never rewrite it |
| Generated state | `~/.local/state/karchy` | karchy's commands | No. A command rewrites it. Change the source instead |

`/etc` belongs to the system. A change there is a system-level change: plan it, snapshot first, and use a drop-in file where the service supports one.

## The packaged tree

Read these to learn how a feature works.

| Path | Holds |
| --- | --- |
| `/usr/share/karchy/bin` | every `karchy-*` command. `/usr/bin/karchy-*` are links to these |
| `/usr/share/karchy/karchy/hypr` | karchy's Hyprland composition: `init.lua`, `bindings.lua`, `autostart.lua` |
| `/usr/share/karchy/karchy/shell.json` | the default bar layout and shell settings |
| `/usr/share/karchy/default/hypr` | the Hyprland modules that `init.lua` loads |
| `/usr/share/karchy/default/themed` | the templates that turn a theme's colors into app configs |
| `/usr/share/karchy/default/karchy` | the menu (`karchy-menu.jsonc`), the Quick install catalog (`quick-install.json`), the icon map |
| `/usr/share/karchy/shell` | the Quickshell shell and its built-in plugins |
| `/usr/share/karchy/plugins`, `/usr/share/karchy/hypr.d` | shell UI and Hyprland drop-ins that add-on packages install |
| `/usr/share/karchy/themes` | the packaged themes |
| `/usr/share/karchy/migrations` | scripts that `karchy update` runs once for each user |
| `/usr/share/karchy/release` | the installed karchy version and commit. `karchy version` prints it |

## The user's files

`/etc/skel` gives a new user the starter files once, when the account is created. From then on the files are the user's. A starter file is short: it loads karchy's defaults and leaves room for overrides.

| Path | Purpose |
| --- | --- |
| `~/.config/hypr/hyprland.lua` | entry point. Loads karchy's defaults, then the five files below |
| `~/.config/hypr/{monitors,input,bindings,looknfeel,autostart}.lua` | the user's Hyprland overrides. They load last, so they win |
| `~/.config/karchy/shell.json` | differences from `karchy/shell.json`: bar layout, plugins, idle times, battery warnings |
| `~/.config/karchy/shell.toml` | shell look overrides on top of the theme, such as the font size |
| `~/.config/karchy/{displays,input,power,nightlight,notifications}.json` | what the Settings window saved. Change them with the `karchy-settings-*` commands |
| `~/.config/karchy/themes/<name>` | the user's own themes |
| `~/.config/karchy/backgrounds/<theme>/` | extra backgrounds for one theme |
| `~/.config/karchy/themed/` | the user's own theme templates, used beside the packaged ones |
| `~/.config/karchy/extensions/karchy-menu.jsonc` | the user's additions to the menu. The shell watches it, so no restart is needed |
| `~/.config/karchy/hooks/` | the user's hook scripts |
| `~/.config/fontconfig/conf.d/60-karchy-font.conf` | the font chosen with `karchy font set` |
| `~/.config/mimeapps.list`, `~/.config/xdg-terminals.list` | default apps |

Terminal, GTK, btop and editor starter configs are also in `~/.config`. They are the user's. karchy's theming does not rewrite them.

## Generated state

Do not edit these files. Find the command that writes them.

| Path | Written by |
| --- | --- |
| `~/.local/state/karchy/current/theme`, `theme.name`, `background` | `karchy theme set`, `karchy theme bg set` |
| `~/.local/state/karchy/hypr/{displays,input,power}.lua` | `karchy-settings-displays`, `-input`, `-power` |
| `~/.local/state/karchy/toggles/` | `karchy toggle`, `karchy hyprland toggle` |
| `~/.local/state/karchy/migrations/` | `karchy-migrate`: one mark for each migration done, and a `.log` for each run |

## Hooks

`karchy-hook <name>` runs `~/.config/karchy/hooks/<name>` and then every file in `~/.config/karchy/hooks/<name>.d/`, with bash. Files that end in `.sample` are skipped. A hook that fails is reported and does not stop the caller.

karchy calls these names: `theme-set <theme>`, `font-set <font>`, `battery-low <percent>`, `battery-critical <percent>`. To confirm the list, run `grep -rn "karchy-hook " /usr/share/karchy/bin`. Use a hook when the user wants their own command to run on one of those events.

## Rules that decide where a change goes

- A value that a Settings page or a `karchy-*` command manages goes through that command.
- A Hyprland value goes in the matching file in `~/.config/hypr`.
- A shell or bar value goes in `~/.config/karchy/shell.json`, through `karchy bar` or `karchy plugin` where they cover it.
- Write only the keys that differ from the defaults. In `shell.json`, objects merge key by key, and an array or plain value replaces the default whole.
- A hand-written value in `~/.config/hypr` wins over what Settings saved. If a Settings change has no effect, look for an override there.
- Nothing loads shell plugins from the home folder. Plugins come from packages only.

## Dev mode

`/etc/karchy.conf` can set `KARCHY_PATH` to a checkout, for the developer of karchy. If `echo $KARCHY_PATH` is not `/usr/share/karchy`, the machine is in dev mode. The checkout is then the user's working copy: do not edit it unless the user asks, and say that dev mode is on. Root-run code always uses the packaged files.
