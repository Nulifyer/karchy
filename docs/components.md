# Components

What a karchy install contains. Tags: [O] Omarchy does it, [C] CachyOS does it, [New] neither does. Packages come from Arch unless a repo is named. Anything not listed here is not in the base install.

## System

| Area | Choice | Source |
|---|---|---|
| Repos | `[cachyos]` (generic), then Arch live mirrors, then `[omarchy]` (D-45) | [C] + [O] |
| Kernel | `linux-cachyos`, with `linux-cachyos-lts` as the fallback; NVIDIA machines add both `-nvidia-open` modules and CachyOS's `nvidia-utils` (D-45), or both `-nvidia-580xx` modules and `nvidia-580xx-utils` on Maxwell, Pascal and Volta cards | [C] |
| Disk | LUKS2, btrfs `zstd:1,noatime`, subvolumes `@ @home @root @srv @cache @log @tmp @swap`, 4 GiB ESP at `/boot` | [O+C] |
| Initramfs | systemd + `sd-encrypt` | [C] |
| Boot | Limine + limine-snapper-sync; text console, no Plymouth | [O+C] |
| Snapshots | snapper on `@`: before and after package changes, keep 5, no timeline | [O] |
| Swap | zswap (zstd) + swap file on `@swap` sized to RAM; no zram | [New] |
| /tmp | tmpfs, cap = RAM size, aged out after 10 days | [New] |
| Login | greetd auto-login → uwsm → Hyprland | [New] |
| Keyring | oo7 (Secret Service), unlocked at login by a random per-user key imported as a systemd credential (D-57); Brave and VS Code store passwords there. `karchy keyring-key export <file>` saves the key for backups and `import` (or `KARCHY_KEYRING_KEY_FILE` at install) puts it back, so a restored home's keyring opens | [New] |
| sudo / polkit | Shell polkit overlay; per-terminal sudo cache (10 min); fingerprint (lid gate on the laptop) for polkit prompts and the lock screen, never sudo (D-14, CVE-2024-37408) | [O] |
| Firewall | ufw deny incoming (+ rules for Podman as needed) | [O] |
| Network | NetworkManager + wpa_supplicant + systemd-resolved; portals detected with Arch's own check, and "Sign in to network" opens `http://neverssl.com` in a floating window. Tuning in karchy-settings (`/usr/lib`, so files in `/etc` win): Wi-Fi power save off, ARP only for the interface's own address, TCP MTU probing, BBR + fq; avahi is the only `.local` responder (resolved's LLMNR and mDNS off). Work or school Wi-Fi (802.1X) checks the server's certificate against the system CAs and a domain taken from the identity; skipping the check is an explicit choice behind a warning. Trusted networks (D-68): one list, bound to the router's hardware address (and, for Wi-Fi, the name and security), so the same profile behind another router isn't trusted; Settings › Network says "Trusted, but a different router: not trusted now". DNS: on networks that aren't trusted, the live connection uses Quad9 over TLS (`/etc/karchy/dns` changes the provider); trusted networks keep the router's DNS; saved networks are never rewritten, and a VPN's own DNS wins while it is up. The network panel (D-66, D-68) says the real state in its status line (no rotating phrases), shows one attention row only when something needs the person (networking off, airplane mode, the hardware switch, a sign-in page, a failed VPN, DNS blocked) with the action that resolves it, the VPN row, ping, loss, IP and gateway, the band, known and other networks, and "Network settings…", which opens Settings › Network at the connection. Airplane mode (`karchy-airplane`, the airplane key): every radio off with rfkill, kept across reboots by systemd-rfkill, with an on-screen message and the `net.airplane` bar icon Privacy (D-79): no hostname in DHCP requests, IPv6 temporary addresses, and avahi (which announces this computer's name) runs only while a trusted network is connected (`karchy-network-privacy`). | [O] + [New] |
| Bluetooth | bluez + shell panel | [O] |
| Printing + scanning | Optional feature (Quick install › System features), D-38 | [O] + [New] |
| Audio | PipeWire + WirePlumber | [O+C] |
| Laptop power | power-profiles-daemon (Arch) with amd-pstate; suspend on idle; suspend-then-hibernate after 2 h | [New] |
| Mirrors | rate-mirrors weekly with safety checks (D-29) | [C] tool, [New] safety |
| Dedup | bees on btrfs, from karchy's fork (`karchy-bees`, D-85), on by default (the installer asks; D-86). `karchy-bees.service` deduplicates the system disk with karchy's options and limits from `/usr/share/karchy/bees.conf` (yours go in `/etc/karchy/bees.conf`): at most one core and only idle CPU, a memory ceiling, a hash table sized from the disk; never rewrites snapper's snapshots, keeps preallocated space, logs no file names; AC power only on laptops. Off: `systemctl disable --now karchy-bees.service` | [New] |
| Secure Boot | sbctl + Microsoft keys, signed Limine, config hash enrollment (installer step) | [C] |
| Firmware | fwupd (menu entry) | [O] |
| AUR helper | paru (from `[cachyos]`) | [C] |
| Fonts | JetBrains Mono Nerd; Noto (+ CJK, emoji) | [O] |

## Desktop

| Area | Choice | Source |
|---|---|---|
| Compositor | Hyprland, Lua config with Omarchy's default/user layering and `o.*` helpers | [O] |
| Look | gaps 5/10, 2 px theme-accent border, square corners, no blur or shadow | [O] |
| Animations | Omarchy fast set, instant workspace switch | [O] |
| Layouts | Dwindle + per-workspace floating mode with titlebars (minimize, maximize, close): `karchy-hyprland-titlebars`, Omarchy's hyprbars fork built by karchy against Arch's Hyprland (D-60). Minimized windows come back from the bar's minimized indicator or Super+Shift+M | [O] + [New] |
| Workspaces | Per-monitor blocks of 10 | [O] |
| Special workspace | Drop-down terminal (no AI agent auto-start) | [O] |
| Opacity | Omarchy default (terminals 0.985/0.96) | [O] |
| Window rules | Omarchy tag system, pruned to installed apps | [O] |
| Idle | Shell screensaver + lock + screen off [O]; laptops on battery also suspend (then hibernate) after 15 minutes idle: `idle.suspend` (seconds, 0 = off) and `idle.suspendOnAC` in `~/.config/karchy/shell.json` [New] | [O] + [New] |
| Gestures | 3-finger swipe left/right = workspace | [O] |

## Shell (Omarchy Quickshell)

Kept:
- **Core:** host, IPC, plugin registry and CLI, bar engine, `omarchy` router, Commons and Ui, `shell.json`.
- **Services:** notifications (with the hover ✕), OSD, polkit, lock (with the time and date above the password field [New]; turn it off in Settings › Appearance › Lock screen, or `lock.clock: false` in `~/.config/karchy/shell.json`), idle, clipboard history, reminders, theme/background picker, speed tests, and the battery service (only on machines with a battery).
- **Menu:** the engine, used as the launcher (app search). The tree is in `menu.md`.
- **Floating bar** [New]: floats inset from the screen edge and docks on a monitor while a window there is maximized; `bar.style` auto, floating or docked (`karchy bar style`, Settings › Appearance). See `architecture.md`, "The bar: floating and docked".
- **Bar modules:** workspaces, clock, tray, audio, microphone, network, Bluetooth, display brightness, power, media, the indicators for kept features, and running VMs and containers (each shown only while something runs; D-63).
- **Updates indicator** [New] (D-61): shows while karchy or package updates wait (`karchy-update-check`, a user timer every 6 hours, no root); click opens the Updates window. A new karchy release is also announced once by notification. **Minimized indicator** [New] (D-60): shows while windows are minimized; click brings one back.
- **Updates window** [New] (D-81): what `karchy update` would install, before it runs: Arch news since the last update first, then the karchy release (with its release notes), apps by name, system components (the ones that need a restart first) and AUR packages, and the release channel, switched there after asking. Install runs `karchy update` in the floating terminal, which keeps the password prompt, AUR build review, config merges and the restart question. Opened by the updates indicator, Update › Update System, Settings › About and `karchy updates`; it reads `karchy-update --plan`.
- **Proposed, needs user approval:** the active-window title module.

Dropped: dock and app grid, emoji picker, intro animations and owe, night light, weather, world clock, AI usage, Tailscale, Dropbox, remote session, dev gallery.

## Theming

| Area | Choice | Source |
|---|---|---|
| Engine | Omarchy theme engine + templates | [O] |
| Themes | All 23 Omarchy themes + **nulifyer** (default, with its own backgrounds: nature photos recoloured to its palette, D-87); the picker shows them in color-wheel order by each theme's accent, red to violet, gray accents last (user 2026-11-16) | [O] + [New] |
| GTK | `adw-gtk-theme`; GTK 3 and GTK 4 (libadwaita) apps get the theme's full palette (`default/themed/gtk.css.tpl`, `gtk4.css.tpl`) and follow a switch live in open apps; checked with Thunar, GNOME Disks and Mission Center | [New] |
| Qt | Qt's GTK 3 platform theme (`QT_QPA_PLATFORMTHEME=gtk3`), so Qt apps take the generated GTK 3 colors and follow a theme switch live; checked with qpwgraph. No separate Qt template | [O] |
| VS Code | Generated theme extension; `settings.json` never edited. Pick "Karchy" once in the color theme picker | [New] |
| fish prompt | Native prompt + theme-color template: Arch logo, user@host, folder, git branch, a › that turns red on failure; earlier prompts collapse to › | [New] |
| fish listings | `ls`, `la`, `ll`, `lt`, `tree` and `l.` through eza (folders first, icons) | [New] |
| fish greeting | None (fish's "Welcome to fish" is turned off; your own `fish_greeting` still shows) | [New] |
| Terminal | foot include line. Starter configs for Ghostty, kitty and Alacritty (in `/etc/skel`) include the theme file the same way, so one installed later follows the theme; `karchy-restart-terminal` reloads open windows on a switch | [O] |
| Optional apps | Not in the base install; each follows the theme once installed, and nothing is written for an app that isn't. The app's own config is never edited: the user picks the karchy theme once. All retint open windows on a switch. Checked in the VM under nulifyer and flexoki-light, switching with each app open (2026-11-14) | |
| — Neovim | Plain color scheme from the theme (`default/themed/neovim-colors.lua.tpl`, VS Code's syntax colors, treesitter and LSP groups), linked to `~/.local/share/nvim/site/colors/karchy.lua`; select once with `:colorscheme karchy` (or `vim.cmd.colorscheme("karchy")` in your init.lua). LazyVim users can use `neovim.lua` in the current theme instead | [New] |
| — Claude Code | `~/.claude/themes/karchy.json`; pick "Karchy" once in `/theme` | [O] |
| — T3 Code | `~/.t3/userdata/themes/karchy.json`; pick it once in Settings › Appearance or with `t3 theme set karchy` | [O] |
| — Pi | `~/.pi/agent/themes/karchy-system.json`; pick "karchy-system" once in `/settings` › Theme | [O] |
| — Obsidian | A `Karchy` theme folder in each vault Obsidian knows (`<vault>/.obsidian/themes/Karchy`); pick it once in Settings › Appearance › Themes. A vault added later gets it on the next theme switch | [O] |
| — Keyboard RGB | The accent color on ASUS ROG (`asusctl`) and Framework 16 (`qmk_hid`) keyboards, when that tool is installed; untested on hardware | [O] |

## Apps in the base install

Every app below shows in Quick install as installed (D-71). Most can be removed there like any other app: the installer installs them as the user's own packages (`karchy-desktop`'s optdepends), not as dependencies. foot, Thunar and Xarchiver can't be removed, because karchy itself uses them; Quick install says why.

| Role | App | Source |
|---|---|---|
| Terminal | foot (server mode + footclient) | [O] |
| Browser | Brave Origin (`brave-origin-bin`, `[cachyos]`); removing it leaves links to another installed browser; PDFs open in the browser; video is decoded on the graphics card (VA-API flags in `brave-origin-flags.conf`, NVIDIA through `nvidia-vaapi-driver`) | [O] |
| File manager | Thunar + gvfs, gvfs-smb, gvfs-mtp, tumbler; right-click actions per D-36 and D-76; Send To › LocalSend; Create Document offers Text File and Markdown Document; Desktop is home (no desktop icons) | [New] |
| Default apps | Settings › Default apps, writing `mimeapps.list` (D-37) | [New] |
| Editor | None in the base (D-88): the user picks one in Quick install (VS Code, Zed and others). micro is the terminal editor (D-58) and Omawrite the notepad | [New] |
| Terminal editor | micro or nano, still open | |
| Images | imv | [O] |
| Media | mpv with hardware decoding config | [O] |
| Task manager | Mission Center (Ctrl+Shift+Esc); btop in a terminal | [New] + [O] |
| About | fastfetch | [O] |
| Screenshots | Omasnap (screenshot + annotation, `[omarchy]`), plus screen recording | [O] |
| Calculator | omacalc (`[omarchy]`) | [O] |
| Notepad | Omawrite (`[omarchy]`); plain text and Markdown files open in it | [O] |
| Disk utility | GNOME Disks | [O] |
| Disk usage | Disktree (`disktree-bin`, `[omarchy]`): treemap, mark and trash; Open in Disktree on folders in Thunar (D-74) | [O] + [New] |
| File sharing | LocalSend (`localsend-bin`, `[omarchy]`), port open only on trusted networks (router included, D-68); closed at boot until one connects | [O] + [New] |
| Settings | karchy Settings window (shell plugin, D-27, D-56): Displays (per monitor: resolution, refresh rate, scale, position, rotation, variable refresh, and under "Color and mirroring…" color depth 8/10-bit, color mode sRGB/wide/EDID/HDR with SDR brightness and saturation in HDR, and mirroring; each change that can blank a screen asks to be kept, D-79), Input, Network, SSH (the server switch with the command to connect, who can sign in: each authorized key with Remove, and a field taking a public key or a GitHub username; your own keys with Copy public key and Create a key…; the agent switch; D-78), Appearance, Default apps, About; more sections (Power, Printers) follow in phase 2. Network, on one scroll: Status (a card per active connection: addresses, gateway, DNS in use and whether it is encrypted, link, MAC), Saved networks (each opens in place: trusted network, connect automatically, metered, Wi-Fi band, private Wi-Fi address, IPv4 settings checked before saving, share, forget with Cancel focused; "Join hidden network…"), DNS (Automatic, Quad9, Cloudflare or custom servers; encrypted DNS; use on trusted networks too; encrypted only; each connection's state in words), VPN (the VPN package's mode, state and local devices on trusted networks, or plain VPN profiles with switches; importing a WireGuard file), Sharing and firewall (read-only), Advanced (Wi-Fi country, connectivity check) | [New] |
| Quick install | A window of its own (shell plugin `karchy.quick-install`, D-70): about 520 common apps from Arch's repositories, `[cachyos]`, `[omarchy]` and well-kept AUR packages, plus karchy's optional features, in categories with counts (All and Installed first), searched like fzf across every category; each row installs, opens or (once open in place, showing what it installs, from where, its size and its setup) removes the app, in a floating terminal. `karchy quick-install [search]`, Packages › Quick install | [New] |
| Web apps | Omarchy web-app mechanism; icons from the site, then Dashboard Icons (D-82) | [O] + [New] |
| Shell | fish, native config from the dotfiles user layer | [New] |
| Plugins | omarchy-vpn-plugin, omarchy-project-picker (Ctrl+Alt+P) | [New] |

## Mounts

- **USB:** udisks2 + udiskie automount with a notification [O].
- **Internal data disks:** fstab at `/mnt/<label>`, with `nofail` and `x-gvfs-show`, owned by the user, NTFS via `ntfs3`. The installer sets up existing ones; a notification offers new ones [New]. Built: `karchy-disk-fstab`, `karchy-disks-check`, `karchy-disk-keep`.
- **NAS:** browse via gvfs-smb. The menu's Setup › Network Shares › Keep a Share Mounted writes an fstab systemd automount (`nofail,_netdev,x-systemd.idle-timeout`) with root-only credentials; Remove a Kept Share undoes it (D-76) [New]. Built: `karchy-mount-keep`.

## Install tiers (D-28)

**Always:**
- desktop portals (`xdg-desktop-portal-hyprland` + `-gtk`)
- `systemd-oomd`
- `fstrim.timer`, monthly btrfs scrub, `smartd` disk-health warnings
- `paccache` cleanup, `.pacnew` alerts (`pacdiff`)
- the rate-mirrors timer
- a default-apps list: links → Brave Origin, PDF → Brave Origin, images → imv, video and audio → mpv, folders → Thunar, plain text and Markdown → Omawrite
- Thunar archive actions (`thunar-archive-plugin` + xarchiver + `7zip`) and the karchy right-click actions (D-36, D-40)
- `avahi` + `nss-mdns`
- LocalSend, GNOME Disks, Disktree, omacalc, Omawrite, Omasnap; Omarchy's theme path `~/.local/state/omarchy/current` links to karchy's, so the `[omarchy]` apps follow the theme (D-72)
- `xdg-user-dirs` (the home folders, Projects included), with Downloads, Projects, Pictures and Videos bookmarked in the file manager's sidebar at the first login (D-75); `man-db`
- `openssh`, `rsync`, `unzip`
- a check that the desktop draws on the graphics card: Settings › About shows what draws it (`karchy-hw-renderer`, through EGL like every Wayland app), and a login notification warns when it falls back to the processor (llvmpipe), with the likely cause and the fix; its actions are Open Settings and Don't show again, and About can turn the warning back on
- the Wi-Fi regulatory domain, set from the timezone when a Wi-Fi device appears (each boot) and when the timezone is changed from the menu (`iw`, `wireless-regdb`; ported from CachyOS). Without it the kernel stays in the world domain, with no 6 GHz. A `COUNTRY=XX` line in `/etc/karchy/wifi-country` overrides it; Settings › Network › Advanced sets or clears it (`karchy-network-country`).

**Detected at install:**
- CPU microcode (`amd-ucode` or `intel-ucode`).
- **NVIDIA GPU:** the driver follows the GPU generation, read from the PCI device ID in sysfs (`karchy-hw-nvidia-generation`; with several NVIDIA GPUs the newest generation decides):
  - Turing and newer (device ID 0x1e00 and up): `karchy-nvidia`, with `linux-cachyos{,-lts}-nvidia-open` and `nvidia-utils`. The open modules need the GSP firmware these cards have.
  - Maxwell, Pascal and Volta (0x1340 to 0x1dff): `karchy-nvidia-580xx`, with `linux-cachyos{,-lts}-nvidia-580xx` and `nvidia-580xx-utils`, NVIDIA's 580 legacy branch. That driver depends on its 32-bit libraries, so these machines also get `[multilib]` enabled. NVIDIA VA-API uses the direct backend on every generation (the EGL backend has been broken since driver 525).
  - Kepler and older: no NVIDIA driver (NVIDIA's current drivers dropped them; the last was 470). The installer says so, and nouveau drives the card.

  Both packages add `libva-nvidia-driver` and early KMS (NVIDIA's modules in the initramfs). Early KMS breaks resume from hibernation (NVIDIA open-gpu-kernel-modules issue #1343, still open on 620), so both turn hibernation off in `sleep.conf.d` and the lid only suspends (D-78). The installer enables NVIDIA's suspend/resume services only for the 580 driver; from 595 the open driver keeps video memory across suspend itself. `karchy-nvidia-580xx` provides and conflicts with `karchy-nvidia`, so only one is installed and anything that checks for `karchy-nvidia` (such as GPU containers) finds either.
- **Battery:** the shell battery service (low and critical warnings), suspend-then-hibernate, power-profiles-daemon. Automatic timezone is not built yet: `tzupdate` is AUR-only and asks a web service where you are (needs a decision).
- **Framework** (DMI vendor): `framework-system` (`framework_tool`: charge limit, firmware and EC state).
- **Fingerprint reader:** Set Up Fingerprint is offered in the menu (Setup › Security) when a reader is found; it enrolls a finger, then adds fprintd to polkit and the lock screen, not sudo (D-14).
- **Firmware in Setup Mode:** the Secure Boot step (D-31).

**Installer choice:** bees dedup, on by default (D-86).

**Optional (Quick install › System features, D-70):**
- Printers & scanners (package `karchy-printing`, D-67): CUPS with Omarchy's hardened cups-browsed (own user, sandboxed, driverless queues only), `system-config-printer`, `sane`, `sane-airscan`, `simple-scan`, and `ipp-usb` for driverless USB printers and scanners (D-38).
- Containers (package `karchy-containers`, D-67): rootless Podman (`podman`, `crun`, `netavark`, `aardvark-dns`, `passt`), `podman-docker` for the `docker` command, `docker-compose` against the user's Podman socket (`DOCKER_HOST` via `/usr/lib/environment.d`, the socket enabled for every user by the package), and `nvidia-container-toolkit` with karchy-nvidia; the Containers panel and window (D-63).
- Virtual machines: `qemu-desktop`, `edk2-ovmf`, `swtpm`, `spice-gtk`; `karchy vm`, VMs in `~/VMs` (no copy-on-write), no libvirt; the VMs panel and window (D-63).
- Home backup to the NAS (phase 7).

## Installed later by the user (not in base)

dotnet, go, zig, rust, bun, AI CLIs (from pacman, `[omarchy]` or the AUR), Steam, Flatpak, a password manager (the user's is Proton Pass).
