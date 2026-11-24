# Using karchy

A short guide to the things you do in the first days. `Super` is the Windows key.

## First keys

| Keys | What they do |
| --- | --- |
| `Super` + `Space` | The menu. Type to search apps, menu rows and Settings pages |
| `Super` + `Return` | Terminal |
| `Super` + `E` | Files |
| `Super` + `K` | Every keybinding, and the editor to change them |
| `Alt` + `F4` | Close the window |
| `Super` + `Up` / `Down` | Maximize / restore or minimize |
| `Super` + `1` … `0` | Go to a workspace. With `Shift`, take the window along |
| `Super` + `Shift` + `S` | Screenshot of a region |
| `Super` + `L` | Lock |
| `Super` + `Escape` | Power menu: lock, suspend, log out, restart, shut down |

[Keybindings](keybindings.md) has the complete list.

## The menu

`Super` + `Space` opens the menu. Typing searches at once: installed apps, the menu's own rows, and every Settings page.

| Row | What it holds |
| --- | --- |
| Apps | Your installed apps |
| Packages | Quick Install, Install Package, Remove Package, web apps |
| Recording | Record the screen, with or without sound, microphone and webcam |
| Keybinds | Opens Settings › Keybindings |
| Update | Opens the Updates window |
| Settings | Opens Settings |
| Reload | Restart one part of the desktop: shell, Hyprland, audio, Wi-Fi, Bluetooth, trackpad |
| Power | Lock, suspend, hibernate, log out, restart, shut down |

## Settings

Settings is one window. Open it from the menu, or type what you look for in the menu's search ("wifi", "monitor", "timezone").

Its pages:

- Network, Bluetooth, Displays, Sound, Input, Keybindings
- Appearance, Fonts, Notifications, Default apps
- Power, Storage, Date & Time
- Users, Security, SSH & Git
- About

The bar has quick panels for the things you change often: sound, microphone, network, Bluetooth, brightness and power. Click an icon to open its panel.

## Windows and workspaces

- New windows tile: they share the workspace without overlapping. `Super` + `T` makes one window float.
- **Settings › Appearance › Workspace layout** chooses whether new workspaces tile or float. On a floating workspace windows overlap as on Windows: each has a title bar with minimize, maximize and close, a click brings a window to the front, and a dialog stays in front of its app.
- `Super` + `Left` / `Right` moves the focus. With `Shift`, the arrows swap windows.
- `Alt` + `Tab` goes back to the window you used last; keep `Alt` down and press `Tab` again to go further back. `Super` + `Tab` goes to the next workspace.
- `Super` + `M` minimizes every window on the workspace. `Super` + `Shift` + `M` brings them back.

## Install and remove apps

**Quick install** (menu › Packages › Quick Install) lists about 720 apps, fonts and optional features by category. Select what you want and press Install; installed apps show as installed, and you remove them the same way.

- Apps from the signed repositories install in the window, with progress for each.
- Apps from the AUR are built on your computer from a community script. They install in a terminal, where you can read the build files first.
- Optional features, under **System features**: Printers & scanners, Containers and Virtual machines.

For anything not in the list, use menu › Packages › **Install Package**, which searches every package in the repositories and the AUR. **Remove Package** lists what you installed.

In a terminal, `pacman` and `paru` work as on any Arch system.

## Update

Open the Updates window (menu › Update, or the bar's update icon) and press **Install**, or run `karchy update` in a terminal.

1. karchy first shows what would change: each package with its old and new version, the download size, whether a restart is needed, and Arch's news since your last update.
2. Nothing is installed until you agree.
3. One pass updates karchy, the system packages and your AUR packages, with a snapshot before and after.

If an update breaks something, start the snapshot from before it: see [An update broke the system](recovery.md#an-update-broke-the-system).

### Release channels

karchy's own packages come from one channel. The rest of the system is the same on every channel.

| Channel | What you get |
| --- | --- |
| stable | Releases |
| rc | Release candidates as well as releases |
| nightly | Every change, as it is made |

Change the channel in the Updates window, or with `karchy channel set <stable|rc|nightly>`. `karchy channel` shows the current one. Moving to an older channel installs that channel's versions, even though they are older.

## Look and themes

- **Settings › Appearance › Theme** switches the theme. One switch recolors the desktop, terminals, GTK and Qt apps, VS Code, btop, the browser and the shell prompt.
- **Settings › Fonts** sets the interface font, the monospace font and the text size.

In a terminal: `karchy theme list` and `karchy theme set "<name>"`.

## Change the keys

**Settings › Keybindings** (`Super` + `K`) lists every binding with its keys and where it comes from. You can search by name or by pressing keys, change, add, remove and reset a binding. It warns before two actions get the same keys.

## Your own config files

karchy's defaults are in `/usr/share/karchy`, and updates replace them. Your changes go in your home folder, which updates never rewrite:

- `~/.config/hypr/` for Hyprland: windows, monitors, and your own keys in `bindings.lua`
- `~/.config/karchy/shell.json` for the shell: the bar's layout, panels and their options

Where a Settings page has a file of yours behind it, the page links the file, and your file wins over the window. Write only what you want to differ from the defaults, so the rest keeps following them.

## More than one person

The installer makes one account, an administrator. Add the others in **Settings › Users**. Each person gets a home folder nobody else can open. The same page changes a name or role, resets a password and removes an account. Removing an account deletes its home folder for good, so copy what should be kept first.

What you see when the computer starts:

| Install | One person | More than one |
| --- | --- | --- |
| Encrypted | The disk password, then the desktop. "Log in automatically" on the Users page can turn that off | The disk password, then the login screen, where each person signs in |
| Not encrypted | The login screen | The login screen |

On an encrypted install, everyone who starts the computer has to know the disk password, which is the first person's install password. When you add a second person, change your own login password in **Settings › Security**, so that it differs from the disk password. **Settings › Security › Drive password** changes the disk password itself.

Each person's saved passwords stay their own. If someone forgets a password, see [Someone can't sign in](recovery.md#someone-cant-sign-in).

## Networks you trust

karchy treats a network as untrusted until you mark it as trusted in **Settings › Network**.

- The firewall refuses incoming connections on every network.
- On an untrusted network, DNS goes to Quad9 over an encrypted connection, and file sharing with LocalSend stays closed.
- On a trusted network, such as your home, LocalSend's port opens so nearby devices can send you files.

## Snapshots

karchy takes a snapshot of the system before and after every package change. The boot menu lists them under **Snapshots**, and you can start any of them and make it permanent. Your home folder is not part of a snapshot, so your files stay as they are.

[When karchy does not boot](recovery.md) explains how to use them, and what else to do when something goes wrong.

## Help from an AI agent

karchy installs [Agent Skills](https://agentskills.io) that tell an AI coding agent how this system works, in `~/.agents/skills`. Claude Code, Codex, Gemini CLI and other agents read them from there. An agent then makes a small change directly and tells you how to undo it, and plans with you and takes a snapshot before a large one.

## Commands

Everything in Settings and the menu is also a command.

```sh
karchy                    # lists the command groups
karchy <group> --help     # lists a group
karchy commands           # lists every command with a one-line summary
```
