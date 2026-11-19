# Keybindings

karchy has one keybinding system for the whole desktop. Every binding belongs to a layer, and a higher layer wins over a lower one:

| Layer | What it is | Where it lives |
| --- | --- | --- |
| 1 `default` | karchy's own bindings | `/usr/share/karchy/karchy/hypr/bindings.lua`; media, brightness and clipboard keys in `/usr/share/karchy/default/hypr/bindings/` |
| 2 `addon` | an add-on package's bindings (the project picker) | `/usr/share/karchy/hypr.d/<name>.lua` |
| 3 `settings` | the user's changes made in Settings › Keybindings | `~/.config/karchy/keybindings.json` (only the changes), generated into `~/.local/state/karchy/hypr/keybindings.lua` |
| 4 `user` | the user's own file | `~/.config/hypr/bindings.lua`, loaded last |

Never edit layers 1 and 2 (an update replaces them) and never edit the generated Lua. To add or change a shortcut, use `karchy-settings-keybindings`. It validates the keys, checks conflicts, refuses a change that would lock the user out, writes both files and reloads Hyprland. Do not hand-edit Lua for this.

The exception: when the user keeps their own `~/.config/hypr/bindings.lua` with bindings in it and wants the change there, edit that file (see the end), and tell the user that it wins over Settings.

## Read first

```sh
karchy-settings-keybindings list            # a table: group, action, keys, source, and the chain where there is one
karchy-settings-keybindings list --json     # the same, for parsing
```

`list --json` has `rows`, `errors` (a file that failed to load) and `stale` (rules that no longer match anything). Each row:

- `action`: the binding's name. It is how every other subcommand refers to the binding.
- `keys`: the keys in effect, as Hyprland writes them (`SUPER + SHIFT + T`), or `""` when the action is not bound. `labels` is the same as key caps.
- `layer` and `source`: the layer that won, and its name in words (`karchy`, `Project picker`, `Settings`, `your bindings.lua`).
- `state`: `default`, `changed`, `added` (the user's own, made in Settings), `removed` or `yours` (the user's file).
- `chain`: every layer the binding went through, lowest first. Each link has `source`, `keys` and `state`: `wins`, `replaced` or `removed`, with `by` naming the layer that replaced or removed it. Read it as "karchy: Super+Enter (replaced in Settings) → Settings: Super+T (replaced in your bindings.lua) → your bindings.lua: Super+P (wins)".
- `readOnly`: empty when the command can change the row. Otherwise the reason: set in the user's `bindings.lua`, a mouse binding, or owned by another Settings page.
- `conflicts`: other actions on the same keys. Both run when the keys are pressed.
- `what`: the command or target the binding runs.

## Check before you bind

```sh
karchy-settings-keybindings conflicts "SUPER + SHIFT + T"    # JSON: the actions on these keys now; "rows": [] means free
```

Pick free keys. If the user wants keys that are taken, ask which they mean: `--replace` unbinds the other action, `--keep-both` leaves both on the keys. Without either flag the command refuses and names the other action.

## Change

```sh
karchy-settings-keybindings set "Terminal" "SUPER + T"                       # move an action to other keys
karchy-settings-keybindings set "Power menu" "SUPER + F12" --from "SUPER + ESCAPE"   # an action with several bindings: say which
karchy-settings-keybindings add "SUPER + SHIFT + R" --command "footclient ssh my-server" --description "SSH to my server"
karchy-settings-keybindings add "SUPER + SHIFT + SPACE" --action "Menu"      # one more binding for an existing action
karchy-settings-keybindings remove "Screenshot region"                       # unbind it
karchy-settings-keybindings reset "Terminal"                                 # back to karchy's default
karchy-settings-keybindings reset --all                                      # forget every change made in Settings
karchy-settings-keybindings reset --stale                                    # drop rules that match nothing any more
```

Each prints the new list (add `--json`) once Hyprland has reloaded, and the change works at once. A refused change exits 1 with one line on stderr and changes nothing.

Keys: modifiers `SUPER`, `CTRL`, `ALT`, `SHIFT` joined with ` + `, then one key. Letters, function keys and named keys go by name (`T`, `F5`, `RETURN`, `ESCAPE`, `SPACE`, `LEFT`, `PRINT`). The digit row and punctuation go by keycode, so they mean the same key on every layout: `code:10` to `code:19` are 1 to 0, `code:20` is minus, `code:21` is equal. Media keys go by their XF86 name (`XF86AudioMute`).

## Safety rules

- The command refuses to remove the last binding for the menu (Super+Space), a terminal (Super+Return) or Settings › Keybindings (Super+K). Give the action other keys first. Do not work around the refusal by editing files.
- A broken `keybindings.json` is never overwritten: fix or remove the file, then run `karchy-settings-keybindings apply`.
- If the generated file fails to load, Hyprland keeps karchy's defaults and `list` shows the error. `karchy-settings-keybindings apply` writes it again.
- To undo any change: `reset "<action>"`. Tell the user this after a change.

## The user's own bindings.lua

Rows with `source` "your bindings.lua" come from `~/.config/hypr/bindings.lua`. They win over everything, and the command will not change them. Edit that file only when the user asks for the change there, or already keeps bindings in it:

```lua
o.bind("SUPER + SHIFT + R", "SSH", "footclient ssh my-server")          -- add
o.rebind("SUPER + E", "File manager", "karchy-launch-files ~/Projects") -- replace what is on the keys
hl.unbind("SUPER + K")                                                  -- remove what is on the keys
```

- The second argument is the action's name, shown in Settings › Keybindings. Always give one. Use the default's name when you replace a default, so the row keeps its history.
- The third argument is a shell command (a string) or a Hyprland dispatcher such as `hl.dsp.window.close()`.
- `o.bind` on taken keys adds a second action to them. Use `o.rebind` to take the keys over.
- Hyprland reloads when the file is saved (`hyprctl reload` does it by hand). Run `karchy-settings-keybindings list` afterwards and check the row's chain, and `hyprctl configerrors` for a mistake in the file.
- To undo, delete the line.
