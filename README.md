# Karchy

A system menu and toolkit for CachyOS KDE Plasma, inspired by [omarchy](https://github.com/basecamp/omarchy).

Launch everything from a single `Super+Space` menu — apps, package management, web apps, dev environments, system settings, updates, and more.

## Features

| | Feature | Description |
|---|---|---|
| 🚀 | **App Launcher** | fuzzel-powered app search with KDE integration |
| 📦 | **Package Management** | Install/remove packages from pacman and AUR (paru) with fzf fuzzy search |
| 🌐 | **Web Apps** | Create desktop shortcuts that launch in browser app mode |
| ⭐ | **Featured Installs** | One-click setup for editors, terminals, AI tools, dev environments, services, and games |
| 🔍 | **Project Discovery** | Scan for projects and open them in your preferred editor |
| 🔄 | **System Updates** | Update pacman + AUR packages, with a system tray notifier icon |
| 🔄 | **Self-Update** | Update karchy itself from the menu |
| 🧹 | **Cleanup** | Remove orphaned packages and clean the package cache |
| 🎨 | **10 Color Themes** | Applied to all menus — Catppuccin, Tokyo Night, Nord, Dracula, and more |
| ⚙️ | **Setup Utilities** | Audio, Wi-Fi, Bluetooth, monitors, DNS, power profiles, screenshots, timezone |
| 🔒 | **System Controls** | Lock, suspend, hibernate, logout, restart, shutdown |

### Dev Environments

All installed via **pacman** or dedicated installers — no version managers needed.

| | Language | Packages |
|---|---|---|
| 💎 | Ruby + Rails | `ruby`, `libyaml`, `gem install rails` |
| 🟢 | Node.js | `nodejs`, `npm` |
| 🍞 | Bun | `bun` |
| 🦕 | Deno | `deno` |
| 🐹 | Go | `go` |
| 🐘 | PHP + Laravel/Symfony | `php`, `composer`, `xdebug` |
| 🐍 | Python + uv | `python`, `uv` |
| 💧 | Elixir + Phoenix | `erlang`, `elixir`, `mix` |
| 🦀 | Rust | `rustup` |
| ☕ | Java (JDK/JRE) | Dynamic — queries pacman for available OpenJDK versions |
| ⚡ | Zig | `zig`, `zls` |
| 🟣 | .NET | Dynamic — queries pacman for available SDK versions |
| 🐫 | OCaml | `opam` |
| 🔵 | Clojure | `clojure`, `rlwrap` |
| 🔴 | Scala | `scala`, `scala3` (AUR) |

### Featured Menu

Editors, terminals, AI tools, dev environments, services, and games — all in one searchable list.

| Category | Items |
|---|---|
| ✏️ Editor | VSCode, Cursor, Zed, Sublime Text, Helix, Emacs |
| 💻 Terminal | Alacritty, Ghostty, Kitty |
| 🤖 AI | Claude Code, Codex, Gemini CLI, LM Studio, Ollama |
| 🛡️ Service | Tailscale, WireGuard, Bitwarden, NordVPN, Dropbox |
| 🎮 Gaming | Steam, RetroArch, Minecraft |

## Requirements

- CachyOS (or Arch Linux) with KDE Plasma 6
- Wayland

## Install

One-liner from GitHub:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Nulifyer/karchy/main/remote-install.sh)
```

Or clone and install manually:

```bash
git clone https://github.com/Nulifyer/karchy.git
cd karchy
bash install.sh
```

This will:
- Install dependencies (fuzzel, gum, alacritty, fzf, chafa, paru-git, etc.)
- Copy scripts to `~/.local/share/karchy/bin` and add to PATH
- Bind `Super+Space` to the karchy menu
- Set up KWin window rules for popups and web apps
- Enable the update notifier tray icon

## Update

From the menu: **Update > Update Karchy**

Or from the command line:

```bash
karchy-self-update
```

## Uninstall

```bash
bash uninstall.sh
```

Removes all scripts, keybindings, KWin rules, desktop entries, systemd units, and PATH entries.

## Usage

Press `Super+Space` to open the menu, or run directly:

```bash
karchy-menu          # main menu
karchy-menu apps     # jump to app launcher
karchy-menu install  # jump to install menu
karchy-menu update   # jump to update menu
karchy-menu setup    # jump to setup menu
karchy-menu remove   # jump to remove menu
karchy-menu system   # jump to system menu
```

### Menu Structure

```
Karchy
├── Apps             — fuzzel app launcher
├── Projects         — scan & open projects in editor
├── Learn            — keybindings, KDE Plasma, Arch Wiki, Bash
├── Setup            — audio, wifi, bluetooth, monitors, power, DNS, theme
├── Install
│   ├── Package      — interactive pacman browser
│   ├── AUR          — interactive paru browser
│   ├── Web App      — create browser app shortcuts
│   ├── Featured     — editors, terminals, AI, dev envs, services, games
│   └── Font         — Nerd Fonts installer
├── Remove
│   ├── Package      — interactive package remover
│   ├── Web App      — remove created shortcuts
│   └── Font         — remove installed fonts
├── Update
│   ├── System       — pacman + AUR upgrade
│   ├── Mirror       — rank fastest mirrors
│   ├── Firmware     — fwupd firmware update
│   ├── Password     — change user password
│   ├── Timezone     — select timezone
│   ├── Hardware     — restart audio, wifi, bluetooth
│   ├── Cleanup      — remove orphans + clean cache
│   └── Karchy       — self-update from GitHub
└── System           — lock, suspend, hibernate, logout, restart, shutdown
```

### Themes

Go to **Setup > Theme** to pick a color theme. Choose `auto` to follow your KDE color scheme, or select a hardcoded theme:

Catppuccin Mocha, Gruvbox Dark, Tokyo Night, Nord, Dracula, Solarized Dark, One Dark, Rose Pine, Everforest Dark, Kanagawa

## License

MIT
