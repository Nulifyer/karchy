# Karchy

A fast, keyboard-driven system utility launcher built with Go and [Bubbletea](https://github.com/charmbracelet/bubbletea).

Summon it with a global hotkey, fuzzy-search your apps and projects, manage packages, install fonts, tweak settings — all from a themed terminal popup.

## Features

- **Global hotkey** (Win+Space) to summon/dismiss
- **Fuzzy search** for apps and projects
- **Package management** — install, remove, update (custom winget integration on Windows)
- **Nerd Font management** — install/remove 71 fonts via oh-my-posh
- **Web app creation** — Chrome/Edge PWA shortcuts with dashboard icons (Windows)
- **WSL management** — launch, install, remove distros (Windows)
- **System settings** — quick access to audio, Wi-Fi, Bluetooth, display, power, timezone
- **10 built-in themes** — Catppuccin Mocha, Gruvbox, Tokyo Night, Nord, Dracula, and more
- **Cross-platform** — Windows, Linux, macOS

## Install

### Windows

```powershell
irm https://raw.githubusercontent.com/Nulifyer/karchy/main/.scripts/install.ps1 | iex
```

### Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/Nulifyer/karchy/main/.scripts/install.sh | bash
```

### Build from Source

```bash
go build -ldflags "-s -w" -o karchy .
./karchy install
```

## Uninstall

### Windows

```powershell
irm https://raw.githubusercontent.com/Nulifyer/karchy/main/.scripts/uninstall.ps1 | iex
```

### Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/Nulifyer/karchy/main/.scripts/uninstall.sh | bash
```

## Usage

| Command | Description |
|---------|-------------|
| `karchy` | Launch the TUI |
| `karchy daemon start` | Start the background daemon (hotkey listener + tray icon) |
| `karchy daemon stop` | Stop the daemon |
| `karchy install` | Register startup, install dependencies, start daemon |
| `karchy uninstall` | Remove startup registration and config |
| `karchy update self` | Update to the latest release |
| `karchy version` | Print version |

## Configuration

Config file: `~/.config/karchy/config.toml` (Linux/macOS) or `%APPDATA%\karchy\config.toml` (Windows)

```toml
[hotkey]
toggle = "Super+Space"

[appearance]
font_family = "CaskaydiaMono NF"
font_size = 13.0

[theme]
name = "catppuccin-mocha"

[terminal]
app = "alacritty"

[projects]
editor = "code"
dirs = ["~/Projects"]
```

## Themes

| Theme | |
|-------|---|
| catppuccin-mocha | Default |
| gruvbox-dark | |
| tokyo-night | |
| nord | |
| dracula | |
| solarized-dark | |
| one-dark | |
| rose-pine | |
| everforest-dark | |
| kanagawa | |

## Dependencies

- [Alacritty](https://alacritty.org/) — terminal emulator (provides borderless themed window chrome)
- [oh-my-posh](https://ohmyposh.dev/) — Nerd Font installer (Windows only, optional)

## License

[MIT](LICENSE)
