# Linutil app catalog (Arch view)

## How checked

- Source: `git clone --depth 1 https://github.com/ChrisTitusTech/linutil`, commit `e272190` (2026-11-14). I read `core/tabs/*/tab_data.toml` for names and categories, then the `pacman)` branch of each install script. Where a script has no `pacman)` branch I recorded what it does instead.
- Repo: `pacman -Si <name>` on this host (CachyOS repos plus core, extra, multilib), run 2026-11-14. "extra, cachyos-extra-v3" means the package is in Arch extra and CachyOS also ships a v3 rebuild. "cachyos" means only the CachyOS repo has it; on stock Arch that package would come from the AUR. Names not in any sync repo were checked with the AUR RPC v5 `info` endpoint. "missing" means neither has that exact name.
- "AUR helper" means Linutil runs `$AUR_HELPER -S`. It uses yay or paru if one is installed, and otherwise builds `yay-bin` first. Many scripts send plain repo packages through the AUR helper too; that works because yay and paru also install from the sync repos.
- On Arch, the Flatpak branch in most scripts is never used; it is the fallback for distros without a native package. I list the Flatpak ID only where Arch actually gets the Flatpak.
- Left out as system setup or out of scope: Grub Theme, Linutil Installer/Updater, Gaming Dependencies, GPU and NVIDIA drivers, Auto Mount Drive, every Security tab item, Monitor Control, User Account Manager, Auto Login, Locale and US Locale Setup, Numlock, Service Manager, SSH Commands, Ramalama Model Manager, Bootable USB Creator and Crypto tool (Linutil's own scripts; their only dependencies are `xz gzip bzip2 jq` and `openssl`), and the game mods (Arc Raiders, D2R loot filter, EverQuest MIDI, Fallout 76, Starfield). Two emulator scripts that are commented out in `tab_data.toml` (PCSX/`pcsxr`, Yabause) and one with no menu entry (Mesen2/`mesen2-git`) are also left out.

109 rows: 107 Linutil menu entries, plus 2 extra rows because the Discord entry offers three variants.

## Applications Setup › Web Browsers

| App | Linutil category | Arch package(s) | Repo | Install method in Linutil | Notes |
|---|---|---|---|---|---|
| Brave | Web Browsers | `brave-bin` (via the `brave-browser` provide) | cachyos | curl installer (`dl.brave.com/install.sh`) | On Arch the Brave script checks `pacman -Ss brave-browser`. If that matches, it runs `pacman -Sy --needed brave-browser`, which resolves to `brave-bin` here; that is a `-Sy` partial-upgrade pattern. Otherwise it installs AUR `brave-bin` with paru, pikaur or yay |
| Brave Origin | Web Browsers | `brave-origin-bin` | cachyos | AUR helper | Menu also offers uninstall |
| Chromium | Web Browsers | `chromium` | extra | pacman | |
| Google Chrome | Web Browsers | `google-chrome` | AUR | AUR helper | Menu also offers uninstall and "remove local AI": it deletes `~/.config/google-chrome/AI` and leaves a `chmod 000` placeholder so the model is not downloaded again |
| Helium Browser | Web Browsers | `helium-browser-bin` | cachyos | AUR helper | Menu also offers uninstall |
| LibreWolf | Web Browsers | `librewolf-bin` | **missing** | AUR helper | `librewolf-bin` no longer exists in the AUR, so this install fails. Use `librewolf` (extra, cachyos-extra-v3) instead |
| Lynx | Web Browsers | `lynx` | extra, cachyos-extra-v3 | pacman | Text-mode browser |
| Mozilla Firefox | Web Browsers | `firefox` | extra, cachyos-extra-v3 | pacman | |
| Thorium | Web Browsers | `thorium-browser-bin` | AUR | AUR helper | AUR version 138, well behind current Chromium (157) |
| Tor Browser | Web Browsers | `torbrowser-launcher` | extra | pacman | The launcher downloads the browser on first run |
| Vivaldi | Web Browsers | `vivaldi` | extra, cachyos-extra-v3 | pacman | |
| waterfox | Web Browsers | `waterfox-bin` | cachyos | AUR helper | |
| Zen Browser | Web Browsers | `zen-browser-bin` | cachyos | AUR helper | |

## Applications Setup › Communication Apps

| App | Linutil category | Arch package(s) | Repo | Install method in Linutil | Notes |
|---|---|---|---|---|---|
| Discord (vanilla, menu choice 1) | Communication Apps | `discord` | extra | pacman | The Discord entry asks which of three variants to install |
| Vesktop (Discord menu choice 2) | Communication Apps | `vesktop-bin` | cachyos | AUR helper | Discord client with Vencord plugins. The AUR also has a source build, `vesktop` |
| Equibop (Discord menu choice 3) | Communication Apps | `equibop-bin` | AUR | AUR helper | Vesktop fork with more plugins |
| Jitsi | Communication Apps | `jitsi-meet-bin` | AUR | AUR helper | |
| Signal | Communication Apps | `signal-desktop` | extra | pacman | |
| Slack | Communication Apps | `slack-desktop` | AUR | AUR helper | |
| Telegram | Communication Apps | `telegram-desktop` | extra | pacman | |
| Thunderbird | Communication Apps | `thunderbird` | extra, cachyos-extra-v3 | pacman | |
| ZapZap | Communication Apps | `zapzap` | AUR | AUR helper | WhatsApp client |
| Zoom | Communication Apps | `zoom` | AUR | AUR helper | |

## Applications Setup › Design Tools

All of these scripts call the AUR helper with `--cleanafter`, including for packages that are in the repos.

| App | Linutil category | Arch package(s) | Repo | Install method in Linutil | Notes |
|---|---|---|---|---|---|
| Ardour | Design Tools | `ardour` | extra, cachyos-extra-v3 | AUR helper | |
| Audacity | Design Tools | `audacity` | extra | pacman | **Broken on Arch:** the script runs plain `pacman` with `--cleanafter`, which pacman rejects ("unrecognized option"). Tested here with `pacman -Sp` |
| Blender | Design Tools | `blender` | extra | AUR helper | |
| Darktable | Design Tools | `darktable` | extra, cachyos-extra-v3 | AUR helper | |
| GNU Image Manipulation Program (GIMP) | Design Tools | `gimp` | extra, cachyos-extra-v3 | AUR helper | |
| Handbrake | Design Tools | `handbrake` | extra, cachyos-extra-v3 | AUR helper | |
| Inkscape | Design Tools | `inkscape` | extra, cachyos-extra-v3 | AUR helper | |
| Krita | Design Tools | `krita` | extra, cachyos-extra-v3 | AUR helper | |
| MyPaint | Design Tools | `mypaint` | extra, cachyos-extra-v3 | AUR helper | |
| Natron | Design Tools | Flatpak `fr.natron.natron` | n/a (AUR has `natron-bin` 2.5.0) | Flatpak, on every distro | The only Flatpak-only app on this tab. The AUR `natron-bin` was last updated in 2022 |
| OBS Studio | Design Tools | `obs-studio` | extra, cachyos-extra-v3 | AUR helper | |
| Olive | Design Tools | `olive` | AUR | AUR helper | AUR package is 0.1.2, the old pre-0.2 release |
| OpenShot | Design Tools | `openshot` | AUR | AUR helper | No longer in the Arch repos |
| Pinta | Design Tools | `pinta` | extra | AUR helper | |
| Scribus | Design Tools | `scribus` | extra, cachyos-extra-v3 | AUR helper | |
| Synfig Studio | Design Tools | `synfigstudio` | extra, cachyos-extra-v3 | AUR helper | |
| Tenacity | Design Tools | `tenacity` | extra, cachyos-extra-v3 | AUR helper | |

## Applications Setup › Developer Tools

| App | Linutil category | Arch package(s) | Repo | Install method in Linutil | Notes |
|---|---|---|---|---|---|
| Cursor | Developer Tools | `cursor-bin` | cachyos | AUR helper | |
| Github Desktop | Developer Tools | `github-desktop-bin` | AUR | AUR helper | |
| JetBrains Toolbox | Developer Tools | `jetbrains-toolbox` | AUR | AUR helper | |
| Meld | Developer Tools | `meld` | extra | pacman | |
| Neovim | Developer Tools | `neovim ripgrep fzf python-virtualenv luarocks go shellcheck git` | all extra or core (most also in cachyos v3 repos) | pacman, then config | Clones `ChrisTitusTech/neovim` to `~/.local/share/neovim`, backs up the old config and links it as `~/.config/nvim` |
| Ngrok | Developer Tools | none (tarball) | n/a (AUR has `ngrok`) | curl download | Extracts `ngrok-v3-stable-linux-amd64.tgz` from bin.equinox.io into `/usr/local/bin` |
| Sublime Text | Developer Tools | `sublime-text-4` | AUR | AUR helper | |
| VS Code | Developer Tools | `visual-studio-code-bin` | AUR | AUR helper | Microsoft build |
| VS Codium | Developer Tools | `vscodium-bin` | AUR | AUR helper | `vscodium` is in cachyos, which needs no AUR build |
| Zed | Developer Tools | `zed` | extra | pacman | |

## Applications Setup › Office Suites

| App | Linutil category | Arch package(s) | Repo | Install method in Linutil | Notes |
|---|---|---|---|---|---|
| FreeOffice | Office Suites | `freeoffice` | AUR | AUR helper | AUR package is flagged out of date |
| LibreOffice | Office Suites | `libreoffice-fresh` | extra, cachyos-extra-v3 | pacman | |
| OnlyOffice | Office Suites | `onlyoffice-bin` | cachyos | AUR helper | |
| WPS Office | Office Suites | `wps-office` | AUR | AUR helper | |

## Applications Setup › PDF Suites

| App | Linutil category | Arch package(s) | Repo | Install method in Linutil | Notes |
|---|---|---|---|---|---|
| Evince | PDF Suites | `evince` | extra, cachyos-extra-v3 | pacman | |
| Okular | PDF Suites | `okular` | extra, cachyos-extra-v3 | pacman | |
| PDF Studio | PDF Suites | none (vendor installer) | n/a (AUR has `pdfstudio-bin` 2024.0.1) | curl installer | Downloads and runs Qoppa's `PDFStudio_linux64.sh`. Commercial software |
| PDF Studio Viewer | PDF Suites | none (vendor installer) | n/a (AUR has `pdfstudioviewer` 2024.0.1) | curl installer | Qoppa's `PDFStudioViewer_linux64.sh`. This entry has no `task_list` in `tab_data.toml` |

## Applications Setup › other top-level entries

| App | Linutil category | Arch package(s) | Repo | Install method in Linutil | Notes |
|---|---|---|---|---|---|
| Alacritty | Applications Setup | `alacritty` | extra, cachyos-extra-v3 | pacman, then config | Downloads `alacritty.toml`, `keybinds.toml` and `nordic.toml` from `dwm-titus` |
| Android Debloater | Applications Setup | `android-tools`, plus the uad-ng binary | extra, cachyos-extra-v3 (AUR has `universal-android-debloater-bin` 1.3.1, the -ng project) | pacman, plus a GitHub binary download | Downloads uad-ng **v1.2.0**, a pinned old release, to `~/uad` |
| Bash Prompt (mybash) | Applications Setup | `bash bash-completion tar bat tree unzip fontconfig git fzf starship zoxide` | all core or extra | pacman, then config | Clones `ChrisTitusTech/mybash`, installs MesloLGS Nerd Font from the nerd-fonts GitHub release, and links the bashrc and `starship.toml`. Falls back to the curl installers for starship and zoxide only if pacman fails |
| Dank Shell | Applications Setup | `dux-shell` (provides and replaces `dms-shell`) | extra, cachyos, cachyos-extra-v3 | curl installer (`install.danklinux.com`) | Desktop shell, so DE-level and probably out of scope. The project has been renamed: the curl script now downloads the `duxinstall` binary from `duxlabs-dev/dux-shell`. Linutil's uninstall removes `dms-shell greetd-dms-greeter-git`, and neither name exists any more |
| Docker | Applications Setup | `docker`, `docker-compose` | extra, cachyos-extra-v3 | pacman | Asks whether to install Docker, Compose or both. Enables and starts `docker.service` and adds `$USER` to the `docker` group (log out and back in) |
| Fastfetch | Applications Setup | `fastfetch` | extra, cachyos-extra-v3 | pacman, then config | Downloads `config.jsonc` from mybash and can add `fastfetch` to the shell rc |
| Flatpak / Flathub | Applications Setup | `flatpak` | extra, cachyos-extra-v3 | pacman | Adds the flathub remote. Apps may not appear until the next login |
| Ghostty | Applications Setup | `ghostty` | extra, cachyos-extra-v3 | pacman | Installs only, with no config, despite the `FM` task flag |
| Kitty | Applications Setup | `kitty` | extra, cachyos-extra-v3 | pacman, then config | Downloads `kitty.conf` and `nord.conf` from `dwm-titus` |
| Noctalia Shell | Applications Setup | `noctalia-shell noctalia-qs` | cachyos | AUR helper | Desktop shell, so DE-level and probably out of scope |
| Podman | Applications Setup | `podman` | extra, cachyos-extra-v3 | pacman | Optionally writes `/etc/containers/registries.conf.d/10-unqualified-search-registries.conf` with docker.io |
| Podman-compose | Applications Setup | `podman-compose` | extra | pacman | |
| Rofi | Applications Setup | `rofi` | extra, cachyos-extra-v3 | pacman | The description promises CTT's dwm-titus config, but the script only installs the package |
| Shelly | Applications Setup | `shelly` | cachyos | AUR helper | Graphical package manager for Arch (pacman systems only). Linutil's uninstall function removes `audacity` instead of `shelly` |
| ZSH Prompt | Applications Setup | `zsh` | extra, cachyos-extra-v3 | pacman, then config | Writes `~/.config/zsh/.zshrc` and appends `export ZDOTDIR=...` to the system-wide `/etc/zsh/zshenv`. Does not change the login shell |

## Gaming › Emulators

| App | Linutil category | Arch package(s) | Repo | Install method in Linutil | Notes |
|---|---|---|---|---|---|
| RetroArch Game Emulator | Emulators › Multi-System | `retroarch retroarch-assets-xmb retroarch-assets-ozone retroarch-assets-glui libretro-core-info` | extra | AUR helper | |
| RetroArch Cores | Emulators › Multi-System | `libretro-beetle-psx libretro-play libretro-ppsspp libretro-nestopia libretro-mesen libretro-mgba libretro-snes9x libretro-mesen-s libretro-bsnes libretro-parallel-n64 libretro-mupen64plus-next libretro-dolphin libretro-melonds libretro-flycast libretro-genesis-plus-gx libretro-kronos libretro-blastem` + `libretro-pcsx2-launcher` | 17 cores in extra, cachyos-extra-v3; `libretro-pcsx2-launcher` is AUR | AUR helper | Requires RetroArch to be installed first. `libretro-pcsx2-launcher` has 1 vote and was last updated in 2020 |
| bsnes | Emulators › Nintendo | `bsnes-hd` | AUR | AUR helper | |
| Dolphin Emulator | Emulators › Nintendo | `dolphin-emu` | extra, cachyos-extra-v3 | AUR helper | |
| Gopher 64 | Emulators › Nintendo | `gopher64` | AUR | AUR helper | |
| MelonDS | Emulators › Nintendo | `melonds-bin` | AUR | AUR helper | |
| mGBA | Emulators › Nintendo | `lua`, `mgba-qt` | extra (lua also cachyos-extra-v3) | AUR helper | |
| Mupen 64 Plus | Emulators › Nintendo | `mupen64plus` | extra, cachyos-extra-v3 | AUR helper | |
| Ryujinx | Emulators › Nintendo | `ryujinx` | cachyos | AUR helper | Switch emulator. The Flatpak fallback is Ryubing |
| snes9x | Emulators › Nintendo | `snes9x-gtk` | extra, cachyos-extra-v3 | AUR helper | |
| PCSX2 | Emulators › PlayStation | `pcsx2` | AUR | AUR helper | Source build |
| Play! | Emulators › PlayStation | Flatpak `org.purei.Play` | n/a (AUR has `play-emu` 0.76) | Flatpak, on every distro | The `pacman)` branch is commented out |
| RPCS3 | Emulators › PlayStation | `rpcs3-bin` | AUR | AUR helper | |
| Blastem | Emulators › Sega | `blastem` | AUR | AUR helper | AUR package is flagged out of date |
| Flycast | Emulators › Sega | `flycast` | AUR | AUR helper | |
| Kronos | Emulators › Sega | `kronos` | AUR | AUR helper | |
| XEMU | Emulators › Xbox | `xemu-bin` | AUR | AUR helper | |
| Xenia | Emulators › Xbox | `xenia-canary-bin` | AUR | AUR helper | Experimental |

## Gaming › Game Launchers

| App | Linutil category | Arch package(s) | Repo | Install method in Linutil | Notes |
|---|---|---|---|---|---|
| Heroic | Game Launchers | `heroic-games-launcher-bin` | cachyos | `git clone` of the AUR repo plus `makepkg -si`, without the AUR helper | Pulls in `base-devel git` if needed |
| Lutris | Game Launchers | `lutris` | extra | pacman | |
| RetroArch | Game Launchers | `retroarch retroarch-assets-xmb retroarch-assets-ozone retroarch-assets-glui libretro-core-info` | extra | pacman | Installs the same packages as the Emulators entry |
| Steam | Game Launchers | `steam` | multilib | pacman | Needs `[multilib]` enabled; the script does not enable it. The Arch "Gaming Dependencies" entry under System Setup covers lib32 and Vulkan |

## Gaming › Tools and Setups

| App | Linutil category | Arch package(s) | Repo | Install method in Linutil | Notes |
|---|---|---|---|---|---|
| Auto CPU Frequency | Tools and Setups | `auto-cpufreq` | cachyos | AUR helper | Disables `power-profiles-daemon` if present and enables `auto-cpufreq.service`. The menu also has tweak and remove options |
| Bottles | Tools and Setups | Flatpak `com.usebottles.bottles` | n/a (AUR has `bottles`) | Flatpak, on every distro | Installs Flatpak and Flathub first if missing |
| ProtonPlus | Tools and Setups | `protonplus`, then `protonplus-bin` | `protonplus`: cachyos; `protonplus-bin`: **missing** | AUR helper, then Flatpak `com.vysp3r.ProtonPlus` | Tries each native name in turn, then falls back to Flatpak |
| ProtonUp-Qt | Tools and Setups | `protonup-qt` | cachyos | AUR helper, then Flatpak `net.davidotek.pupgui2` | |
| Waydroid | Tools and Setups | `waydroid`, `dkms`, `<kernel>-headers` for each installed kernel, `binder_linux-dkms` | `waydroid`: extra; `dkms`: cachyos, extra; `binder_linux-dkms`: AUR | AUR helper plus pacman | Only shown in Wayland sessions, and exits if `lspci` shows any NVIDIA GPU. Runs `modprobe binder-linux` and enables `waydroid-container.service` |

## Utilities

| App | Linutil category | Arch package(s) | Repo | Install method in Linutil | Notes |
|---|---|---|---|---|---|
| CUPS | Printers | `cups` | extra | pacman | Does not enable `cups.service` or `cups.socket` |
| Epson printer drivers | Printers | `epson-inkjet-printer-escpr` | AUR | AUR helper | |
| HP printer drivers | Printers | `hplip` | extra, cachyos-extra-v3 | pacman | |
| Bluetooth Manager | Utilities | `bluez bluez-utils` | extra, cachyos-extra-v3 | pacman | Enables and starts `bluetooth.service`, then opens a menu-driven `bluetoothctl` wrapper |
| Ollama | Utilities | none (upstream install script) | n/a (`ollama` is in extra, cachyos-extra-v3) | curl installer (`ollama.com/install.sh`, run as root) | Starts the `ollama` service. The menu also lists, pulls, runs and removes models |
| Ramalama | Utilities | `ramalama` | extra | AUR helper | Needs Docker or Podman and offers to install either. Option 2 of that prompt is mislabelled "Uninstall Podman" |
| SSH Samba | Utilities | `openssh`, `samba` | `openssh`: core, cachyos-core-v3; `samba`: extra, cachyos-extra-v3 | pacman | Enables `sshd`, `smb` and `nmb`, edits `/etc/samba/smb.conf` and adds a Samba user with `smbpasswd -a` |
| Timeshift Backup | Utilities | `timeshift` | extra, cachyos-extra-v3 | pacman | Hidden on dnf systems |
| WiFi Manager | Utilities | `networkmanager` | extra | pacman | Enables `NetworkManager.service`, then opens a menu-driven `nmcli` wrapper |
