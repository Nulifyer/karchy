# Desktop usage audit: what this machine uses vs. what karchy covers

Machine: CachyOS desktop, RTX 5080 (open modules), Ryzen (Matisse platform), two DisplayPort monitors (DP-1, DP-3), Intel AX200 Wi-Fi/BT, Intel I211 Ethernet, 3.6 TB ext4 data disk labelled `BIG` at `/mnt/big`, 3 CIFS automounts from a TrueNAS box.

Everything here was checked read-only on 2026-11-14. 254 explicit packages (`pacman -Qqe`), 6 foreign (`bcompare`, `pi-coding-agent-bin`, `rustdesk-bin`, `t3code-bin`, `visual-studio-code-bin`, `android-sdk-cmdline-tools-latest`). No flatpak binary is installed (only leftover `~/.var/app` dirs from old Flatpak browsers), no snaps, no `~/Applications`. `~/.local/bin` holds `cmake`/`ctest`/`cpack`/`ccmake`, `guget`, `sqlgo` and `darkreader-update`.

How "in karchy?" was decided: I checked `docs/components.md`, `install/packages/base.txt` and the `depends` of the `karchy`, `karchy-desktop` and `karchy-nvidia` PKGBUILDs, plus their full dependency closure from the sync databases (`pactree -su`, 573 packages). The closure misses the dependencies of `[omarchy]`/`[karchy]`-only packages, because those repos are not in this host's pacman config.

## Session in use

| Thing | Here | karchy |
|---|---|---|
| Desktop | KDE Plasma 6, Wayland (`XDG_CURRENT_DESKTOP=KDE`, `kwin_wayland`, `plasmashell`) | Hyprland + Quickshell |
| Login | `plasma-login-manager` with autologin (`plasmalogin-autologin`) | greetd auto-login → uwsm |
| Boot splash | Plymouth | none (PLAN "Out") |
| Swap | zram (31 GB) | zswap + swap file |
| Wi-Fi backend | NetworkManager with `wifi.backend=iwd` | NetworkManager + wpa_supplicant |
| Keyring | KWallet (`kwallet-pam`); Brave runs with `--password-store=basic` | oo7; Brave uses `gnome-libsecret` |

Enabled system units worth noting: `ananicy-cpp`, `avahi-daemon`, `bluetooth`, `iwd`, `NetworkManager`, `systemd-resolved`, `ufw`, `libvirtd*.socket`, `cachyos-rate-mirrors.timer`, `fstrim.timer`, `paccache.timer`, `snapper-timeline.timer`, `snapper-cleanup.timer`, `limine-snapper-sync`. User units: `pipewire`, `wireplumber`, `xdg-user-dirs`, `arch-update.timer`. Autostart: only system `/etc/xdg/autostart` entries (Plasma pieces, `arch-update-tray`, `limine-snapper-notify`, KDE Connect daemon); `~/.config/autostart` is empty. No crontab (cronie not installed).

Local tweaks found: `/etc/systemd/system/user-1000.slice.d/90-memory-spike-grace.conf` sets `ManagedOOMMemoryPressureDurationSec=120s` (a systemd-oomd grace period). A user override on powerdevil sets `POWERDEVIL_NO_DDCUTIL=1`. `~/.config/environment.d/terminal.conf` sets `TERMINAL=kitty`.

Default apps here: http/https and PDF → Brave, text/plain → Kate, images → Gwenview, video → Haruna, audio → mpv, folders → Dolphin, mailto → none.

## Comparison

"In karchy?" values: **base** (always installed), **detected** (installer installs it when it finds the hardware), **optional** (Settings › Optional features), **replaced** (karchy ships a different tool for the job), **no**.

### Desktop basics

| Item | Used here (evidence) | In karchy? | Recommendation |
|---|---|---|---|
| Plasma, KWin, plasmashell, kscreen, powerdevil, plasma-nm, plasma-pa, bluedevil, klipper, kinfocenter, plasma-systemmonitor | running session | replaced (Hyprland, shell panels, Settings › Displays, clipboard history, fastfetch, btop) | not needed |
| Dolphin (folder default), Ark | mime default, `arkrc` | replaced (Thunar, xarchiver + archive plugin, 7zip) | not needed |
| Kate (text/plain default) | mime default, `katerc` | replaced by VS Code / micro, but the D-28 default-apps list has no text entry | add `text/plain` → VS Code to the base default-apps list |
| Gwenview, Haruna, VLC | mime defaults | replaced (imv, mpv) | not needed |
| Spectacle | config stowed from dotfiles | replaced (Omasnap) | not needed |
| kcalc, filelight, partitionmanager, btrfs-assistant | installed, config files | omacalc / GNOME Disks replace two; no disk-usage viewer | user installs (`baobab` or `gdu`) if wanted |
| kitty (`TERMINAL=kitty`), konsole, alacritty | env var, configs in dotfiles | replaced (foot) | user installs kitty only if foot falls short; drop the kitty/alacritty/konsole dotfiles from the user layer or keep them dormant |
| pavucontrol | installed | no (shell audio panel) | user installs; per-app stream routing is the gap |
| Fonts: Cascadia Mono Nerd, Meslo Nerd, DejaVu, Liberation, Bitstream Vera, Open Sans | installed | no (JetBrains Mono Nerd + Noto only) | add `ttf-liberation` to base (metric-compatible Arial/Times/Courier for web pages and documents); others user installs |
| bash-completion, nano, vim, plocate, pkgfile, ripgrep, duf, pv, stow, wget, rsync, unzip, unrar | installed | only `which` and `less` are in the closure; micro is base | add `openssh`, `rsync`, `unzip` to base (scripts and installers expect them); the rest user installs |
| cachyos-hello, kernel-manager, packageinstaller, chwd, arch-update tray, cachy-update | installed, autostart | replaced (`karchy update`, updates indicator) | not needed |
| Plymouth | installed | dropped on purpose | not needed |
| KDE Connect | daemon autostarts, but no paired devices in its config | no | not needed (LocalSend is base) |

### Apps

| Item | Used here (evidence) | In karchy? | Recommendation |
|---|---|---|---|
| Brave (`brave-bin`) + 8 Brave web apps (ChatGPT, Discord, YouTube, Amazon, several homelab dashboards) | default browser, `.desktop` files | base (Brave Origin) + web-app mechanism | recreate the web apps after the move; see the password note below |
| VS Code, 28 extensions | config updated today | base | turn on Settings Sync before the move |
| Zed | config from Sept | no | user installs (`zed`) |
| Obsidian | vault config, Oct | no; `theme-set-obsidian` was dropped by D-48 | user installs; revisit D-48 if the theme should follow karchy's |
| Beyond Compare (AUR), Meld | config updated Nov 12 | no | user installs (paru `bcompare`, `meld`) |
| RustDesk (AUR) | config from Aug, service disabled (client use) | no | user installs; client works, being a host under Hyprland is unreliable |
| AI tools: claude-code, openai-codex, opencode, pi-coding-agent-bin, t3code-bin | running (t3code), configs | out by PLAN ("AI CLIs") | user installs; `theme-set-pi` was dropped by D-48 too |
| Ghidra, Odin, android-tools, Android SDK | configs, Oct | no | user installs |
| tesseract-data-eng | installed | base (Omasnap OCR) | covered |
| LocalSend | installed | base | covered |
| Mail client | none (mailto unset) | none | not needed |
| Password manager | Proton Pass (per components.md) | user installs | covered by plan |

### Dev

| Item | Used here (evidence) | In karchy? | Recommendation |
|---|---|---|---|
| dotnet-sdk, go, rustup, zig, bun, deno, jdk-openjdk, kotlin, gradle, python + uv + pypy, nodejs/npm, cmake (in `~/.local/bin`), gopls, actionlint, shellcheck | all on `PATH` | out (D-19) | user installs; consider a one-line `paru -S` list in the dotfiles repo |
| gh (also the git credential helper for github.com) | `git config` credential helper points at gh | no | user installs right away, or HTTPS pushes to GitHub fail |
| Podman + podman-compose, ~111 GB storage, test database containers | `podman ps -a` | out (D-19); ufw rules planned | user installs |
| nvidia-container-toolkit (GPU in containers) | installed, `~/.config/cdi` | no | user installs with Podman, then `nvidia-ctk cdi generate` |
| libvirt, qemu-desktop, virt-manager, edk2-ovmf, swtpm, dnsmasq; 14 system VMs + 2 session VMs, `virbr0` bridge, `libvirtd` sockets enabled | `virsh list --all` | no | **Optional feature** "Virtual machines": it needs setup (group, sockets, default network, ufw/nftables interplay with libvirt's NAT), which is exactly D-28's "Optional" criterion. Also needed to keep testing karchy itself in VMs |

### Gaming

| Item | Used here (evidence) | In karchy? | Recommendation |
|---|---|---|---|
| Steam (running), libraries in `~/.local/share/Steam` and `/mnt/big/SteamLibrary`, Steam game shortcuts in `~/.local/share/applications` | running process, `libraryfolders.vdf` | out (PLAN) | **Optional feature** "Gaming": karchy's installer does not enable `[multilib]`, and `karchy-nvidia` has no `lib32-nvidia-utils`/`lib32-vulkan-icd-loader`, so `pacman -S steam` fails or runs without the GPU driver. Enabling multilib is setup, so it fits Optional |
| proton-cachyos-slr, wine-cachyos-opt, wine (with `~/.wine`), umu-launcher, protontricks, winetricks | `cachyos-gaming-meta` | no | part of the Gaming feature, or user installs |
| gamescope, MangoHud (own config), GOverlay, vkBasalt (own config) | configs present | no | part of the Gaming feature; carry MangoHud/vkBasalt configs into the dotfiles repo |
| Lutris, Heroic, Faugus | installed by `cachyos-gaming-applications` | no | not needed (no config or data dirs) |
| ananicy-cpp + cachyos-ananicy-rules, cachyos-settings (I/O scheduler, NVIDIA, writeback udev rules, sysctl), realtime-privileges | enabled | no | not needed for basics; user can add `ananicy-cpp` later |

### Hardware

| Item | Used here (evidence) | In karchy? | Recommendation |
|---|---|---|---|
| `linux-cachyos{,-lts}-nvidia-open`, `nvidia-utils`, `libva-nvidia-driver`, `egl-wayland` | loaded modules | detected (`karchy-nvidia`) | covered; karchy also enables the NVIDIA suspend/resume services, which are off here |
| `opencl-nvidia`, `lib32-opencl-nvidia` | installed | no | user installs `opencl-nvidia` if compute or OpenCL apps are used; lib32 goes with Gaming |
| `lib32-nvidia-utils` | installed | no | Gaming feature (see above) |
| nvidia-settings | installed | no | not needed (mostly X11) |
| `amd-ucode` | installed | detected | covered |
| Two monitors, DDC brightness | 2 connected DP outputs, `i2c_dev` loaded | base (`ddcutil`, `karchy-brightness-display-ddc`) | verify on this desktop: the powerdevil override `POWERDEVIL_NO_DDCUTIL=1` suggests ddcutil caused trouble here. Also check that `i2c-dev` gets loaded on karchy |
| Corsair K95 RGB Platinum, ASUS AURA LED controller, Keychron Ultra-Link 8K receiver | `lsusb` | no | not needed: no RGB or keyboard software (ckb-next, OpenRGB) is installed now, so lighting runs from firmware |
| liquidctl, CoolerControl, fan control, Piper/Solaar, input-remapper | not installed | no | not needed |
| fwupd, smartmontools | installed | base | covered |
| hdparm, sg3_utils, lsscsi, dmidecode, hwinfo | installed | no | user installs if needed |
| `alsa-firmware`, `sof-firmware` | installed | no | not needed on the desktop; check the Framework's internal microphone on first boot |
| Data disk `BIG` (ext4) at `/mnt/big` | fstab | base (internal disk mounts at `/mnt/<label>`) | **path changes**: karchy keeps the label's case, so it mounts at `/mnt/BIG`. Steam's library and any scripts pointing at `/mnt/big` break. Relabel the disk to `big` before installing, or fix the paths afterwards |
| Wi-Fi (AX200), Bluetooth (no paired devices) | NM, bluez | base | covered |

### Networking / NAS

| Item | Used here (evidence) | In karchy? | Recommendation |
|---|---|---|---|
| 3 CIFS automounts from TrueNAS (homelab, media, tank-share), with a root-only credentials file, `x-systemd.automount`, idle timeout | fstab | base ("Keep this mount", gvfs-smb, cifs-utils) | covered; re-create each with "Keep this mount" and re-enter the credentials |
| avahi + nss-mdns, systemd-resolved | enabled | base | covered |
| openssh client (keys in `~/.ssh`; sshd not enabled) | `~/.ssh` | **no** (not in base or in the dependency closure) | add `openssh` to base: git over SSH and homelab logins need it on day one |
| networkmanager-openvpn, openvpn, xl2tpd | installed, but NM has no VPN profiles | omarchy-vpn-plugin | not needed unless the VPN plugin needs one of them |
| nfs-utils | installed, no NFS mounts | no | not needed |
| bind (dig), inetutils, ethtool, wget | installed | no | user installs |

### Backup

| Item | Used here (evidence) | In karchy? | Recommendation |
|---|---|---|---|
| snapper timeline snapshots | `snapper-timeline.timer` enabled | base snapper, pre/post only, no timeline | not needed (deliberate) |
| restic, borg, rclone, Syncthing | not installed | Optional (phase 7) | not needed now; nothing to migrate |
| Data that lives only on the system disk | VM disks in `/var/lib/libvirt/images` (45 GB) and under `~/.local/state`; Podman storage 111 GB; `~/.wine` 1.2 GB; Steam in `~/.local/share/Steam` | — | copy these to `/mnt/big` or the NAS before the reinstall wipes the disk. Podman images can be pulled again |

### Security

| Item | Used here (evidence) | In karchy? | Recommendation |
|---|---|---|---|
| ufw (+ ufw-extras, plasma-firewall) | enabled | base ufw | covered; ufw-extras not needed |
| KWallet + kwallet-pam | running | replaced (oo7) | not needed, but anything stored in KWallet does not migrate |
| Brave passwords and cookies | Brave runs with `--password-store=basic` | Brave Origin with `gnome-libsecret` | a copied Brave profile cannot decrypt its saved passwords under a different store. Use Brave Sync or Proton Pass before the move |
| gnupg | `~/.gnupg` | in closure (pacman dependency) | covered |
| systemd-oomd grace override (120 s) | `/etc/systemd/system/user-1000.slice.d/` | systemd-oomd is base (Always) | consider shipping the same grace period, or oomd may kill large builds that this machine tolerates now |
| Secure Boot | not set up here | installer step | covered |

## Likely missed on day one

1. **Steam does not install.** `[multilib]` is off and the 32-bit NVIDIA driver is missing. The Steam library path also moves from `/mnt/big` to `/mnt/BIG`.
2. **No `ssh` command.** `openssh` is not in karchy's base or its dependency closure.
3. **GitHub HTTPS push fails** until `gh` is installed, because git's credential helper calls it.
4. **VMs are gone.** virt-manager, libvirt and QEMU are absent, and the VM disks in `/var/lib/libvirt/images` are wiped unless they are copied off first.
5. **Saved Brave passwords** do not carry over (the password store changes from basic to libsecret).
6. **Text files open in the wrong app or none.** The default-apps list has no `text/plain` entry.
7. `unzip` and `rsync` are missing for scripts and installers.
8. DDC monitor brightness may misbehave on this hardware (the powerdevil ddcutil override).
9. The dev runtimes, Podman with the NVIDIA CDI, Zed, Obsidian, Beyond Compare and the AI CLIs all need a single paru run (planned, but worth a list in the dotfiles repo).
