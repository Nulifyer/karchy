# Karchy

A system menu and toolkit for CachyOS KDE Plasma, inspired by [omarchy](https://github.com/basecamp/omarchy).

Launch everything from a single `Super+Space` menu — apps, package management, web apps, system settings, updates, and more.

## Features

- **App Launcher** — fuzzel-powered app search with KDE integration
- **Package Management** — install/remove packages from pacman and AUR (paru) with fzf search
- **Web Apps** — install web apps from Dashboard Icons, launch in browser app mode, remove with one click
- **Featured Installs** — one-click setup for editors, terminals, AI tools, dev environments, services, and games
- **Development Environments** — Ruby, Node.js, Bun, Deno, Go, PHP, Laravel, Symfony, Python, Elixir, Phoenix, Rust, Java, Zig, .NET, OCaml, Clojure, Scala
- **Dynamic Version Menus** — .NET and Java versions are queried from pacman, not hardcoded
- **System Updates** — update pacman + AUR packages, with a system tray notifier icon
- **Self-Update** — update karchy itself from the menu
- **Cleanup** — remove orphaned packages and clean the package cache
- **Theming** — auto-reads KDE colors or manually override with 10 built-in themes (Catppuccin, Gruvbox, Tokyo Night, Nord, Dracula, etc.)
- **Setup Utilities** — audio, wifi, bluetooth, monitors, DNS, power profiles, screenshots, timezone
- **System Controls** — lock, suspend, hibernate, logout, restart, shutdown

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

This removes all scripts, keybindings, KWin rules, desktop entries, systemd units, and PATH entries.

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

### Themes

Go to **Setup > Theme** to pick a color theme. Choose `auto` to follow your KDE color scheme, or select a hardcoded theme:

Catppuccin Mocha, Gruvbox Dark, Tokyo Night, Nord, Dracula, Solarized Dark, One Dark, Rose Pine, Everforest Dark, Kanagawa
