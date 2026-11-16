# What Omarchy and CachyOS do that karchy doesn't

Date: 2026-11-14. Read-only research. Sources:
- karchy at `/home/nulifyer/Projects/karchy`: `.agents/PLAN.md`, `.agents/DECISIONS.md`, `docs/*.md`, `install/`, `packaging/pkgbuilds/`, `system/`, `bin/`, `shell/`.
- Omarchy v4.5.0 at `/home/nulifyer/Projects/Omarchy/reference/omarchy-v4.5.0` ("O:" below), and the earlier audit in `/home/nulifyer/Projects/Omarchy/audit/`.
- CachyOS: this host. It is the RTX 5080 desktop, running CachyOS (`pacman -Ql`, `/proc/config.gz`, `/proc/driver/nvidia/params`). Also wiki.cachyos.org (gaming, sched-ext and general system tweaks pages).

Classes: **(a)** base, **(b)** installer-detected, **(c)** Optional feature in Settings, **(d)** skip. **[dropped]** means karchy dropped the item on purpose. Such items are flagged only where the reason looks wrong.

## 0. Findings that are bugs today

1. **Wi-Fi band pinning, and the band shown in the network panel, need `iw`, and karchy never installs it.**
   - `bin/karchy-network-band` (`read_link`) and `bin/karchy-network-status:41,115` call `iw dev … link`.
   - On this host, `iw` is pulled in only by `cachyos-settings` and `wireless-regdb` (`pacman -Qi iw`). Neither is in any karchy package.
   - On a fresh karchy, `print_status` therefore prints nothing and the band section never shows.
   - The VM has no Wi-Fi, so testing did not catch this.
2. **There is no wireless regulatory domain.**
   - `wireless-regdb` is only an *optional* dependency of `linux-cachyos` and `linux-cachyos-lts`.
   - Nothing sets the country: no Omarchy `set-wireless-regdom.sh`, no CachyOS `iw-set-regdomain`.
   - The kernel then stays in the world domain `00`. In that domain 6 GHz is unavailable and many 5 GHz channels are passive-only. This directly undercuts the band feature's "6 GHz" option.
3. **The webcam overlay can't be reached from the UI.**
   - D-48 keeps it, but karchy dropped the Capture submenu (`docs/menu.md`), so the only way to start it is `karchy-capture-screenrecording --with-webcam` from a terminal.
   - Alt+Print (`karchy/hypr/bindings.lua:68`) records with no audio and no webcam.
   - The resize keys (O: `default/hypr/bindings/utilities.lua:43-44`) are unbound.
4. **The bar's screen-recording indicator, when not recording, opens a menu entry that doesn't exist.** `shell/plugins/bar/indicators/ScreenRecording.qml:41` runs `karchy-menu toggle trigger.capture.screenrecord`, but `default/karchy/karchy-menu.jsonc` has no `trigger.*` entries (only the i18n strings remain, in `default/i18n/en/menu.json:336-368`).
5. **Documented but not built.** `docs/components.md:118-119` lists these in the Detected tier, but `install/setup.sh` detects only battery, NVIDIA and VM:
   - `tzupdate` (battery)
   - `framework-system` (Framework)
6. **The `etc/` tuning audit was never applied.** The "Keep" rows of `docs/ownership-audit.md` (section "Omarchy's system tuning") are still "Not decided yet", and none of them are in `system/`:
   - Wi-Fi power save off
   - ARP sysctl, BBR/fq and MTU probing
   - resolved multicast off
   - faster shutdown, mount events, nofile
   - I/O scheduler, faillock, dirmngr
   - Thunderbolt in the initramfs
   - keep-shell

   One of these matters right now: karchy enables both avahi and systemd-resolved, and resolved's mDNS and LLMNR are on by default. This host shows `+LLMNR +mDNS`, so two mDNS responders run side by side.

## 1. Omarchy: what karchy doesn't have

### 1a. System tuning and services (`etc/`, `default/systemd`, `install/config`)

| Item | Omarchy path | karchy status | Class | Reason |
|---|---|---|---|---|
| Wi-Fi power save off | `etc/NetworkManager/conf.d/omarchy-wifi-powersave.conf` | missing (audit said Keep) | **a** | Stops idle latency spikes and link drops (the Framework's MediaTek RZ616/MT7922 is prone to these) |
| ARP announce/ignore | `etc/sysctl.d/90-omarchy-arp.conf` | missing (Keep) | **a** | Framework docked with Ethernet and Wi-Fi on the same LAN |
| BBR + fq + `tcp_mtu_probing` | `etc/sysctl.d/99-omarchy-sysctl.conf` (network half) | missing (Keep) | **a** | Less bufferbloat, fewer SSH stalls. The zram half: (d), since karchy uses zswap (D-10) |
| resolved mDNS/LLMNR off | `etc/systemd/resolved.conf.d/10-disable-multicast.conf` | missing (Keep) | **a** | avahi is in base (D-28/D-38). Avoids two responders |
| Faster shutdown (stop timeout 5 s) | `etc/systemd/system.conf.d/10-faster-shutdown.conf`, `user@.service.d/` | missing (Keep) | **a** | A hung unit no longer holds shutdown for 90 s. CachyOS uses 10 s |
| Mount-event rate limit | `etc/systemd/system.conf.d/20-mount-events.conf` | missing (Keep) | a (low) | Rare boot delay |
| NOFILE limits | `etc/systemd/{system,user}.conf.d/20-omarchy-nofile.conf` | missing (Keep) | a (low), or fold into Gaming (c) | systemd's 524288 hard limit is already enough for most uses |
| Kyber I/O scheduler | `etc/udev/rules.d/60-omarchy-io-scheduler.rules` | missing (Keep) | **a**, but use CachyOS's per-type rule (§2) | The desktop's 3.6 TB data disk, if it is an HDD, wants bfq rather than kyber |
| faillock deny=10 | `etc/security/faillock.conf`, `install/config/increase-lockout-limit.sh` | missing (Keep) | **a** | Three typos lock sudo for 10 minutes. karchy already sets `passwd_tries=10` |
| dirmngr keyserver list | `etc/gnupg/dirmngr.conf` | missing (Keep) | a (low) | `pacman-key` refreshes when one keyserver is down |
| Thunderbolt module in the initramfs | `etc/mkinitcpio.conf.d/thunderbolt_module.conf` | missing (Keep) | **b**: `/sys/bus/thunderbolt/devices/domain*` exists | The Framework 13 AMD has USB4. A dock keyboard must work at the LUKS prompt |
| keep-shell on logout | `etc/systemd/user/wayland-wm@hyprland.desktop.service.d/10-keep-shell.conf` | missing (Keep) | a (low) | Cosmetic |
| `linux-modules-cleanup` (`kernel-modules-hook`) | `install/config/enable-services.sh` | missing | **a** | After a kernel upgrade, the running kernel's modules are deleted, so a USB stick needing `exfat` or `uas`, or a USB NIC, fails until reboot. This breaks "USB just works" |
| Unmount gvfs FUSE before sleep | `default/systemd/system-sleep/unmount-fuse` | missing | **a** | karchy ships gvfs and gvfs-smb (Thunar, NAS browsing). A hung gvfsd-fuse can make suspend fail silently |
| `bt-agent` pairing agent (`bluez-tools`) | `default/systemd/user/bt-agent.service` | missing | **a**, after a test | `karchy-bluetooth-device pair` runs `bluetoothctl pair` with its output sent to /dev/null, so passkey or confirm pairing (keyboards, some phones) has no agent to answer it. Test a keyboard and a headset in phase 4. `bluez-tools` is tiny |
| First-login "no network" prompt | `install/user/first-run/wifi.sh` | missing | **a** | The installer doesn't carry the live ISO's Wi-Fi over (no iwd or NM code in `install/`). The first Framework boot has no network and nothing says so. Either copy the iwd PSK into an NM keyfile at install, or notify and open the network panel |
| Reboot-needed prompt after updates | `bin/omarchy-update-restart` | missing (`bin/karchy-update` only reloads Hyprland and the shell) | **a** | Detects a kernel replaced under the running one, or a deleted Hyprland binary. CachyOS's `cachyos-reboot-required.hook` does the same (§2) |
| SSH keepalive | `install/config/ssh-keepalive.sh` | missing | a (low) | Dead SSH sessions are noticed within a minute. Small, dev-friendly |
| Wireless regdom from timezone | `install/hardware/set-wireless-regdom.sh` | missing | **a**, using CachyOS's version (§2) | See bug 2 |
| `hid_apple fnmode=2` | `install/hardware/fix-fkeys.sh` | missing | a (low) / d | F-keys stay F-keys on Keychron/Lofree-style keyboards on the desktop. Harmless elsewhere |
| NM wait-online mask; networkd retirement | `install/hardware/network.sh`, `enable-services.sh` | missing | d | karchy's own installer never enables networkd. Nothing waits on network-online |
| Connectivity URL `ping.omacom.io` | `etc/NetworkManager/conf.d/omarchy-connectivity.conf` | [dropped] D-15 | d | Arch's `20-connectivity.conf` (ping.archlinux.org) already ships with networkmanager. Reason is fine |
| USB autosuspend off | `etc/modprobe.d/omarchy-usb-autosuspend.conf` | [dropped] (audit: Skip) | d | Reason is fine (battery) |
| File-watcher sysctl | `etc/sysctl.d/90-omarchy-file-watchers.conf` | missing | d | Arch's `10-arch.conf` already sets 524288 |
| timesyncd `ntp.omarchy.org` | `default/systemd/timesyncd.conf.d/10-omarchy.conf` | missing | d | Arch pool is fine |
| oomd app.slice | `default/systemd/user/app.slice.d/10-oomd.conf` | present (`default/systemd/user/app.slice.d`) | — | Already there |

### 1b. Hardware steps (`install/hardware`, `install/user/hardware`)

| Item | Omarchy path | karchy status | Class | Detection / reason |
|---|---|---|---|---|
| Vulkan driver by GPU vendor | `install/hardware/vulkan.sh` | missing. Mesa comes in via Hyprland, but nothing in karchy pulls `vulkan-radeon` (checked deps of mpv, ffmpeg, libplacebo, gpu-screen-recorder) | **b** | `lspci` VGA/Display vendor AMD → `vulkan-radeon`; Intel → `vulkan-intel`. The Framework 13 AMD otherwise has no Vulkan |
| NVIDIA early KMS: `MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)`, `kms` hook removed | `install/hardware/nvidia.sh`; on CachyOS, chwd writes `/etc/mkinitcpio.conf.d/10-chwd{,-kms}.conf` (present on this host) | missing. `system/mkinitcpio.conf.d/karchy.conf` keeps `kms`; `karchy-nvidia` is depends only | **b** (`karchy-nvidia` ships the drop-in) | **Dropped reason is wrong for karchy.** PLAN puts "Omarchy's NVIDIA script" out of scope on the assumption chwd covers it (audit SYS-14), but karchy doesn't install chwd. On CachyOS this is the default for the RTX 5080 |
| `lib32-nvidia-utils` | `install/hardware/nvidia.sh` | missing (karchy has no multilib) | **c** (Gaming) | Only Steam and Wine need it |
| F13 AMD internal-mic profile "HiFi (Mic1, Mic2, Speaker)" | `install/user/hardware/framework/fix-f13-amd-audio-input.sh` | missing | **b**: DMI `sys_vendor=Framework`, `product_name` contains "Laptop 13 (AMD" | PLAN keeps "quirks the Framework 13 AMD needs", and this is one of them. Better as a WirePlumber rule than as Omarchy's one-shot `pactl` call |
| VM: no animations, opaque windows | `install/user/hardware/vm-no-animations.sh` | missing | b (low): `karchy-vm` | CPU rendering in virt-manager. Workspace switching is already instant |
| nouveau software cursor | `install/user/hardware/fix-nouveau-cursor.sh` | missing | d | karchy always installs the NVIDIA driver |
| Intel: `sof-firmware`, `thermald`, `intel-lpmd`, `intel-media-driver`, IPU7, Wi-Fi 7 EHT | `install/hardware/intel/*` | missing | d for now; b if an Intel machine appears | No Intel target (PLAN Out) |
| Elgato Cam Link 4K relay | `install/hardware/fix-elgato-camlink-4k.sh` | missing | d (b if the user owns one) | Only matters if that device is used for webcam-in-recording on the desktop |
| ASUS, Apple, Dell, Surface, Tuxedo, Qualcomm, Lenovo, GB10, N1x, speaker tuning | `install/hardware/*` | [dropped] D-48 | d | Reason is fine |
| Framework 16 `qmk-hid` | `install/hardware/framework16.sh` | [dropped] D-48 | d | Reason is fine |

### 1c. Commands and shell (bin/, shell/)

| Item | Omarchy path | karchy status | Class | Reason |
|---|---|---|---|---|
| Capture submenu (screenrecord with audio/webcam options, OCR text, QR decode, color picker) | `default/omarchy/omarchy-menu.jsonc:142-152` | [dropped] menu.md | **Reason partly wrong**: it was also the only entry point to the kept webcam overlay. See §3 |
| `hw-webcam` predicate | `bin/omarchy-hw-webcam` | not vendored | a (with §3) | Hides the webcam option when there is no camera. Cheap udev-db read |
| `capture-qr`, `capture-text` | `bin/omarchy-capture-{qr,text}` | [dropped] | d | Omasnap covers screenshots. QR decode would need `zbar` |
| Stay-awake indicator, DND indicator | `shell/plugins/bar/indicators/{StayAwake,Dnd}.qml`, `bin/omarchy-toggle-{idle,notification-silencing}` | [dropped] with the toggles. The idle service still keeps `stayAwake` state (`shell/plugins/services/idle/Service.qml:17-47`) but nothing can set it | d. Remove the dead state, or put a Stay-awake row in the power panel | Browsers and mpv inhibit idle on their own |
| `install-gaming-steam`, `install-gaming-gpu-lib32`, `install-gaming-xbox-controllers` (`xpadneo-dkms` + `input` group) | `bin/omarchy-install-gaming-*` | [dropped] D-19 (Steam installed by the user) | **c** (Gaming) | **D-19's reason is weaker than it looks.** Steam on karchy needs `[multilib]` turned on (karchy never does), the right lib32 Vulkan driver, and `ntsync`. That is "packages plus setup", which is D-28's own definition of an Optional feature |
| `snapshot` (create/restore from menu) | `bin/omarchy-snapshot` | not in menu | d | Limine snapshot entries are enough |
| `kernel` picker | `bin/omarchy-kernel` | [dropped] menu.md | d | Reason is fine |
| `hibernation-setup` | `bin/omarchy-hibernation-setup` | done by the installer (D-32) | — | Already there |
| `toggle-hybrid-gpu` (supergfxd) | `bin/omarchy-toggle-hybrid-gpu` | missing | d | No hybrid target |
| `crash-watch`, `upload-log`, `debug`, `windows-key`, `transcode` | `bin/` | [dropped] | d | AI, telemetry, or niche |
| `mpv-mpris` | `install/omarchy-base.packages` | missing | a (low) | The bar's media module and the media keys can't see mpv without it |
| `exfatprogs` | `install/omarchy-base.packages` | missing | a (low) | GNOME Disks can format a USB stick as exFAT only with `mkfs.exfat` |
| `bolt` | `install/omarchy-base.packages` | missing | **b**: a Thunderbolt domain whose `security` is `user` or `secure` | Dock authorization. Not needed when the domain reports `none` |
| `hyprland-preview-share-picker` | `config/hypr/xdph.conf` | missing | d | xdph's own picker works |

## 2. CachyOS: what karchy doesn't have

### What karchy already gets from CachyOS packages

karchy uses the generic `[cachyos]` repo, listed first (D-45). That repo is not v3 or v4, so `cachyos-extra-v3` builds such as bluez, fwupd and wireplumber come from Arch instead. From the packages karchy installs, it gets:
- **`linux-cachyos` and `-lts`**, with this kernel config (`/proc/config.gz`):
  - `CONFIG_SCHED_CLASS_EXT=y`
  - ADIOS I/O scheduler built in (not the default)
  - `ZSWAP_DEFAULT_ON=y`, zstd, shrinker on
  - `TRANSPARENT_HUGEPAGE_ALWAYS=y`
  - `NTSYNC=m`
  - `HZ=1000`
- **Prebuilt `-nvidia-open` modules and CachyOS's `nvidia-utils` (620.70).** The utils bring the nouveau/nova blacklist and the softdeps (`/usr/lib/modprobe.d/nvidia-utils.conf`).
- **CachyOS builds of `pacman`, `mesa`, `linux-firmware` and `power-profiles-daemon`.** CachyOS's power-profiles-daemon turns AMD core boost off on powersave (wiki: general_system_tweaks).
- **`paru`, `rate-mirrors`, `cachyos-keyring` and `cachyos-mirrorlist`.**

karchy does **not** install any of these, so it gets none of their settings: `cachyos-settings`, `chwd`, `cachyos-hooks`, `ananicy-cpp`, `scx-*`, `cachyos-hello`, `cachyos-kernel-manager`, `cachyos-rate-mirrors`, `cachyos-snapper-support`, `cachyos-fish-config`, `cachyos-micro-settings`.

### 2a. cachyos-settings (1:1.4.4; files under `/usr/lib/...` on this host)

| Item | File | Class | Reason |
|---|---|---|---|
| Wireless regdom from timezone, at device add and on timezone change | `/usr/lib/iw-set-regdomain`, `cachyos-iw-set-regdomain.{path,service}`, `85-iw-regulatory.rules` (ISC licence) | **a** + depend on `iw` and `wireless-regdb` | Bugs 1 and 2. Better than Omarchy's one-shot: it follows a timezone change, and karchy plans `tzupdate` on laptops |
| I/O scheduler per device type: kyber on NVMe, mq-deadline on SATA SSD, bfq on HDD | `60-ioschedulers.rules` | **a** | Replaces Omarchy's kyber-everywhere rule. The HDD data disk gets bfq |
| Writeback caps for slow disks: 16 MB USB, 256 MB removable/HDD/SD | `61-writeback-limits.rules` | **a** | "USB just works": copies finish when they say they did, and eject or suspend doesn't stall |
| HDA power save off on AC (pops/crackle) | `20-audio-pm.rules`, `/usr/lib/udev/audio-pm-ctl` | **a** | The Framework's Realtek codec, and the desktop's onboard and NVIDIA HDMI audio, all use `snd_hda_intel` |
| THP shrinker 409 + `defrag=defer+madvise` | `/usr/lib/tmpfiles.d/thp-shrinker.conf`, `thp.conf` | **a** | karchy runs the CachyOS kernel (THP=always) without CachyOS's counter-setting, so it uses more memory. Two lines |
| Journal cap (50M) | `/usr/lib/systemd/journald.conf.d/00-journal-size.conf` | a (low), with a larger value (e.g. 500M) | Arch caps at 10% of the filesystem (up to 4G). 50M is too small for debugging |
| Stop timeout 10 s (start 15 s) | `system.conf.d/00-timeout.conf`, `user.conf.d/00-timeout.conf` | a (stop only) | Same goal as Omarchy's. A 15 s start timeout is risky: it skips slow mounts |
| `nmi_watchdog=0` + watchdog blacklist (`sp5100_tco` on Ryzen) | `sysctl.d/70-cachyos-settings.conf`, `modprobe.d/blacklist.conf` | a (low) | Small power saving on the Framework. The Arch wiki laptop page recommends it |
| `kernel.printk = 3 3 3 3` | same sysctl | a, but better as `quiet loglevel=3` on the cmdline (`install/base.sh:146`) | Kernel messages can overwrite the text-console LUKS prompt (D-12). A sysctl applies too late for the initramfs |
| `kernel.sysrq=1` | same | a (low, user call) | REISUB recovery on a hard hang. Arch default is 16 (sync only) |
| swappiness 100, `page-cluster 0`, `vfs_cache_pressure 50`, dirty ratios 10/3 | same | d | Tuned for zram (their own comment says page-cluster 1 for SSD swap). karchy uses zswap plus a disk swap file (D-10). Dirty ratios are only worth taking together with `61-writeback-limits` |
| zram generator, `30-zram.rules`, xswap generator | `zram-generator.conf`, `30-zram.rules`, `xswap-generator` | d [D-10] | karchy chose zswap |
| `ntsync` module load | `modules-load.d/ntsync.conf` | **c** (Gaming) | Proton NTSYNC (wiki: on by default in proton-cachyos) |
| NVIDIA runtime PM `power/control=auto` | `71-nvidia.rules` | b (`karchy-nvidia`, low) | Only matters on hybrid laptops. No effect on the 5080 desktop |
| `NVreg_InitializeSystemMemoryAllocations=0` | `modprobe.d/nvidia.conf` | d | A performance-for-security trade. Live value on this host is 0 |
| HDD APM/spin-down off (`hdparm -B 254 -S 0`) | `69-hdparm.rules` | d (b if the data disk is an HDD and its spin-ups bother the user) | Taste. Needs `hdparm` |
| SATA ALPM `max_performance` | `50-sata.rules` | d | Costs power for little gain |
| oomd per-slice defaults, `session.slice` omit | `system.slice.d/`, `user/slice.d/`, `session.slice.d/` | d | karchy has its own oomd config (`system/systemd/oomd.conf.d/10-karchy.conf`) plus app.slice |
| `user@` Delegate cpu/cpuset/io | `user@.service.d/delegate.conf` | d | Only needed for scx/ananicy-style tools |
| rtkit log level, audio limits, hpet/rtc/cpu_dma_latency group | `rtkit-daemon.service.d`, `limits.d/20-audio.conf`, `40-hpet…`, `99-cpu-dma…` | d | PipeWire uses rtkit. Pro-audio only |
| `NetworkManager dns=systemd-resolved` | `/usr/lib/NetworkManager/conf.d/dns.conf` | d (optional) | NM already picks resolved through the stub `resolv.conf` link (`install/base.sh:201`). Being explicit doesn't hurt |
| `pci-latency` | `pci-latency.service` | d | Not enabled on this host either |
| timesyncd cloudflare; coredump 3d; amdgpu SI/CIK; X11 touchpad; GNOME login schema; debuginfod | various | d | Not relevant |
| Tools: `game-performance`, `dlss-swapper`, `eac-setup` | `/usr/bin/` | c (Gaming): ship a small `game-performance`-style wrapper (powerprofilesctl performance while the game runs) | `cachyos-settings` itself can't be installed without zram and ananicy coming along |
| Tools: `kerver`, `topmem`, `paste-cachyos`, `cachyos-bugreport`, `sbctl-batch-sign`, `zink-run` | `/usr/bin/` | d | karchy's Secure Boot verifies the Limine config hash instead (D-31) |

### 2b. Other CachyOS components

| Item | Source | Class | Reason |
|---|---|---|---|
| chwd GPU profiles (driver packages, early KMS, `lib32`, `egl-wayland`, `opencl-nvidia`, `nvidia-settings`, VM `vulkan-virtio`) | `/var/lib/chwd/db/pci/graphic_drivers/profiles.toml` | b (karchy's own detection, not chwd) | NVIDIA: add early KMS. `egl-wayland` already comes as a dependency of `nvidia-utils`. AMD: `vulkan-radeon`. `opencl-nvidia` and `nvidia-settings`: d. VM: `vulkan-virtio`, low |
| chwd Framework profile | `/var/lib/chwd/db/pci/framework/profiles.toml` | d | Only the Framework 12 (`iio-sensor-proxy`) |
| `cachyos-reboot-required.hook` | `cachyos-hooks` | **a** (in `karchy update` or an alpm hook feeding the updates indicator) | Same need as Omarchy's update-restart. Targets kernel, ucode, firmware, mesa, nvidia, systemd, cryptsetup |
| ananicy-cpp + rules | cachyos-settings dependency | d | The CachyOS wiki says don't combine it with GameMode, and lists it as a common cause of crashes alongside scx. Not minimal |
| sched-ext (`scx-scheds`, `scx_loader`, scx-manager) | wiki `/configuration/sched-ext/` | d | Not enabled by default even on CachyOS. The kernel already supports it, so the user can `pacman -S scx-scheds` |
| cachyos-kernel-manager | package | d [menu.md: kernel picker dropped] | Reason is fine |
| cachyos-hello tweaks: psd, oomd, bpftune, Bluetooth, ananicy, cachy-update tray | `/usr/bin/cachyos-hello` strings | d. karchy has oomd and Bluetooth, plus its own updates indicator (D-61) | — |
| cachyos-hello fixes: remove db lock, remove orphans, clear cache, reset keyrings, rank mirrors, reinstall all | same | d. Maybe later: "remove stale `db.lck`" inside `karchy update` | paccache timer and rate-mirrors timer already exist (D-29) |
| cachyos-hello DNS switcher (DoT/DoH via blocky) | same | d [D-44] | Reason is fine (the VPN plugin owns DNS) |
| cachyos-hello VRAM management (`dmemcg-booster`), Winboat | same | d | Gaming or niche |
| Gaming: `cachyos-gaming-meta` (`proton-cachyos-slr`, umu, `wine-cachyos-opt`, winetricks, lib32 libs), `cachyos-gaming-applications`, shader-cache env (`MESA_SHADER_CACHE_MAX_SIZE`, `__GL_SHADER_DISK_CACHE_SIZE`) | wiki `/configuration/gaming/` | **c** (Gaming) | See below |
| zram by default | wiki | d [D-10] | — |
| `cachyos-rate-mirrors`, `cachyos-snapper-support`, `cachyos-fish-config`, `cachyos-micro-settings` | packages | d. karchy has its own versions (D-29, snapper template, fish prompt, D-58) | — |

**A proposed "Gaming" Optional feature** (`default/karchy/features.json`). In one click:
- enable `[multilib]`
- install `steam`, plus `lib32-nvidia-utils` (karchy-nvidia) or `lib32-vulkan-radeon` (AMD)
- add `proton-cachyos-slr` and the `ntsync` module load
- add a small performance wrapper
- optionally `xpadneo-dkms`, which is in `[cachyos]`, for Xbox controllers over Bluetooth
- optionally a shader-cache `environment.d` file

The user would need to revise D-19 for this.

## 3. The three kept Omarchy features: where they should live

**Webcam overlay (recording).**
- Where it is now: `bin/karchy-capture-screenrecording` (`--with-webcam`, `--webcam-size`), `bin/karchy-capture-webcam-{list,resize}`, and window rules in `default/hypr/apps/webcam-overlay.lua`. There is no UI path (bugs 3 and 4).
- Recommendation: a **recording chooser**, opened by Alt+Print when nothing is recording and by the bar recording indicator.
  - Rows: Region or Full screen, Desktop audio, Microphone, Webcam (shown only when a camera exists, via a ported `hw-webcam` or a non-empty `karchy-capture-webcam-list`), webcam size S/M/L, Start.
  - It remembers the last choices in `~/.config/karchy/recording.json`.
  - It needs no new keybinding (D-17). Overlay size is set in the chooser instead of with Omarchy's Super+Alt+[ / ].
  - It could reuse the menu engine (a `capture.screenrecord` entry, which is what the indicator already expects), but that needs approval under D-18.
  - It doesn't need to be a Settings section.

**Wi-Fi band pinning.**
- Where it is now: the network panel's band row (`shell/plugins/panels/network/Panel.qml:77-260`) and `bin/karchy-network-band`. NetworkManager saves the pin on the connection profile (`802-11-wireless.band`).
- Recommendation: **keep the quick control in the bar network panel**. That is where you are when you notice a slow link. Also show the saved pin per network in **Settings › Network** (`shell/plugins/settings/NetworkSection.qml`, next to Trusted networks), so pins on networks not in range can be seen and cleared.
- First fix bugs 1 and 2 (`iw`, `wireless-regdb`, regdomain), or the row never appears and 6 GHz never works.

**Wi-Fi QR share.**
- Where it is now: its own panel `shell/plugins/panels/wifiqr` (`karchy.wifiqr`), summoned from the network panel header (`Panel.qml:132,225`), with `bin/karchy-network-qr` and `qrencode` (already in `karchy`'s depends).
- Recommendation: **leave it where it is.** Sharing is a one-off action on the current network, which is a panel job.
- Optional extra: a "Share" button per saved network in Settings › Network, which would need `karchy-network-qr` to take a connection UUID instead of an interface. Not a priority.

## 4. Merged prioritized list

### Base (a), roughly in priority order
1. Add `iw` and `wireless-regdb` to the `karchy` (or `karchy-desktop`) depends, and port CachyOS's `iw-set-regdomain` with its path unit and udev rule. Fixes band pinning and 6 GHz (cachyos-settings; bug 1).
2. `kernel-modules-hook` with `linux-modules-cleanup.service` enabled. USB keeps working after kernel updates (O: `install/config/enable-services.sh`).
3. Reboot-needed notice after kernel, firmware, systemd or NVIDIA updates, in `karchy update` and the updates indicator (O: `bin/omarchy-update-restart`; CachyOS: `cachyos-reboot-required.hook`).
4. A recording chooser with audio and webcam options, and a fix for the broken indicator click. This makes the kept webcam overlay usable (§3; `ScreenRecording.qml:41`). Needs approval under D-17/D-18.
5. Apply the audit's pending "Keep" set (`docs/ownership-audit.md`):
   - Wi-Fi power save off
   - ARP sysctl, BBR/fq/MTU probing
   - resolved multicast off
   - stop timeout
   - faillock 10
   - dirmngr
   - keep-shell
6. CachyOS udev set: per-type I/O scheduler (instead of Omarchy's kyber), slow-disk writeback caps, and HDA power save off on AC (`60-ioschedulers`, `61-writeback-limits`, `20-audio-pm`).
7. The gvfs FUSE unmount sleep hook. Suspend can fail with a NAS share open (O: `default/systemd/system-sleep/unmount-fuse`).
8. A first-login "no network" notification that opens the network panel, or carrying the live ISO's Wi-Fi over at install (O: `install/user/first-run/wifi.sh`).
9. THP shrinker and defrag tmpfiles, because karchy runs the CachyOS kernel (cachyos-settings `thp*.conf`).
10. `quiet loglevel=3` on the cmdline, to keep the LUKS prompt clean (`install/base.sh:146`).
11. Test `bt-agent` (`bluez-tools`) with keyboard and phone pairing, and add it if pairing fails (O: `default/systemd/user/bt-agent.service`).
12. Low priority:
    - journald cap (around 500M)
    - `nmi_watchdog=0` and the watchdog blacklist
    - `sysrq=1` (user call)
    - `mpv-mpris`, `exfatprogs`
    - SSH keepalive
    - `hid_apple fnmode=2`
    - mount-event limit, NOFILE

### Detected (b)
1. **NVIDIA:** `karchy-nvidia` ships the early-KMS mkinitcpio drop-in (MODULES, no `kms`). chwd does this on CachyOS, but karchy has no chwd. Detection: `has_nvidia`. Optionally add `71-nvidia.rules` runtime PM for hybrid machines later.
2. **AMD GPU:** `vulkan-radeon` (Intel: `vulkan-intel`, plus `intel-media-driver` if an Intel machine appears). Detection: `lspci` VGA/Display vendor (O: `install/hardware/vulkan.sh`).
3. **Framework 13 AMD:**
   - Internal-mic profile, as a WirePlumber rule (O: `install/user/hardware/framework/fix-f13-amd-audio-input.sh`). Detection: DMI.
   - `framework-system` (in extra), already documented in components.md. A charge limit in Settings › Power could instead use the kernel's `charge_control_end_threshold`.
4. **Battery:** `tzupdate`, documented but not built (components.md:118). It pairs with the regdomain path unit.
5. **Thunderbolt/USB4:** `thunderbolt` module in the initramfs, and `bolt` when the domain's security is not `none`. Detection: `/sys/bus/thunderbolt/devices/domain*`.
6. **VM** (`karchy-vm`): no animations and opaque windows; `vulkan-virtio` (low).
7. **HDD present** (`queue/rotational=1`): bfq (covered by item 6 of the base list); hdparm only if wanted.

### Optional features (c), Settings › Optional features
1. **Gaming:**
   - `[multilib]`, `steam`, lib32 Vulkan driver per GPU
   - `proton-cachyos-slr`, `ntsync` module load, a performance wrapper
   - optional `xpadneo-dkms` and shader-cache env

   Needs D-19 revisited (sources: wiki.cachyos.org/configuration/gaming; O: `bin/omarchy-install-gaming-{steam,gpu-lib32,xbox-controllers}`).
2. Printing (exists) and NAS backup (phase 7). Nothing else from either source qualifies.

### Skip (d)
- zram and its swap sysctls (D-10)
- ananicy-cpp, sched-ext, kernel manager, cachyos-hello and its DNS switcher (D-44)
- `NVreg_InitializeSystemMemoryAllocations=0`, SATA ALPM, pci-latency
- Omarchy's vendor quirks (D-48), connectivity URL (D-15), USB autosuspend
- crash-watch, AI, telemetry, `capture-qr`/`capture-text`, snapshot menu
- nouveau cursor, supergfxd, Elgato relay (unless owned), stay-awake and DND indicators (or remove the idle service's unreachable `stayAwake` state)

## 5. Notes for phase 5 (RTX 5080, two monitors)
- **NVIDIA sleep services.** On this host, `nvidia-suspend`, `-resume` and `-hibernate` are all **disabled**, and `/proc/driver/nvidia/params` shows `PreserveVideoMemoryAllocations: 2`. CachyOS and chwd don't enable them with driver 620. karchy enables them (`install/setup.sh:54-56`). Test suspend both ways on the desktop before deciding.
- **The two monitors** need nothing from CachyOS or Omarchy beyond karchy's per-monitor display settings (D-56). With early KMS, the LUKS prompt comes up on the NVIDIA framebuffer at native resolution rather than through the simpledrm handoff.
- **The 3.6 TB data disk.** If it is an HDD, the per-type scheduler gives it bfq and the writeback cap applies. `ntfs3` is already the plan (D-24).
