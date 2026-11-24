# Hyprland, keybindings, the bar and the shell

karchy configures Hyprland in Lua. The config has three layers, loaded in this order. A later layer wins.

1. karchy's defaults: `/usr/share/karchy/karchy/hypr/init.lua`, which loads `karchy/hypr/bindings.lua`, `autostart.lua`, the modules in `default/hypr/`, the add-on drop-ins in `/usr/share/karchy/hypr.d/*.lua`, and the current theme's Hyprland file.
2. What the Settings window saved: `~/.local/state/karchy/hypr/{displays,input,power}.lua`. Generated. Do not edit.
3. The user's files: `~/.config/hypr/monitors.lua`, `input.lua`, `bindings.lua`, `looknfeel.lua`, `autostart.lua`, in that order.

`~/.config/hypr/hyprland.lua` is the entry point that loads all three. Leave its `dofile` and `require` lines in place and in order. Removing one removes karchy's desktop.

Make every Hyprland change in layer 3, or through a `karchy-settings-*` command for layer 2. Never in layer 1.

## Before you edit

- Read the default that you want to change. For a key, run `karchy-settings-keybindings list` ([keybindings.md](keybindings.md)). For look and feel, read `/usr/share/karchy/default/hypr/looknfeel.lua`. For input, read `default/hypr/input.lua`.
- If the value is a display, keyboard, mouse or touchpad setting that Settings shows, prefer the Settings command ([settings.md](settings.md)). Use `~/.config/hypr` when Settings does not offer the value, or when the user wants the rule in their own file.
- Check that the user's file does not already set the value.

## Keybindings

karchy has a keybinding system with layers and an editor (Settings › Keybindings, Super+K). Read [keybindings.md](keybindings.md) before you add, change or remove a shortcut: use `karchy-settings-keybindings`, not a hand edit, unless the user keeps their own `~/.config/hypr/bindings.lua`.

## Monitors, input, look, autostart

- Monitors: `hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })` in `monitors.lua`. List outputs with `hyprctl monitors all`. A rule here wins over Settings › Displays, so tell the user when you add one. In a virtual machine (package `karchy-vm`), an output named `Virtual-N` whose rule asks for `mode = "preferred"` follows the viewer's window size; a rule with a size stops that.
- Look and feel: `hl.config({ general = { gaps_in = 5, gaps_out = 10 } })` in `looknfeel.lua`. Write only the keys that change.
- Autostart: `o.launch_on_start("my-app")` in `autostart.lua`.
- Window rules: `o.window(match, rules)`. Read `default/hypr/windows.lua` and `default/hypr/apps/` for working examples before you write one.
- Which window is in front: a floating window is always in front of the tiled ones, and the one with the keyboard is in front of the other floating ones. To keep a window in front of the others on its workspace, float it and tag it: `o.window("its-class", { float = true, tag = "+stay-in-front" })`. To keep one on every workspace too, pin it (`pin = true`), as picture-in-picture is. The rules are in `default/hypr/stacking.lua`.
- Halves: on a floating workspace Super+Left and Super+Right put the window on the left or right half of its monitor, and Super+Down gives it its earlier size back (`default/hypr/snap.lua`). On a tiling workspace the same keys move the focus. `karchy-hyprland-window-minimize --down` does what Super+Down does.
- Alt+Tab: `default/hypr/window-switch.lua` keeps the walk (the workspace's windows, last used first, then the ones minimized from it) and switches when Alt is let go. The picture of the windows is the shell plugin `karchy.window-switcher`, which only draws what that file sends it; `karchy plugin disable karchy.window-switcher` turns the picture off and leaves the keys.
- Gaps, corners, transparency and animations have ready-made flags: `karchy hyprland toggle <flag> [on|off|toggle]`. The flag names are the files in `/usr/share/karchy/default/hypr/toggles/`.

## Reload and check

Hyprland reloads when a config file is saved. To force a reload, run `karchy restart hyprctl`.

After every Hyprland edit, run `hyprctl configerrors`. Empty output means the config loaded. If it prints an error, fix it or revert the edit before you report. A Lua syntax error in a user file can leave the session without keybindings, so do not leave a broken file behind.

## The bar and shell plugins

The shell is one Quickshell process: the bar, panels, menu, notifications, lock screen and Settings. Its settings are `~/.config/karchy/shell.json`, laid over `/usr/share/karchy/karchy/shell.json`. The user's file holds only the differences.

Use the commands. They edit `shell.json` and tell the running shell.

| Task | Command |
| --- | --- |
| List plugins and bar widgets | `karchy plugin list` (`--json`) |
| Turn a plugin or widget on or off | `karchy plugin enable <id> [placement]`, `karchy plugin disable <id>` |
| Place or move a widget | `karchy bar put <id> --after <id>`, `karchy bar move <id> --section <section> --index <n>` |
| Set a widget option | `karchy bar set <id> <key> <value>`, read it with `karchy bar get <id> <key>` |
| Bar position, background, style | `karchy bar position`, `karchy bar background`, `karchy bar style`. Without a value each prints the current one |
| Back to the default bar | `karchy bar defaults` |
| Hide or show the bar | `karchy toggle bar [on|off]`. `on` hides it |

`karchy bar --help` lists the sections and placement options. Before `karchy bar defaults`, copy `~/.config/karchy/shell.json`, because the command discards the user's layout.

If you edit `shell.json` by hand, keep it a JSON object and write only differing keys. Objects merge key by key. An array, such as a bar section's widget list, replaces the default list whole.

The clipboard history is the plugin `karchy.clipboard`: a service that records copies, the picker on Super+Ctrl+V and a bar widget in the tray's drawer (the `tray` section). The history is switched off with "Keep a history" in the bar panel, which is `"clipboard": { "history": false }` in `shell.json`; copy and paste keep working. `karchy plugin disable karchy.clipboard` only takes the icon off the bar, and `karchy plugin enable karchy.clipboard` puts it back in the tray's drawer. To put a copy on the clipboard from a script use `wl-copy`, and for files `karchy clipboard copy files <path>...`, which a file manager can paste. A password manager's copy is never in the history, so do not look for one there.

Plugins come from packages only: the built-in ones in `/usr/share/karchy/shell/plugins` and add-on ones in `/usr/share/karchy/plugins`. Do not write a plugin into the home folder. The shell does not load it.

## Restart and talk to the shell

- `karchy restart shell` restarts the shell. It is safe while the screen is locked. Use it after a change the shell did not pick up.
- `karchy shell <target> <method> [args...]` sends an IPC call to the running shell. `karchy shell shell ping` checks that the shell answers.
- The menu's entries are `/usr/share/karchy/default/karchy/karchy-menu.jsonc`. Add the user's entries in `~/.config/karchy/extensions/karchy-menu.jsonc`. The shell reads the file again when it changes. Read the default file for the entry format.
