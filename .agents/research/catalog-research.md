# karchy Settings › Install: quick-install catalog research

Date: 2026-11-14. Research only: nothing was installed and the karchy repo was not edited.

## How this was checked

- **Omarchy**: `reference/omarchy-v4.5.0`. I read `bin/omarchy-install-*`, `omarchy-remove-*`, `omarchy-install-dev-env`, `omarchy-install-browser`, the Install/Remove tree in `default/omarchy/omarchy-menu.jsonc`, `install/config/{docker,firewall}.sh`, `install/hardware/nvidia.sh`, and `audit/04-features-apps.md`. I also downloaded `omarchy.db` from `pkgs.omarchy.org/stable/x86_64` to list which packages `[omarchy]` actually builds; karchy has that repo enabled.
- **CachyOS (this host)**: `/usr/lib/cachyos-pi/pkglist.yaml` (the Package Installer's whole catalog), strings from `/usr/bin/cachyos-hello` (its Apps/Tweaks/Fixes actions), `pacman -Si` on the gaming meta packages, the `cachyos-settings` file list, and the chwd profiles in `/var/lib/chwd/db/pci/*/profiles.toml`. Wiki pages read: Gaming, General system tweaks, and QEMU/VMM setup.
- **Package names**: about 330 candidates were checked with `pacman -Si`, plus the AUR RPC for the ones the sync repos lack. Arch file lists (archlinux.org JSON) were used to see which units, udev rules and ufw profiles each package ships. The Arch wiki was not readable (bot wall), so the libvirt and ufw notes come from libvirt's and CachyOS's docs and from package contents.

**Repository notation.** karchy has only the generic `[cachyos]` repository, not the `-v3` ones; it is listed before `[core]`. Then come `[core]`, `[extra]`, `[multilib]` (only once Gaming turns it on), then `[omarchy]` and `[karchy]`. Packages that this host shows in `cachyos-extra-v3,extra` therefore come from **[extra]** on karchy. Where `[cachyos]` and `[omarchy]` both carry a package (for example `claude-code` and `brave-bin`), pacman takes `[cachyos]`, because it comes first.

**Legend.** ⚙ = needs a setup script (install/remove/status), like `karchy-feature-printing`. Blank = plain package entry. "Source" says who offers it: **O** Omarchy, **C** CachyOS (Package Installer, Hello, wiki, chwd), **A** the user's usage audit, **N** new suggestion.

---

## 1. Merged catalog

### 1.1 Gaming

| Entry | Installs (repo) | Setup? | Source |
|---|---|---|---|
| **Steam** ⚙ | `steam` [multilib] plus the matching 32-bit GPU driver: NVIDIA `lib32-nvidia-utils` [cachyos] (pins `nvidia-utils=620.70.06`); AMD `vulkan-radeon lib32-vulkan-radeon lib32-mesa` [cachyos]; Intel `vulkan-intel lib32-vulkan-intel` | Enable `[multilib]`; install the driver in the same transaction as steam (not after it); optional shader-cache env file; optional ufw Steam profile on trusted networks only | O, C, A |
| Game tools: GameMode ⚙ | `gamemode lib32-gamemode` [extra]/[multilib] | Add the user to the `gamemode` group (the polkit rule for its CPU/GPU helpers checks that group) | C (wiki), N |
| Game tools: MangoHud, GOverlay | `mangohud lib32-mangohud goverlay` [extra]/[multilib] | none (`mangohud --dlsym %command%`) | C, A |
| Game tools: Gamescope | `gamescope` [cachyos] | none (wrapper) | C, A |
| Game tools: vkBasalt | `vkbasalt lib32-vkbasalt` (AUR) | none | A |
| NTSync autoload | `ntsync-autoload` [extra] (both karchy kernels provide `NTSYNC-MODULE`) | none; loads `ntsync` at boot. CachyOS does this through `cachyos-settings` | C, N |
| Proton-CachyOS | `proton-cachyos-slr` [cachyos] | none (pick it per game in Steam) | C, A |
| Proton-GE / Proton manager | `protonup-qt` or `protonplus` [cachyos]; `proton-ge-custom-bin` (AUR) | none | C (wiki), O (uses GE-Proton for Battle.net) |
| Wine helpers | `protontricks winetricks` [extra], `umu-launcher` [cachyos], `wine-cachyos-opt` [cachyos] | multilib | C (meta), A |
| CachyOS gaming bundle (all of the above) | `cachyos-gaming-meta` [cachyos]; `cachyos-gaming-applications` adds steam, lutris, heroic, faugus, gamescope, mangohud, goverlay | multilib plus driver first (same as Steam) | C (Hello "Install gaming packages") |
| Lutris ⚙ | `lutris umu-launcher wine-staging winetricks` [extra]/[cachyos] | multilib plus lib32 driver | O, C |
| Heroic (Epic/GOG/Amazon) | `heroic-games-launcher-bin` [cachyos]/[omarchy], or `heroic-games-launcher` [cachyos] | multilib plus lib32 driver | O, C |
| Faugus Launcher | `faugus-launcher` [cachyos] | multilib | C |
| Bottles | `bottles` (AUR; upstream recommends Flatpak) | none (or via Flatpak) | C (wiki mention), N |
| Battle.net ⚙ | `umu-launcher` plus a GE-Proton prefix in `~/Games/battlenet` | Download the installer and run it under umu; write a .desktop file | O |
| RetroArch ⚙ | `retroarch`, assets and about 40 `libretro-*` cores [extra], some `-git` cores from [omarchy] | Writes `~/.config/retroarch/retroarch.cfg` paths, Vulkan, `~/Games/{roms,bios}` | O |
| Minecraft | `prismlauncher` [extra] or `minecraft-launcher` ([omarchy]/AUR) | none | O, N |
| GeForce NOW ⚙ | Flatpak (NVIDIA's `GeForceNOWSetup.bin`) | needs Flatpak | O |
| Xbox Cloud Gaming | web app | web app | O |
| Xbox controllers ⚙ | `xpadneo-dkms` [cachyos]/[omarchy] plus `linux-cachyos-headers linux-cachyos-lts-headers` [cachyos] | DKMS needs headers for both karchy kernels; blacklist `xpad`; load `hid_xpadneo`; add the user to `input` | O |
| Controller udev rules | `steam-devices` (pulled in by steam); `game-devices-udev` (AUR) for other pads | udev reload | N |
| Sunshine (stream this PC) ⚙ | `sunshine` [cachyos]/[omarchy] | user service, ufw ports (LAN and tailnet only), admin web app | O |
| Moonlight (stream client) | `moonlight-qt` [extra] | none | O |
| Gamescope session | `gamescope-session-cachyos` [cachyos] | session entry | C. **Skip**: karchy logs in with greetd straight into one uwsm session |

### 1.2 Virtualization and containers

| Entry | Installs (repo) | Setup? | Source |
|---|---|---|---|
| **Virtual machines** ⚙ | `qemu-desktop libvirt virt-manager dnsmasq edk2-ovmf swtpm` [extra] (optional `virt-viewer`) | socket units, `libvirt` group, default network, libvirt firewall backend plus ufw route rules, a no-copy-on-write image directory outside snapper | C (pi lists virt-manager; wiki), A |
| GNOME Boxes | `gnome-boxes` [extra] | none (user-session libvirt) | C (pi) |
| VirtualBox | `virtualbox virtualbox-host-dkms` [extra] plus both header packages | DKMS, `vboxusers` group | C (pi). **Skip**: conflicts with KVM in use |
| Windows apps: Omarchy Windows VM ⚙ | Docker plus the `dockurr/windows` image plus `freerdp` | Docker, root-owned compose, RDP launcher | O |
| Windows apps: WinBoat ⚙ | `winboat` [cachyos] plus `docker docker-compose` | Docker with the user in the `docker` group, KVM | C (Hello "Install Winboat") |
| **Podman** ⚙ | `podman podman-compose` [extra] (crun, passt, netavark come as deps); optional `podman-docker`, `podman-desktop`; on NVIDIA `nvidia-container-toolkit` [extra] | check subuid/subgid, user `podman.socket`, short-name registry drop-in | C (pi: `podman-docker podman-compose crun`), A |
| **Docker** ⚙ | `docker docker-compose docker-buildx` [extra], `ufw-docker` ([omarchy]/AUR) | `docker.socket`, group choice, ufw-docker rules, daemon.json | O (base), C (pi: `docker docker-compose`) |
| Distrobox | `distrobox` [extra] | needs Podman | N |
| Dev databases in containers ⚙ | containers only (MySQL, Postgres, MariaDB, Redis, Mongo, MSSQL) | `podman run …` bound to 127.0.0.1 | O (`omarchy-install-docker-dbs`); port it to Podman |
| lazydocker | `lazydocker` [extra] | none (works with Podman through `DOCKER_HOST`) | O |
| GPU in containers | `nvidia-container-toolkit` [extra] | none now: the package enables `nvidia-cdi-refresh.path`, which writes the CDI spec under `/var/run/cdi` | A |

### 1.3 Developer toolchains (pacman/AUR, no mise)

| Entry | Installs (repo) | Setup? | Source |
|---|---|---|---|
| .NET SDK | `dotnet-sdk` [extra] (10.0.14, 1xx band) or `dotnet-sdk-bin` [cachyos] (10.0.15, 4xx band) | none (`~/.dotnet/tools` on PATH is optional) | O (mise), A |
| Go | `go gopls` [extra] | none (`~/go/bin` on PATH is optional) | O, A |
| **Rust** ⚙ | `rustup` [extra] (conflicts with `rust`), `clang` for bindgen | Run `rustup default stable` as the user; optionally add `rust-analyzer` and `rust-src` | O (curl installer), A |
| Zig | `zig zls` [extra] | none. **Warning**: the repo has `zig 0.17.1` but `zls 0.15.1`, and zls must match zig's version | O, A |
| Bun | `bun` [extra] (also `bun-bin` [omarchy]/AUR) | none | O, A |
| Deno | `deno` [extra] | none | O, A |
| Java/Kotlin | `jdk-openjdk` (27) or `jdk21-openjdk` (LTS), `kotlin gradle maven` [extra] | `archlinux-java` if more than one JDK | O, A |
| Python | `uv python-pipx pypy3` [extra] | none | O, A |
| Node.js | `nodejs npm pnpm` [extra] | optional `npm config set prefix ~/.local` for global installs | O, A |
| Ruby on Rails | `ruby libyaml` [extra] plus `gem install rails` | user gem install | O |
| PHP / Laravel / Symfony | `php composer` [extra], `symfony-cli` ([omarchy]/AUR) | composer global bin dir | O |
| Elixir / Phoenix | `elixir erlang` [extra] plus `mix local.hex`, `phx_new` | user mix archives | O |
| OCaml | `opam ocaml` [extra] plus `opam init` | user init | O |
| Clojure / Scala | `clojure leiningen rlwrap` [extra]; `scala-cli` (AUR) | none | O |
| GitHub CLI ⚙ | `github-cli` [extra] | `gh auth login` (git's credential helper on this host points at gh) | O (mise), A ("day one") |
| CLI dev tools | `lazygit shellcheck actionlint cmake ninja` [extra] | none | A |
| Android | `android-tools scrcpy` [extra]; `android-studio` (AUR) | none | A, C (pi: scrcpy) |
| Reverse engineering, Odin | `ghidra odin` [extra] | none | A |
| JetBrains Toolbox | `jetbrains-toolbox` (AUR) | none | N |

### 1.4 Editors and diff tools

| Entry | Installs (repo) | Setup? | Source |
|---|---|---|---|
| Zed | `zed` [extra] | none (Omarchy adds its own `omazed` theme) | O, A |
| Helix / Neovim / Vim / Emacs | `helix neovim vim emacs` [extra] | none | O, C (pi: vim, emacs) |
| Sublime Text 4 | `sublime-text-4` ([omarchy]/AUR) | none | O |
| Cursor | `cursor-bin` [cachyos]/[omarchy] | none | O |
| Code - OSS | `code` [extra] | none (VS Code proper is already in base) | C (pi) |
| Meld | `meld` [extra] | none | A |
| Beyond Compare | `bcompare` (AUR) | none | A |

### 1.5 AI tools

| Entry | Installs (repo) | Setup? | Source |
|---|---|---|---|
| Claude Code | `claude-code` [cachyos] (also [omarchy]) | none | O (mise), A |
| Codex CLI | `openai-codex` [extra] (or `openai-codex-bin` [omarchy]/AUR) | none | O, A |
| OpenCode | `opencode` [extra] | none | O, A |
| pi | `pi-coding-agent-bin` (AUR) | none | O (mise), A |
| T3 Code | `t3code-bin` ([omarchy]/AUR) | none (Omarchy uses the self-updating AppImage instead) | O, A |
| Claude Desktop | `claude-desktop` [cachyos]/[omarchy] | none | O |
| ChatGPT/Codex Desktop | `openai-codex-desktop` [omarchy] | none | O |
| LM Studio | `lmstudio-bin` ([omarchy]/AUR) | none | O |
| Ollama ⚙ | `ollama-cuda` (NVIDIA) or `ollama-vulkan`/`ollama-rocm` (AMD) [extra] | `systemctl enable --now ollama.service` | O, C (chwd ai_sdk) |
| CUDA/ROCm AI SDK | chwd's `nvidia-ai-sdk` set: `cuda cudnn nccl python-pytorch-opt-cuda …` | none | C. **Skip**: several GB; install by hand |

### 1.6 Browsers

The setup Omarchy does for every Chromium-family browser is: create the policy directory, copy the flags file, apply the theme, and for Brave link Widevine. karchy already has `karchy-theme-set-browser(-policy)` for Chromium, Chrome, Edge and Brave.

| Entry | Installs (repo) | Setup? | Source |
|---|---|---|---|
| Firefox | `firefox` [extra] | policies file (Omarchy) | O, C |
| Chromium | `chromium` [extra] | policy dir plus theme | O, C |
| Google Chrome | `google-chrome` ([omarchy]/AUR) | policy dir plus theme | O |
| Brave | `brave-bin` [cachyos]/[omarchy] | policy dir, theme, Widevine link | O, C, A |
| Zen | `zen-browser-bin` [cachyos]/[omarchy] | policies file | O |
| Microsoft Edge | `microsoft-edge-stable-bin` ([omarchy]/AUR) | policy dir plus theme | O |
| Helium | `helium-browser-bin` ([omarchy]/AUR) | none | O (`karchy-launch-webapp` already accepts it) |
| Vivaldi | `vivaldi` [extra] | none | C |
| Mullvad Browser | `mullvad-browser-bin` [cachyos] | none | C (repo), N |
| Tor Browser | `torbrowser-launcher` [extra] | none | C |
| ungoogled-chromium, Floorp | `ungoogled-chromium-bin`, `floorp-bin` [cachyos] | none | C |
| LibreWolf | **not in the repos or the AUR** (`librewolf`/`librewolf-bin` both missing) | — | C (pi lists it; the entry is stale) |

### 1.7 Communication, passwords, VPN

| Entry | Installs (repo) | Setup? | Source |
|---|---|---|---|
| Signal | `signal-desktop` [extra] | none | O, C |
| Discord / Vesktop | `discord` [extra]; `vesktop-bin` [cachyos] | none | C, A (as a web app) |
| Telegram, Element | `telegram-desktop element-desktop` [extra] | none | C |
| Slack | `slack-desktop` ([omarchy]/AUR) | none | O |
| Zoom | `zoom` (AUR), or a web app | none | O (web app) |
| Thunderbird | `thunderbird` [extra] | none | C |
| Proton Mail / Bridge | `proton-mail-bin` [cachyos], `protonmail-bridge` [extra] | none | N |
| **Proton Pass** | `proton-pass` [cachyos] (also `proton-pass-bin` AUR) | none | A |
| 1Password ⚙ | `1password 1password-cli` ([omarchy]/AUR) | Chromium external-extension JSON (Omarchy) | O |
| Bitwarden, KeePassXC | `bitwarden keepassxc` [extra] | none | O |
| Proton VPN | `proton-vpn-gtk-app` [extra] | none | N |
| Mullvad VPN ⚙ | `mullvad-vpn` [extra] | enable the daemon (I could not read the unit name from the file list; check `pacman -Ql mullvad-vpn`) | N |
| NordVPN ⚙ | `nordvpn-bin` ([omarchy]/AUR) | `nordvpnd`, `nordvpn` group, reboot | O |
| WireGuard tools | `wireguard-tools` [extra] | none (NetworkManager imports configs) | N |
| **Tailscale** ⚙ | `tailscale` [extra] (optional GUI `trayscale`/`ktailctl`, AUR) | `tailscaled`, `tailscale up`, operator, ufw on `tailscale0` | O, A (homelab) |

### 1.8 Sync, backup, remote

| Entry | Installs (repo) | Setup? | Source |
|---|---|---|---|
| **Syncthing** ⚙ | `syncthing` [extra], optional `syncthingtray` [extra] | user service, ufw profile `syncthing` on trusted networks, admin web app | N (karchy phase 7 backup) |
| Nextcloud client | `nextcloud-client` [extra] | none | C |
| Dropbox ⚙ | `dropbox dropbox-cli` ([omarchy]/AUR) | start the daemon; tray | O |
| RustDesk | `rustdesk` [omarchy] or `rustdesk-bin` (AUR) | none (client use) | A |
| Remmina, FileZilla | `remmina filezilla` [extra] | none | C |
| Backup tools | `restic borg rclone pika-backup vorta` [extra], `kopia` [cachyos] | none, or the planned phase-7 NAS backup feature | N |

### 1.9 Media, creative, office

All of these are plain packages from [extra] unless noted. Source is C (Package Installer) unless noted.

| Entry | Installs (repo) |
|---|---|
| OBS Studio | `obs-studio` [extra] or `obs-studio-browser` [cachyos] (CachyOS wiki prefers the latter: CUDA and virtual-camera fixes) |
| Video editing | `kdenlive shotcut handbrake` |
| Graphics | `gimp inkscape krita blender darktable` |
| Audio | `audacity`; `easyeffects` (C wiki, laptop speakers) |
| Players | `vlc` (mpv is already in base) |
| Spotify | `spotify` ([omarchy]/AUR), `spotify-launcher` [extra], or a web app (O) |
| Obsidian | `obsidian` [extra] (A; theme sync was dropped in D-48) |
| LibreOffice | `libreoffice-fresh` |
| OnlyOffice | `onlyoffice-bin` [cachyos] |
| Notion | `notion-desktop` [omarchy] (O) |
| qBittorrent | `qbittorrent` |

### 1.10 Hardware and monitoring

| Entry | Installs (repo) | Setup? | Source |
|---|---|---|---|
| **OpenRGB** ⚙ | `openrgb` [extra], optional `i2c-tools` | The package ships `60-openrgb.rules`, `modules-load.d/openrgb.conf` (`i2c-dev`) and `openrgb.service`. The script reloads udev, loads `i2c-dev` now, and optionally enables the server for boot-time profiles | A (K95, AURA), N |
| ckb-next (Corsair) ⚙ | `ckb-next` [extra] | `ckb-next-daemon.service` | A (K95) |
| CoolerControl ⚙ | `coolercontrol` [extra] (needs `coolercontrold`) | `coolercontrold.service` | N |
| LACT (GPU control) ⚙ | `lact` [extra] | `lactd.service` | N |
| liquidctl, nvtop | `liquidctl nvtop` [extra] | none | N |
| Piper (gaming mice) | `piper` [extra] | none (`ratbagd` starts on demand over D-Bus) | N |
| Solaar (Logitech) | `solaar` [extra] | none (udev rules shipped) | N |
| OpenCL on NVIDIA | `opencl-nvidia` [cachyos] (`lib32-opencl-nvidia` comes with Gaming) | none | A, C (chwd) |
| Audio mixer | `pavucontrol` [extra] | none | A |
| Disk usage | `baobab` or `gdu` [extra] | none | A |

### 1.11 CachyOS system tweaks (Hello's "Tweaks" page)

| Entry | Installs (repo) | Setup? | Source |
|---|---|---|---|
| ananicy-cpp ⚙ | `ananicy-cpp` [extra], `cachyos-ananicy-rules` [cachyos] | `ananicy-cpp.service`. The CachyOS wiki says not to combine it with GameMode | C (Hello tweak), A |
| Profile-sync-daemon ⚙ | `profile-sync-daemon` [extra] | user `psd.service`; browser profiles in RAM | C (Hello tweak) |
| bpftune ⚙ | `bpftune-git` [cachyos] | `bpftune.service` | C (Hello tweak) |
| sched-ext schedulers ⚙ | `scx-scheds` [extra], `scx-tools` (scx_loader) [extra], `scx-manager` GUI [cachyos] | `scx_loader.service` plus `/etc/scx_loader.toml` | C (Kernel Manager) |
| VRAM management | `dmemcg-booster` [cachyos] (and KDE-only `plasma-foreground-booster`) | service | C (Hello). **Skip**: experimental, and the booster half is Plasma-only |
| Encrypted DNS ⚙ | none (systemd-resolved drop-in with DoT, or an NM connection setting) | a resolved drop-in | C (Hello DNS page), N |
| `cachyos-settings` | — | — | C. **Do not install**: it depends on `zram-generator` and ships `zram-generator.conf`, which fights karchy's zswap plus swap file (see section 4) |

### 1.12 Fonts and terminals

| Entry | Installs (repo) | Setup? | Source |
|---|---|---|---|
| Nerd Fonts (Cascadia, Meslo, Fira Code, Victor, Bitstream Vera, Iosevka) | `ttf-{cascadia-mono,meslo,firacode,victor-mono,bitstream-vera-mono,iosevka}-nerd` [extra] | optionally `karchy-font-set` | O, A |
| Liberation / MS core fonts | `ttf-liberation` [extra]; `ttf-ms-fonts` (AUR) | none | A (audit suggests adding Liberation to base), C (gaming meta) |
| kitty / Alacritty / Ghostty / WezTerm | `kitty alacritty ghostty wezterm` [extra] | optionally set as default (`karchy-default-terminal`) | O, A |

### 1.13 Platform features

| Entry | Installs (repo) | Setup? | Source |
|---|---|---|---|
| **Flatpak + Flathub** ⚙ | `flatpak` [extra], optional `flatseal`/`warehouse` [extra] | Check the Flathub remote, relogin for XDG_DATA_DIRS, GTK theme override | O (only as a GeForce NOW dependency), A |
| **Web apps** ⚙ | none (`karchy-webapp-install`, already in karchy) | writes a `.desktop` file plus icon; remove with `karchy-webapp-remove` | O, A |
| SSH server | already karchy (`karchy-setup-security-sshd`) | — | O |

---

## 2. Things both Omarchy and CachyOS offer: side by side

### 2.1 Steam and gaming

- **Omarchy.** `omarchy-install-gaming-steam` runs `omarchy-install-gaming-gpu-lib32` first. That script picks `lib32-vulkan-radeon` and/or `lib32-vulkan-intel` from `lspci`, and `lib32-nvidia-utils` (or `lib32-nvidia-580xx-utils` for cards without GSP), then installs `steam`. Multilib is always on in Omarchy's pacman.conf. The script explains the ordering: `--noconfirm` resolves `lib32-vulkan-driver` to its first provider, which is the NVIDIA one, so installing Steam first would pull the NVIDIA stack onto AMD machines. There is no gamemode, mangohud, gamescope or Proton fork. Separate installers cover Lutris, Heroic, Battle.net, RetroArch, Xbox controllers, Sunshine and GeForce NOW.
- **CachyOS.** Hello's "Install gaming packages" button installs `cachyos-gaming-meta` and `cachyos-gaming-applications`. Together they bring proton-cachyos-slr, wine-cachyos-opt, umu, protontricks, winetricks, lib32 audio and OpenCL loaders, and Steam, Lutris, Heroic, Faugus, gamescope, mangohud and goverlay. The lib32 GPU driver comes from chwd at install time: every chwd GPU profile already lists `lib32-mesa`/`lib32-vulkan-*` or `lib32-nvidia-utils`. `cachyos-settings` loads `ntsync` and ships the `game-performance` wrapper.
- **What matters for karchy:**
  - CachyOS's bundle is complete but heavy (three launchers plus wine-cachyos), and it assumes chwd already put the lib32 drivers in place. karchy has no multilib and no lib32 drivers.
  - `game-performance` is a trap on karchy. It lives in `cachyos-settings`, and it exits with an error if neither `powerprofilesctl` nor `tlpctl` is present. karchy installs power-profiles-daemon only on machines with a battery, so on the NVIDIA desktop `game-performance %command%` would fail to start the game.
  - Omarchy's driver-first pattern is the right core. CachyOS's repo gives the matching `lib32-nvidia-utils` (same version as `[cachyos]` nvidia-utils, with a strict `nvidia-utils=620.70.06` dependency) and `lib32-mesa` at epoch 3, which matches `[cachyos]` mesa.
- **Recommendation.** One **Gaming** ⚙ feature built on Omarchy's pattern:
  1. Enable multilib.
  2. Install the GPU-matched lib32 driver together with `steam`.
  3. Add CachyOS's best pieces as default-on sub-items: `proton-cachyos-slr`, `gamemode lib32-gamemode`, `mangohud lib32-mangohud`, `gamescope`, `ntsync-autoload`, `protontricks`.

  Offer Lutris, Heroic, Faugus, wine-cachyos and the full `cachyos-gaming-meta` as separate ticks. Use GameMode instead of `game-performance`, and don't pull in `cachyos-settings`.

### 2.2 Virtual machines and Windows apps

- **Omarchy.** No libvirt or virt-manager at all. Windows comes through `omarchy-windows-vm`, a 1625-line script that runs the `dockurr/windows` image under Docker with KVM and connects with `xfreerdp3`. It is heavily hardened: a root-owned compose file, polkit, and no docker group.
- **CachyOS.** The Package Installer lists `virtualbox`, `gnome-boxes` and `virt-manager` as plain packages. The wiki's QEMU page gives the full recipe:
  - `qemu-full virt-manager swtpm`
  - `firewall_backend = "iptables"` appended to `/etc/libvirt/network.conf`
  - `usermod -aG libvirt`
  - `libvirtd.socket`
  - `virsh net-autostart default`
  - `ufw route allow from 192.168.122.0/24`

  Hello's "Install Winboat" button installs `winboat` plus `docker docker-compose`. WinBoat also runs dockur/windows underneath.
- **What matters for karchy.** The user runs 14 system VMs in virt-manager and tests karchy itself in libvirt, so libvirt is the must-have. CachyOS's recipe fits karchy's ufw base. Both Windows-app routes (Omarchy's VM and WinBoat) need Docker; WinBoat also wants the root-equivalent docker group, which Omarchy deliberately avoids.
- **Recommendation.** Build a **Virtual machines** ⚙ feature on the CachyOS recipe. Use `qemu-desktop` rather than `qemu-full`, which pulls every emulator architecture. Add a btrfs layout fix (section 3.2). Leave Windows-app integration out of v1. Offer WinBoat later as its own entry that depends on Docker.

### 2.3 Docker and Podman

- **Omarchy.** Docker is in base: `docker docker-buildx docker-compose ufw-docker`, with `docker.socket` enabled. `daemon.json` sets log rotation, `bip 172.17.0.1/16` and DNS 172.17.0.1. ufw allows container DNS to the host, and `ufw-docker install` fixes Docker's habit of publishing ports past ufw. The user is not added to the `docker` group; `omarchy-setup-security-sudoless-docker` opts in. Omarchy also offers dev-database containers. Podman appears only inside omarchy-local-ai.
- **CachyOS.** The Package Installer lists `docker docker-compose` and `podman-docker podman-compose crun` as plain packages, with no service, group or firewall setup.
- **What matters for karchy.** The user uses **Podman** (111 GB of storage, database test containers, NVIDIA CDI). Rootless Podman is not root-equivalent, its published ports are ordinary host sockets that ufw filters normally, and it needs no daemon. Docker publishes ports past ufw unless ufw-docker is installed.
- **Recommendation.** Make **Podman** the primary ⚙ entry (setup in 3.3). Offer **Docker** as a second ⚙ entry following Omarchy's model: socket, no group by default, ufw-docker. Treat the two as mutually exclusive whenever `podman-docker` is ticked, because it conflicts with `docker`. Port Omarchy's dev-DB list onto Podman.

### 2.4 Flatpak

- **Omarchy.** Installs `flatpak` only as a step inside GeForce NOW, with no remote setup. Its "remove launcher entry" command knows how to uninstall Flatpak apps.
- **CachyOS.** No Flatpak entry in the Package Installer or Hello. The wiki mentions Flatpak for some apps (Bottles).
- **Recommendation.** A small ⚙ entry of karchy's own (section 3.4). Arch's `flatpak` already ships the Flathub remote file and environment generators, so the setup is mostly checks plus a theme override.

### 2.5 Browsers

- **Omarchy.** `omarchy-install-browser <chromium|chrome|brave|brave-origin|edge|firefox|zen>` does more than install the package. It creates the managed-policy directory, copies Omarchy's flags file, installs its copy-URL and yt-dlp extensions, links Widevine for Brave, applies the theme and sets Wayland for Firefox and Zen.
- **CachyOS.** Plain packages: librewolf (now gone from the AUR), firefox, chromium, ungoogled-chromium, vivaldi, tor, brave-bin, floorp, falkon, qutebrowser. The `[cachyos]` repo prebuilds `brave-bin`, `zen-browser-bin`, `floorp-bin`, `mullvad-browser-bin` and `ungoogled-chromium-bin`, so no AUR build is needed.
- **Recommendation.** Plain entries that take packages from `[cachyos]`/`[extra]` first and `[omarchy]` second, with a small post-install hook for the Chromium family: policy directory plus `karchy-theme-set-browser`, and the Widevine link for Brave. Skip Omarchy's extensions. Drop LibreWolf.

### 2.6 Dev toolchains and editors

- **Omarchy.** Runtimes come from `mise use -g <lang>@latest`. Rust and OCaml use their curl installers. Editors are packages plus Omarchy theme glue; note that the VS Code installer overwrites `argv.json` and `settings.json`.
- **CachyOS.** The Package Installer's Development group is mostly IDEs and ops tools (vim, code, emacs, qtcreator, intellij, pycharm, cockpit, ansible, docker, podman, terraform), not language runtimes.
- **Recommendation.** karchy dropped mise (D-19), so every runtime is a plain pacman entry from `[extra]`. The exception is Rust via `rustup`, which needs one user-side step. Take Omarchy's *list* of languages and the user's audit list. Ignore CachyOS's IDE list except where the user asks.

### 2.7 NVIDIA bits

- **Omarchy.** `nvidia-open-dkms nvidia-utils lib32-nvidia-utils libva-nvidia-driver`, or the 580xx branch for pre-GSP cards. It sets `nvidia_drm modeset=1` and early-loads the modules in mkinitcpio.
- **CachyOS (chwd `nvidia-open-dkms` profile).** `nvidia-utils egl-wayland nvidia-settings opencl-nvidia lib32-opencl-nvidia lib32-nvidia-utils libva-nvidia-driver vulkan-icd-loader lib32-vulkan-icd-loader cachyos-drm-awaiter`, on top of the prebuilt `linux-cachyos-nvidia-open` modules.
- **karchy now** (`karchy-nvidia`): `linux-cachyos{,-lts}-nvidia-open nvidia-utils libva-nvidia-driver`, which is already the CachyOS prebuilt-module approach.
- **Recommendation.** Leave the base as it is. The Gaming feature adds `lib32-nvidia-utils` (and `lib32-opencl-nvidia` if OpenCL is ticked). `opencl-nvidia` can be a plain entry. `nvidia-settings` is X11-centric and not needed.

### 2.8 Tailscale and Sunshine (network services both touch)

- **Omarchy.** It installs Tailscale as follows:
  - `tailscale` plus `tailscaled`
  - `tailscale up --accept-routes`
  - `tailscale set --operator=$USER`
  - a Taildrop auto-receive user unit
  - a bar panel
  - an admin-console web app

  Its Sunshine setup opens ufw only for RFC1918 ranges and `tailscale0`.
- **CachyOS.** `ufw-extras` (Arch [extra]) ships ufw app profiles for `tailscale` (3478,41641/udp) and `Steam`. Hello has no Tailscale action.
- **Recommendation.** Use Omarchy's flow, minus the bar panel (karchy has none yet; porting Omarchy's Quickshell Tailscale panel is a separate job). Use karchy's trusted-network list for any LAN-facing ports.

### 2.9 AI desktop and local models

- **Omarchy.** Install menu entries for Claude Desktop, ChatGPT/Codex Desktop, LM Studio, Ollama (it picks `ollama-cuda` when `nvidia-smi` exists, else `-rocm`, else plain), T3 Code (AppImage) and others. Agent CLIs come through mise lazy shims.
- **CachyOS.** chwd's `nvidia-ai-sdk` and `rocm-ai-sdk` profiles bundle CUDA or ROCm, PyTorch, TensorFlow and Ollama.
- **Recommendation.** Plain entries from `[cachyos]`/`[extra]` (`claude-code`, `openai-codex`, `opencode`, `claude-desktop`) plus AUR `pi-coding-agent-bin`, and `t3code-bin` from `[omarchy]`. Ollama becomes a small ⚙ entry using Omarchy's GPU choice, but prefer `ollama-vulkan` on the AMD laptop: ROCm is large and poorly supported on APUs. Skip the CUDA SDK bundle.

---

## 3. Setup details for the ⚙ features

Every script follows the `karchy-feature-printing` shape: `status | install | remove`, run in a floating terminal, packaged config under `/usr/share/karchy/default/features/<id>/`, and a dry run of the removal before any change.

### 3.1 Gaming (Steam)

**install**
1. Refuse unless the machine is x86_64.
2. **Enable multilib.** Arch's stock `/etc/pacman.conf` carries a commented `#[multilib]` / `#Include = /etc/pacman.d/mirrorlist` pair after `[extra]`. Uncomment it in place so it stays after `[extra]` and before `[omarchy]`/`[karchy]`, or append it if the pair is missing. Then run a **full** `pacman -Syu` in the same command as the installs (`sudo pacman -Syu --needed …`) to avoid a partial upgrade.
3. **GPU driver, in the same transaction as steam.** With explicit providers listed, `--noconfirm` cannot pick the wrong `lib32-vulkan-driver`:
   - NVIDIA (`karchy-hw-nvidia`): `lib32-nvidia-utils` (from `[cachyos]`, because `[cachyos]` comes before `[multilib]`; version-locked to nvidia-utils). Optionally `lib32-opencl-nvidia`.
   - AMD: `vulkan-radeon lib32-vulkan-radeon lib32-mesa`. karchy's base pulls in no Vulkan driver for AMD today, so `vulkan-radeon` is needed for 64-bit games as well.
   - Intel: `vulkan-intel lib32-vulkan-intel lib32-mesa`.
   - Both: a hybrid laptop gets both sets.
4. Packages: `steam` plus the default-on ticks `proton-cachyos-slr gamemode lib32-gamemode mangohud lib32-mangohud gamescope ntsync-autoload protontricks ttf-liberation`. `steam` already pulls `steam-devices` (controller udev rules) and `lib32-pipewire`.
5. `sudo usermod -aG gamemode "$USER"`, which needs a relogin. The `gamemode` group comes from the package's sysusers file, and its polkit rule allows the governor/GPU/X3D helpers without a password only for that group.
6. `sudo modprobe ntsync` now, so no reboot is needed. `/dev/ntsync` already exists on this host because `cachyos-settings` loads it.
7. Optional, per the CachyOS wiki: a shader-cache size in `~/.config/environment.d/gaming.conf`. Use `__GL_SHADER_DISK_CACHE_SIZE=12000000000` on NVIDIA or `MESA_SHADER_CACHE_MAX_SIZE=12G` on AMD. It takes effect on the next login.
8. Optional ufw: Steam Remote Play and LAN transfer (`27031:27036/udp`, `27036:27037/tcp`, `27040/tcp`). Open them **only on trusted networks**, through the same NetworkManager hook used for LocalSend (D-33). Skip this by default.
9. Notes for the user:
   - The existing library at `/mnt/big/SteamLibrary` moves to `/mnt/BIG` (audit), so re-add it in Steam.
   - Proton on NTFS is unsupported (CachyOS wiki).
   - Keep Valve Proton as the global default and use proton-cachyos per game.
   - Don't use `game-performance`; use `gamemoderun %command%`.

**status**: `installed` when multilib is enabled, `steam` is installed and the lib32 driver for this GPU is present. `incomplete` when Steam is present but the driver is missing (say which). Otherwise `available`.

**remove**:
1. `pacman -Rns` steam and the ticked companions.
2. Keep `[multilib]` enabled while any `lib32-*` package remains (`pacman -Qqs '^lib32-'`). Disable it only when none remain.
3. Take the user out of `gamemode`.
4. **Do not delete `~/.local/share/Steam` or the library folders.** Omarchy's remover does; it should be at most a separate, confirmed choice here.

**Separate gaming ticks** (each needs multilib and the lib32 driver, so they call the Gaming install first when it isn't installed):
- Lutris: `lutris umu-launcher wine-staging winetricks`. Omarchy's shebang `sed` was a mise workaround; karchy doesn't need it.
- Heroic: `heroic-games-launcher-bin` [cachyos].
- Faugus: `faugus-launcher` [cachyos].
- wine-cachyos: `wine-cachyos-opt`.
- Xbox controllers: `xpadneo-dkms` plus **`linux-cachyos-headers linux-cachyos-lts-headers`** (DKMS must build for both karchy kernels), `/etc/modprobe.d/blacklist-xpad.conf`, `/etc/modules-load.d/xpadneo.conf`, the `input` group.

### 3.2 Virtual machines (libvirt)

**install**
1. Packages: `qemu-desktop libvirt virt-manager dnsmasq edk2-ovmf swtpm`, optionally `virt-viewer`. `iptables` (which provides `iptables-nft`) is already on karchy for ufw, and `nftables` comes with libvirt and Podman.
2. **Firewall backend.** libvirt 12 picks nftables first when `firewall_backend` is unset; that is the default in `/etc/libvirt/network.conf` on this host. Under nftables, libvirt's accept rules sit in their own table, and ufw's iptables-nft `INPUT`/`FORWARD` DROP policies still drop the same packets: a drop verdict in any base chain is final. CachyOS's wiki avoids this with `firewall_backend = "iptables"`. That puts libvirt's DHCP/DNS accepts into the same filter table that ufw uses. Ship it as the line `firewall_backend = "iptables"` in `/etc/libvirt/network.conf`; libvirt reads only that file, with no drop-in directory.
3. **ufw forwarding.** ufw has `DEFAULT_FORWARD_POLICY="DROP"` (this host). Add `sudo ufw route allow in on virbr0` and `sudo ufw route allow out on virbr0` with comment `karchy-vm`. CachyOS's equivalent is `ufw route allow from 192.168.122.0/24`; the interface form also covers additional NAT networks if they use `virbr*`. Then `ufw reload`.
4. **Daemons.** Enable `libvirtd.socket`, the monolithic daemon. This host uses it and the CachyOS wiki gives it. The alternative is the modular set (`virtqemud.socket virtnetworkd.socket virtstoraged.socket virtnodedevd.socket virtsecretd.socket virtinterfaced.socket`). Both work; pick one and don't enable both.
5. **Group**: `sudo usermod -aG libvirt "$USER"`. libvirt's own polkit rule lets that group manage `qemu:///system` without a password. A relogin is needed.
6. **Default network**: `sudo virsh -c qemu:///system net-autostart default && sudo virsh -c qemu:///system net-start default`. This needs dnsmasq.
7. **Disk layout (karchy-specific).** `/var/lib/libvirt/images` lives in the `@` root subvolume, so snapper's pre/post snapshots on every pacman transaction would pin VM disk churn. The user's disks there take 45 GB. Create a dedicated subvolume, for example `@libvirt` at `/var/lib/libvirt/images`, through an fstab entry, so it stays out of root snapshots. Run `chattr +C` on it while it is empty so qcow2 files don't fragment under copy-on-write.
8. Optional: virt-manager's "Connect to qemu:///system" is the default; nothing more to configure.

**verify in a VM before shipping**: the guest gets a DHCP lease and DNS, reaches the internet, and the LAN cannot reach the guest. Also check that `ufw reload` does not wipe libvirt's iptables chains. libvirt's docs warn that restarting the host firewall removes them, and they come back with `systemctl restart libvirtd` (or virtnetworkd) or a SIGHUP. That may need a ufw-reload hook.

**status**: `installed` when the packages are present, a libvirt socket is enabled and the user is in `libvirt`. `incomplete` when, for example, the default network is not autostarted.

**remove**:
1. `virsh net-autostart --disable default`.
2. Disable the sockets.
3. Delete the `karchy-vm` ufw rules.
4. `pacman -Rns`.
5. **Keep `/var/lib/libvirt/images` and the domain XML** unless the user confirms deletion.

### 3.3 Podman (primary) and Docker (optional)

**Podman install**
1. Packages: `podman podman-compose`. `crun`, `passt`, `netavark`, `aardvark-dns`, `conmon` and `catatonit` come as dependencies; `fuse-overlayfs` is not needed with native rootless overlay. Optional ticks: `podman-docker` (a `docker` CLI shim that conflicts with `docker`), `podman-desktop`, `lazydocker`, `distrobox`.
2. **subuid/subgid.** karchy creates the user with `useradd`, and `/etc/login.defs` has `SUB_UID_COUNT 65536`, so an entry should already exist; this host has `nulifyer:100000:65536`. The script checks `grep "^$USER:" /etc/subuid /etc/subgid`. If the entry is missing, it runs `sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER"`, then `podman system migrate`.
3. `systemctl --user enable --now podman.socket` gives Docker-API tools (VS Code Dev Containers, docker-compose, lazydocker) a socket at `$XDG_RUNTIME_DIR/podman/podman.sock`. Optionally export `DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock` in the environment.
4. **Short names.** This host's `/etc/containers/registries.conf` defines no `unqualified-search-registries`, so `podman pull postgres` fails without a TTY prompt. Ship `/etc/containers/registries.conf.d/10-karchy.conf` with `unqualified-search-registries = ["docker.io"]`, or document that full image names are required.
5. **NVIDIA** (`karchy-hw-nvidia`): add `nvidia-container-toolkit`. The package enables `nvidia-cdi-refresh.path`/`.service` itself and writes the CDI spec under `/var/run/cdi`, so the user's manual `~/.config/cdi/nvidia.yaml` is no longer needed. Use `--device nvidia.com/gpu=all`.
6. ufw: nothing to do. Rootless published ports are host sockets, so ufw's deny-incoming applies: localhost works and the LAN is blocked unless the user allows a port.

**status**: podman installed and subuid present. Optionally report whether the user socket is enabled.

**remove**: disable the user socket, then `pacman -Rns`. Keep `~/.local/share/containers` (111 GB on this host) unless the user confirms `podman system reset`.

**Docker install** (Omarchy model)
- Packages: `docker docker-compose docker-buildx`; `ufw-docker` from `[omarchy]`, or the AUR as a fallback.
- `systemctl enable --now docker.socket`.
- `/etc/docker/daemon.json`: log rotation, and optionally Omarchy's `bip`/`dns` values.
- `ufw-docker install` so `-p` publishes stop bypassing ufw. Plus Omarchy's DNS rule: `ufw allow in proto udp from 172.16.0.0/12 to 172.17.0.1 port 53`.
- **No `docker` group by default**: it is root-equivalent. Offer it as an opt-in, because WinBoat needs it.
- Refuse when `podman-docker` is installed.

**Docker remove**: disable the socket, run `ufw-docker uninstall` (or remove the after.rules block), `pacman -Rns`. Keep `/var/lib/docker` unless the user confirms.

### 3.4 Flatpak + Flathub

**install**
1. `flatpak`. The Arch package ships `/usr/share/flatpak/remotes.d/flathub.flatpakrepo`, the sysusers file and polkit rules. The script verifies with `flatpak remotes --columns=name`, and if `flathub` is missing runs `flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`.
2. Launcher visibility: flatpak ships `user-environment-generators/60-flatpak`, which adds the export dirs to `XDG_DATA_DIRS` for the systemd user manager. karchy's apps run under uwsm or systemd, so a **relogin** is needed. Verify on karchy that the Quickshell launcher sees `/var/lib/flatpak/exports/share/applications`. fish does not read `/etc/profile.d/flatpak.sh`.
3. Portals: `xdg-desktop-portal-hyprland` and `xdg-desktop-portal-gtk` are already karchy base dependencies.
4. Theme (optional): `flatpak install flathub org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark`, plus `flatpak override --user --filesystem=xdg-config/gtk-3.0:ro --filesystem=xdg-config/gtk-4.0:ro`, so GTK Flatpaks follow karchy's adw-gtk3 theme.
5. Optional ticks: `flatseal` (permissions) and `warehouse` (management), both in [extra].

**status**: flatpak installed and the flathub remote present.

**remove**: refuse while Flatpak apps are installed (`flatpak list --app`), or offer `flatpak uninstall --all` with confirmation. Then `pacman -Rns flatpak`.

### 3.5 Tailscale

**install**
1. `tailscale`, then `sudo systemctl enable --now tailscaled`.
2. `sudo tailscale up --operator="$USER"` (Omarchy adds `--accept-routes`; make that a choice). It prints an auth URL; open it with `xdg-open`.
3. `tailscale set --operator="$USER"` lets the shell and CLI work without sudo.
4. DNS: karchy uses systemd-resolved, and tailscaled configures MagicDNS through resolved's D-Bus API. Nothing else to do.
5. **ufw.** With ufw active, tailscaled detects iptables rules and uses its iptables mode. Its `ts-input` chain is jumped to from the top of `INPUT`, and in current releases (from my reading of Tailscale's source, not checked here) it accepts all traffic arriving on `tailscale0`, so tailnet traffic bypasses ufw by design and access is controlled by tailnet ACLs. The Tailscale KB still recommends `sudo ufw allow in on tailscale0`; add it with comment `karchy-tailscale`, which is harmless. Inbound `41641/udp` is optional: NAT traversal works without it, and opening it only improves direct connections. **Verify** on karchy with `sudo iptables -S ts-input` and `sudo nft list ruleset`.
6. Optional (Omarchy):
   - an admin-console web app (`karchy-webapp-install Tailscale https://login.tailscale.com/admin/machines <icon>`)
   - a Taildrop auto-receive user unit (`tailscale file get --loop --conflict=rename ~/Downloads`)
   - later, port Omarchy's Quickshell Tailscale panel. karchy's captive-portal script already handles exit nodes.

**status**: `tailscale status --json` succeeds and reports BackendState; otherwise check that `tailscaled` is active.

**remove**: `tailscale down` (optionally `tailscale logout`), disable `tailscaled`, delete the ufw rule, remove the web app and the user unit, `pacman -Rns tailscale`.

### 3.6 Syncthing

**install**
1. `syncthing`, optionally `syncthingtray`.
2. `systemctl --user enable --now syncthing.service` (a user unit, shipped by the package).
3. ufw: the package ships `/etc/ufw/applications.d/ufw-syncthing` (22000/tcp, 22000/udp, 21027/udp). Open it **only on trusted networks** with the D-33 LocalSend-style hook, so Syncthing uses relays elsewhere. A simpler alternative is `ufw allow syncthing` everywhere.
4. Web UI: `karchy-webapp-install Syncthing http://127.0.0.1:8384 <icon>` (the Omarchy Sunshine and Tailscale pattern).
5. The package also ships `sysctl.d/30-syncthing.conf` (UDP buffer sizes for QUIC). Nothing to do.

**status**: package installed and user unit enabled.

**remove**: disable the user unit, delete the ufw rules and web app, `pacman -Rns`. Keep `~/.local/state/syncthing` (keys and config) unless the user confirms.

### 3.7 Rust (rustup)

**install**
1. `rustup` and `clang` (Omarchy adds clang for bindgen). If the `rust` package is installed it conflicts; offer to replace it.
2. As the user: `rustup default stable`, optionally `rustup component add rust-analyzer rust-src`.
3. PATH: rustup's proxies are `/usr/bin/cargo` and `/usr/bin/rustc`. `~/.cargo/bin` holds only `cargo install` binaries; add it to fish's PATH (`fish_add_path ~/.cargo/bin`) if wanted.

**status**: `rustup` installed and `rustup toolchain list` not empty.

**remove**: `pacman -Rns rustup`; optionally delete `~/.rustup` and `~/.cargo` after confirmation.

### 3.8 OpenRGB

**install**
1. `openrgb`, optionally `i2c-tools`.
2. The package ships `/usr/lib/udev/rules.d/60-openrgb.rules`, `/usr/lib/modules-load.d/openrgb.conf` (containing `i2c-dev`) and `/usr/lib/systemd/system/openrgb.service` (`openrgb --server --config /etc/openrgb`).
3. Script: `sudo udevadm control --reload-rules && sudo udevadm trigger`, then `sudo modprobe i2c-dev`. This avoids a reboot.
4. Optional: `systemctl enable --now openrgb.service` to apply a profile at boot. The GUI can connect to the server.
5. Do **not** add `acpi_enforce_resources=lax` automatically. Some boards need it for SMBus RAM and motherboard LEDs, but it is a kernel-level risk; document it instead.
6. Hardware fit: the Corsair K95 RGB and the ASUS AURA USB controller are USB HID, so the udev rules alone suffice. RAM RGB would need i2c.

**status**: package installed and udev rules present. **remove**: disable the service, then `pacman -Rns`.

Note: ckb-next (`ckb-next-daemon.service`) is the alternative for Corsair keyboards. Don't run it together with OpenRGB on the same device.

### 3.9 Web apps

- karchy already has `karchy-webapp-install [name url icon [exec] [mime]]`, `karchy-webapp-remove`, `karchy-launch-webapp` and `karchy-launch-or-focus-webapp`, ported from Omarchy (URL and name validation, icon fetch, a `.desktop` file in `~/.local/share/applications`).
- The catalog entry is data only: `{name, url, icon}`. Omarchy uses `https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/<app>.png` icons.
  - **status**: `[[ -f ~/.local/share/applications/<Name>.desktop ]]`
  - **install**: `karchy-webapp-install "<Name>" "<url>" "<icon>"`
  - **remove**: `karchy-webapp-remove "<Name>"`
- Suggested set:
  - the user's own: ChatGPT, Discord, YouTube, Amazon
  - Omarchy's: Google Maps, Messages, Photos, Contacts, WhatsApp, X, Netflix, Spotify, Zoom, Grok, Xbox Cloud Gaming, plus the Microsoft 365 bundle (Outlook, Word, Excel, PowerPoint, Teams, OneDrive)
  - a "Custom web app…" row that opens the interactive form, for the homelab dashboards
- Web apps need a Chromium-family browser. Brave Origin is base, so that is fine.

### 3.10 Smaller ⚙ entries (one-liners)

- **Ollama**: GPU-matched package, then `systemctl enable --now ollama.service`. Remove: disable, `pacman -Rns`, offer to delete `/var/lib/ollama` (models).
- **Sunshine**:
  - `sunshine` and `systemctl --user enable --now sunshine`.
  - ufw TCP 47984/47989/48010 and UDP 47998-48000/48002/48010 for RFC1918 ranges and `tailscale0`; Omarchy's port list also includes UDP 5353.
  - admin web app at `https://localhost:47990`.
  - Remove those rules on uninstall.
- **GitHub CLI**: `github-cli`, then `gh auth login` and `gh auth setup-git` in a terminal.
- **NordVPN / Mullvad / ckb-next / CoolerControl / LACT / ananicy-cpp / psd / bpftune / scx_loader**: install, then enable the shipped unit, plus a group where noted (`nordvpn`). Remove reverses it. See the tables for unit names.

---

## 4. Side findings in karchy (not part of the catalog, worth a look)

1. **`cachyos-settings` would undo karchy's zswap choice.** It depends on `zram-generator` and ships `/usr/lib/systemd/zram-generator.conf`, plus udev, sysctl, modprobe (`NVreg_InitializeSystemMemoryAllocations=0`), THP and journald defaults. Don't let any catalog entry pull it in. `cachyos-gaming-meta` does **not** depend on it.
2. **`game-performance` fails on the NVIDIA desktop**: it needs `powerprofilesctl` or `tlpctl`, and karchy installs power-profiles-daemon only with a battery. GameMode is the safe default. Alternatively, install power-profiles-daemon on every machine.
3. **zls/zig mismatch in [extra]**: `zig 0.17.1` against `zls 0.15.1`. A "Zig" entry that installs both gives a non-working language server; consider leaving `zls` out or warning about it.
4. **`bin/karchy-pkg-aur-install` and `bin/karchy-pkg-remove` still call `yay`**, but D-20 chose paru and karchy ships `paru`, not `yay`. The Install page's AUR path should use paru.
5. **`bin/karchy-launch-webapp` error text** says "install Chromium with 'karchy install browser chromium'", but no `karchy-install-browser` command exists. Either the Install page provides it, or the message should change.
6. **`install/packages/base.txt` lists `iptables-nft`**, which is no longer a package name. `iptables` now provides and replaces it. Pacstrap still resolves the provide, so this works, but `iptables` is the real name.
7. **`[omarchy]` ships builds of several AUR apps**: `google-chrome`, `visual-studio-code-bin`, `spotify`, `slack-desktop`, `1password`, `sublime-text-4`, `microsoft-edge-stable-bin`, `minecraft-launcher`, `t3code-bin`, `ufw-docker`, `nordvpn-bin`, `lmstudio-bin`, `dropbox`, `rustdesk`, `symfony-cli`, `notion-desktop`. karchy can install these with pacman, with no AUR build. Several more are prebuilt in `[cachyos]`: `brave-bin`, `zen-browser-bin`, `cursor-bin`, `claude-code`, `claude-desktop`, `proton-pass`, `proton-mail-bin`, `vesktop-bin`, `onlyoffice-bin`, `winboat`, `sunshine`, `xpadneo-dkms`. Only these remain AUR-only: `pi-coding-agent-bin`, `bcompare`, `vkbasalt`, `proton-ge-custom-bin`, `android-studio`, `jetbrains-toolbox`, `zoom`, `ttf-ms-fonts`, `bottles`, `game-devices-udev`, `scala-cli`, `trayscale`/`ktailctl`.
8. **The audit's "add to base" items** (`openssh`, `rsync`, `unzip`, `ttf-liberation`, and arguably `github-cli`) are not catalog material: they belong in base.

## 5. Not verified

- How ufw and libvirt interact under each libvirt firewall backend, and whether `ufw reload` drops libvirt's iptables chains (section 3.2). The analysis is reasoned from nftables semantics and the CachyOS wiki; test it in a karchy VM.
- That Tailscale's `ts-input` accepts all traffic on `tailscale0` before ufw (section 3.5). This is from my reading of Tailscale's source; check with `iptables -S ts-input`.
- That Flatpak apps appear in karchy's launcher after a relogin (section 3.4).
- The Mullvad daemon unit name. The Arch file-list lookup came back empty.
- Whether karchy's [cachyos]-only repo set resolves `lib32-mesa` and `lib32-nvidia-utils` from `[cachyos]` once `[multilib]` is added. This host also has the `-v3` repos, so I inferred this from the repo order rather than testing it.
