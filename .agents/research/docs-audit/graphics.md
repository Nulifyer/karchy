# Docs audit: graphics and display

Audited 2026-11-16 against karchy at `7bfe00a`. Read-only: nothing in the repo, on this host or in any VM was changed except this file.

**Scope:** NVIDIA (open modules on Blackwell, 580xx, early KMS, modeset/fbdev, suspend and hibernate, GSP, Hyprland's NVIDIA needs, VA-API, Vulkan, 32-bit), AMD (Mesa, Vulkan, VA-API, amdgpu parameters), and general display (multiple monitors, scaling, VRR, HDR, screen sharing, the software-rendering check).

**Real hardware used:** this host has the same GPU as the owner's desktop (GeForce RTX 5080, `10de:2c02`) and runs CachyOS's `nvidia-utils 620.70.06-2` and `linux-cachyos-nvidia-open 7.3.3-1`, the exact packages `karchy-nvidia` pulls in. Driver state (`/proc/driver/nvidia/params`, `/sys/module/nvidia_drm/parameters`), the package files and NVIDIA's README and changelog for 620.70.06 (`/usr/share/doc/nvidia/`) were read from it. Nothing was changed on it.

## Sources

| Short name | Where |
|---|---|
| AW-NVIDIA | https://wiki.archlinux.org/title/NVIDIA (fetched as `index.php?title=NVIDIA&action=raw`, 2026-11-16) |
| AW-NV-Tips | https://wiki.archlinux.org/title/NVIDIA/Tips_and_tricks |
| AW-NV-TS | https://wiki.archlinux.org/title/NVIDIA/Troubleshooting |
| AW-AMDGPU | https://wiki.archlinux.org/title/AMDGPU |
| AW-FW13 | https://wiki.archlinux.org/title/Framework_Laptop_13 and https://wiki.archlinux.org/title/Framework_Laptop_13_(AMD_Ryzen_7040_Series) |
| AW-Chromium | https://wiki.archlinux.org/title/Chromium |
| AW-Wayland | https://wiki.archlinux.org/title/Wayland |
| AW-HDR | https://wiki.archlinux.org/title/HDR |
| AW-PRIME | https://wiki.archlinux.org/title/PRIME, "PRIME render offload" (per-command `__GLX_VENDOR_LIBRARY_NAME=nvidia`) |
| AW-VRR | https://wiki.archlinux.org/title/Variable_refresh_rate |
| NV-README | NVIDIA 620.70.06 README, `/usr/share/doc/nvidia/README` (from `nvidia-utils`), chapter 20 "Configuring Power Management Support" (lines 4642-4925) and the open vs proprietary section (lines 7638-7639) |
| NV-CL | NVIDIA changelog, `/usr/share/doc/nvidia/NVIDIA_Changelog` |
| HW-NV | Hyprland wiki NVIDIA page. Current version (`e6cb57b`, 2026-09-29) only points to the Arch Wiki: https://github.com/hyprwm/hyprland-wiki/blob/e6cb57b2de82a64577d6e8dea323b5aa75b2770c/content/nvidia/_index.md. The last full version (`cba1dbc509`, 2026-08-29): https://github.com/hyprwm/hyprland-wiki/blob/cba1dbc509/content/nvidia/_index.md |
| HW-Opts | Hyprland wiki config options, monitors, modes, XWayland, multi-GPU and XDPH pages: https://github.com/hyprwm/hyprland-wiki/tree/main/content/configuring (config-options.md last changed 2026-11-13) |
| CY-nvutils | CachyOS `nvidia-utils.install`: https://github.com/CachyOS/CachyOS-PKGBUILDS/blob/master/nvidia/nvidia-utils/nvidia-utils.install |
| CY-580 | CachyOS `nvidia-580xx-utils` (`nvidia-580xx-utils.install`, `nvidia-580xx-utils.conf`, PKGBUILD lines 358-360): https://github.com/CachyOS/CachyOS-PKGBUILDS/tree/master/nvidia/nvidia-580xx/nvidia-580xx-utils |
| CY-kernel | CachyOS `linux-cachyos` PKGBUILD lines 125-128 and 268-271: https://github.com/CachyOS/linux-cachyos/blob/master/linux-cachyos/PKGBUILD |
| CY-chwd | chwd 1.25.0 GPU profiles, `/var/lib/chwd/db/pci/graphic_drivers/profiles.toml` on this host |
| VAAPI | nvidia-vaapi-driver README (v0.0.18 is packaged): https://github.com/elFarto/nvidia-vaapi-driver#upstream-regressions |

Neither the Arch Wiki nor the Hyprland wiki blocked the fetches. The Hyprland wiki dropped its own NVIDIA instructions on 2026-09-29 ("relegate most of it to the specific distro wiki pages", hyprland-wiki PR #1660). The Arch Wiki is therefore the main reference, with the archived Hyprland page used only where it adds something.

## Findings

Ordered by severity. "VM" means the item can be checked in the QEMU VM; "hardware" means it needs the real GPU.

### 1. Hibernation with NVIDIA's modules in the initramfs is documented to fail on resume

- **Severity:** data-loss. If resume fails, the machine cold-boots and the hibernated session, including unsaved work, is lost. Whether this still happens with the 620 open driver is **unverified**.
- **What karchy does:**
  - `system/nvidia/mkinitcpio.conf:6` puts `nvidia nvidia_modeset nvidia_uvm nvidia_drm` in the initramfs for both NVIDIA packages.
  - The same machines are offered hibernation:
    - "Hibernate" in the menu whenever `karchy-hibernation-available` passes (`default/karchy/karchy-menu.jsonc:33`, `bin/karchy-hibernation-available:35`). That includes the RTX 5080 desktop: its swap file is sized to RAM and `resume=` is on its command line.
    - On laptops, idle suspend-then-hibernate (`shell/plugins/services/idle/Service.qml:105`) and the lid switch (`system/laptop/logind.conf:5`).
- **What the docs say:**
  - AW-NVIDIA, "Early loading": "Early loading the modules will break hibernation, as video memory preservation is enabled by default."
  - AW-NV-Tips, "Preserve video memory after suspend", note 1: "When using early KMS, i.e. when the loading of `nvidia` module happens in the initramfs, it has no access to `NVreg_TemporaryFilePath` which stores the previous video memory: early KMS should not be used if hibernation is desired."
  - HW-NV (`cba1dbc509`), "Early KMS, modeset and fbdev": "Loading the NVIDIA modules early may cause resuming from hibernation to not work anymore (i.e. the system will just boot instead of resuming). If you have issues with that, try disabling early KMS."
  - Caveat: the Tips note's reason is the `NVreg_TemporaryFilePath` file. On the 620 open driver that path is empty on this host (`TemporaryFilePath: ""`), and NV-README 20B says the open modules keep the copy "in tmpfs" by default. The documented reason may therefore not apply to `karchy-nvidia`, while AW-NVIDIA's general warning still stands. For `karchy-nvidia-580xx` it applies as written: CachyOS sets `NVreg_TemporaryFilePath=/var/tmp` (CY-580, `nvidia-580xx-utils.conf`).
- **Fix:**
  1. Before relying on Hibernate on the desktop, test it there with nothing unsaved open: hibernate, resume, and check `journalctl -b -1` for the image being restored.
  2. If it cold-boots, make `karchy-hibernation-available` fail when an NVIDIA module is built into the initramfs. For example, fail when `/etc/mkinitcpio.conf.d/karchy-nvidia.conf` exists and `/sys/module/nvidia` is loaded. The menu entry, idle suspend-then-hibernate and (through the same check) the laptop lid would then fall back to plain suspend. The lid needs its own check, because logind calls suspend-then-hibernate directly.
  3. The alternative is to drop early KMS. That brings back the race between greetd and the late-loading `nvidia_drm` that early KMS avoids. CachyOS handles that race with `cachyos-drm-awaiter` (CY-chwd installs it with every GPU profile).
- **Check:** hardware. The VM has no NVIDIA module.

### 2. AMD and Intel machines get no Vulkan driver, and Intel gets no VA-API driver

- **Severity:** broken-feature. Vulkan apps and games outside Steam fail on the Framework 13 AMD; GTK4, mpv and other apps fall back to GL.
- **What karchy does:**
  - Nothing in `install/packages/base.txt`, `packaging/pkgbuilds/karchy/PKGBUILD:16-28`, `packaging/pkgbuilds/karchy-desktop/PKGBUILD:12-49` or `install/setup.sh:6-31` installs `vulkan-radeon` or `vulkan-intel`.
  - `vulkan-icd-loader` comes in through ffmpeg, gtk4 and mpv. It only optionally depends on `vulkan-driver` (`pacman -Si vulkan-icd-loader`), so no ICD is installed.
  - The only path that adds one is Quick install's `gpu32` setup (`bin/karchy-quick-install:150-151`, Steam only). It adds `lib32-vulkan-radeon`, which pulls in `vulkan-radeon` as a dependency.
  - `mesa` does carry AMD's VA-API driver (`/usr/lib/dri/radeonsi_drv_video.so`; mesa provides `libva-mesa-driver`), so AMD video decode is fine. Intel's VA-API driver (`intel-media-driver`) is not in Mesa.
- **What the docs say:**
  - AW-AMDGPU, "Installation": "For Vulkan support, install vulkan-radeon (lib32-vulkan-radeon for 32-bit applications)."
  - CachyOS installs these per GPU vendor (CY-chwd):
    - `[amd]`: `mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon … gst-plugin-va`
    - `[intel]`: `vulkan-intel … intel-media-driver` (or `libva-intel-driver-irql` for older IDs)
  - karchy has no chwd (`system/nvidia/mkinitcpio.conf:3-4` says so), so nothing replaces this step.
- **Fix:** in `setup_packages` (`install/setup.sh`), read the display-class PCI vendors from sysfs, as `karchy-hw-nvidia-generation` does:
  - `0x1002` → add `vulkan-radeon`.
  - `0x8086` → add `vulkan-intel intel-media-driver`.
  - Optionally add `gst-plugin-va` for both, as chwd does.
  - Keep the lib32 halves in `gpu32`. A detected-tier meta-package (`karchy-amd`, `karchy-intel`) is the alternative if these should be updatable like `karchy-nvidia`.
- **Check:** VM for the install logic (point `KARCHY_PCI_DEVICES_PATH`-style fakes at it, or `pacman -Q vulkan-radeon` after install). Hardware (the Framework) for `vulkaninfo --summary` listing RADV.

### 3. VA-API on Maxwell, Pascal and Volta uses the EGL backend, which upstream calls broken

- **Severity:** broken-feature (video decode in Brave on `karchy-nvidia-580xx` machines). Neither of the owner's machines is affected.
- **What karchy does:** `default/hypr/nvidia.lua:22-26` sets `NVD_BACKEND=egl` when `karchy-hw-nvidia-without-gsp` passes (the 580xx cards). `docs/components.md:135` specifies the same: "Hyprland uses the EGL backend for NVIDIA VA-API on these cards (no GSP)."
- **What the docs say:**
  - VAAPI, "Upstream regressions": "The EGL backend is broken on driver versions 525 or later due to a regression. Users running these drivers should use the direct backend instead."
  - VAAPI, "Direct Backend": "has been tested on a variety of hardware from the Kepler to Lovelace generations."
  - The `NVD_BACKEND` row: "Either `egl`, or `direct` (default)."
  - `karchy-nvidia-580xx` ships driver 580.196.07 (`pacman -Si nvidia-580xx-utils`), well past 525.
- **Fix:** set `NVD_BACKEND=direct` for every NVIDIA generation, or drop the variable, since direct is the default. Treat 580xx like the GSP branch for `LIBVA_DRIVER_NAME`. Update `docs/components.md:135` in the same change. The spec line is the documented error here: it records a choice that upstream marks broken.
- **Check:** hardware (a Maxwell, Pascal or Volta card): `vainfo` and brave://gpu.

### 4. The installer enables NVIDIA's suspend services that the 595+ open driver no longer wants

- **Severity:** suboptimal. Not documented as breaking anything, but against NVIDIA, Arch and CachyOS. On 580xx laptops, one service the driver documents is missing.
- **What karchy does:**
  - `install/setup.sh:91-95` enables `nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service` whenever they exist, with the comment "NVIDIA keeps video memory across sleep only through its own services". `docs/components.md:138` specifies the same.
  - Those services run `nvidia-sleep.sh`, which does `chvt 63` around every suspend (`/usr/bin/nvidia-sleep.sh`, "suspend|hibernate" case).
  - karchy works around that VT switch in the lock screen (`shell/plugins/lock/LockView.qml:89-92`, "A VT switch, which the NVIDIA driver forces around every suspend…"; `shell/plugins/lock/Service.qml:791-794`).
- **What the docs say:**
  - NV-README 20A: "When the open kernel modules are in use, this is handled automatically."
  - NV-README 20C: "This is required if using the proprietary driver with the NVreg_PreserveVideoMemoryAllocations=1 kernel module parameter or advanced CUDA features (such as UVM). The NVIDIA Linux kernel driver requires no configuration if the default power management mechanism is used."
  - NV-CL 595.45.04: "Modified nvidia.ko to handle video memory preservation on its own when the open kernel modules are in use if NVreg_UseKernelSuspendNotifiers=1 is enabled."
  - NV-CL 615.71.09: "Enabled the NVreg_UseKernelSuspendNotifiers=1 option by default."
  - This host shows `UseKernelSuspendNotifiers: 1`.
  - AW-NV-Tips, "Preserve video memory after suspend": "The aforementioned services are disabled by default on 595+ drivers, as per upstream requirements, as video memory preservation is now handled by kernel suspend notifiers, making the nvidia suspend/hibernate services unnecessary."
  - CY-nvutils `post_upgrade`: "With 595+ open kernel modules, video memory preservation is handled by kernel suspend notifiers, making the nvidia suspend/hibernate services unnecessary. Disable them…"
  - For 580xx, CY-580's `post_install` already runs `systemctl enable nvidia-resume nvidia-hibernate nvidia-suspend`, so karchy's lines are redundant there.
  - Neither package nor karchy enables `nvidia-suspend-then-hibernate.service`. NV-README 20C lists that service for the suspend-then-hibernate method, which karchy laptops use (D-32).
- **Fix:**
  - Delete `install/setup.sh:91-95` and the sentence in `docs/components.md:138`.
  - For `karchy-nvidia-580xx` on a machine with a battery, enable `nvidia-suspend-then-hibernate.service`.
  - Once the services are off, the LockView/Service workarounds can be re-tested; they may become unnecessary on the open driver.
  - This contradicts what the spec line records, so it is listed here as a documented error in the spec, not a judgment call.
- **Check:** VM can confirm which units are enabled. Hardware (the 5080) for a suspend/resume cycle without the services: `journalctl -b | grep -i nvrm`, no corruption after resume, and no VT flash.

### 5. No VRAM-reuse profile for Hyprland and the shell

- **Severity:** suboptimal (idle VRAM use). **Unverified** for Hyprland and Quickshell specifically.
- **What karchy does:** nothing. CachyOS's `nvidia-utils` installs `/etc/nvidia/nvidia-application-profiles-rc.d/limit-vram-usage`, which applies "No VidMem Reuse" to niri, browsers and some terminals. Its rules don't match Hyprland, Quickshell or foot.
- **What the docs say:** AW-NVIDIA, "nvidia-application-profiles-rc.d": "Some Wayland compositors will consume a large quantity of VRAM by default if the GLVidHeapReuseRatio application profile key is not applied against their process name. For example, niri users can free up to ~2.5GiB of idle VRAM consumption…"
- **Fix:**
  1. Measure on the desktop first: `nvidia-smi --query-compute-apps=…` or `nvidia-smi` per process at idle.
  2. If Hyprland or `quickshell` hold a lot, ship a rule from `karchy-nvidia`, for example `/etc/nvidia/nvidia-application-profiles-rc.d/50-karchy.json`, matching `procname` `Hyprland` and `quickshell` with `GLVidHeapReuseRatio` 0, as in the wiki's example.
- **Check:** hardware.

### 6. HDR auto-switching is turned off

- **Severity:** suboptimal (only with an HDR monitor).
- **What karchy does:** `default/hypr/looknfeel.lua:125-129` sets `render.cm_auto_hdr = 0`. The comment comes from Omarchy and its Pro Display XDR.
- **What the docs say:**
  - HW-Opts, config-options: `cm_auto_hdr` "Auto-switch to HDR in fullscreen when needed", default `1`.
  - AW-HDR, "Hyprland": "Hyprland >= 0.55 will automatically switch to HDR mode in its default configuration, when the monitor and fullscreen content support it."
  - AW-HDR, "Vulkan HDR WSI": nvidia-open 595.58.03 and later include the needed Vulkan extensions.
  - With `cm_auto_hdr = 0`, an HDR game or video on the 5080 stays SDR unless the owner sets `cm = "hdr"` and `bitdepth = 10` per monitor.
- **Fix:** if either desktop monitor does HDR, drop the override (back to Hyprland's default) or make it a user setting. Otherwise leave it.
- **Check:** hardware (HDR monitor).

### 7. Hybrid NVIDIA laptops: the iGPU driver isn't ordered before NVIDIA's

- **Severity:** suboptimal. Neither of the owner's machines is affected.
- **What karchy does:** `system/nvidia/mkinitcpio.conf:6` loads only the NVIDIA modules from `MODULES`. On a hybrid laptop, `amdgpu` or `i915` arrives later through the `kms` hook and udev.
- **What the docs say:**
  - HW-NV (`cba1dbc509`): "Electron or Chromium-based apps can stall for up to a minute after boot on hybrid graphics systems with an Intel iGPU and an NVIDIA dGPU. This can be fixed by loading the `i915` module before the NVIDIA ones", with `MODULES=(i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm ...)`.
  - CachyOS's `cachyos-drm-awaiter` generator does the same with softdeps: "NVIDIA driver can be in a race state with additional driver like amdgpu, especially on laptops. This configuration forces NVIDIA driver to load later than the iGPU one" (https://github.com/CachyOS/CachyOS-PKGBUILDS/blob/master/cachyos-drm-awaiter/drm-module-awaiter-generator).
- **Fix:** when `karchy-hw-nvidia-display` fails (the iGPU drives the panel), put the iGPU module first. Either make the drop-in conditional, like `karchy-thunderbolt.conf`, or ship softdeps like CachyOS's.
- **Check:** hardware (a hybrid laptop).

### 8. VRR is off and can't be turned on in Settings

- **Severity:** suboptimal (gaming desktop). This is a feature choice; it needs the owner's approval per AGENTS.md.
- **What karchy does:** no `misc.vrr` and no per-monitor `vrr` anywhere. `bin/karchy-settings-displays:18-20` handles mode, scale, position, transform and enabled only.
- **What the docs say:**
  - HW-Opts: `vrr` default `0`; values: "0 - off, 1 - on, 2 - fullscreen only, 3 - fullscreen with `video` or `game` content type".
  - AW-VRR, "Hyprland": "you need to add either `vrr = 1` or `vrr = 2`".
  - AW-NV-TS, "Crashes related to VRR and TTY-switching", warns of flip timeouts with VRR on NVIDIA, which argues for opt-in rather than on by default.
- **Fix:** if the owner wants it, add `vrr` (0 or 3) to Settings › Displays per monitor and write it in `displays.lua`. Otherwise document `hl.config({ misc = { vrr = 3 } })` for `~/.config/hypr/looknfeel.lua`.
- **Check:** hardware (a VRR monitor; `hyprctl monitors` shows `vrr: true`).

### 9. Deprecated Electron variable

- **Severity:** cosmetic.
- **What karchy does:** `default/hypr/envs.lua:16` sets `ELECTRON_OZONE_PLATFORM_HINT=wayland`.
- **What the docs say:** AW-Wayland, "Electron": "Since Electron 38.2, Wayland is used by default." and "`ELECTRON_OZONE_PLATFORM_HINT` environment variable is deprecated. … Electron 39 and above will safely ignore it."
- **Fix:** keep it for older Electron apps (harmless) or drop it. No action needed.
- **Check:** VM.

### 10. Brave's flags carry a pre-143 feature

- **Severity:** cosmetic.
- **What karchy does:** `config/brave-origin-flags.conf:12` enables `AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,VaapiOnNvidiaGPUs,VaapiIgnoreDriverChecks`.
- **What the docs say:**
  - AW-Chromium, "Hardware video acceleration": "since Chromium 143 hardware acceleration via VA-API should work out of box", and `AcceleratedVideoDecodeLinuxZeroCopyGL` is for "Chromium versions prior to 143".
  - The same section: "For proprietary NVIDIA support, you must install libva-nvidia-driver and append the `VaapiOnNvidiaGPUs` feature".
  - The flags are one `--enable-features` line, as the wiki requires. Brave Origin's launcher reads the file and skips `#` lines (AUR `brave-origin-bin.sh`: https://aur.archlinux.org/cgit/aur.git/tree/brave-origin-bin.sh?h=brave-origin-bin).
- **Fix:** none needed. On the 5080, confirm "Video Decode: Hardware accelerated" in brave://gpu. If it isn't, VAAPI's Chrome section suggests adding `--use-gl=angle --use-angle=gl`.
- **Check:** hardware for NVIDIA; the Framework for AMD.

## Checked and found correct

One line each; the source follows the dash.

1. The RTX 5080 gets the open driver: device `0x2c02` ≥ `0x1e00` (`bin/karchy-hw-nvidia-generation:38`) — NV-README 7638-7639 "Blackwell and later are only supported by the open kernel modules"; 0x2C02 is in the supported list (README line 10537).
2. `karchy-nvidia` pulls both kernels' prebuilt open modules plus CachyOS's `nvidia-utils` (`packaging/pkgbuilds/karchy-nvidia/PKGBUILD:11`) — `pacman -Si`: `linux-cachyos{,-lts}-nvidia-open` depend on `nvidia-utils=620.70.06`, which is in `[cachyos]` (D-45).
3. The early-KMS module list is exactly the documented one (`system/nvidia/mkinitcpio.conf:6`) — AW-NVIDIA "Early loading"; CachyOS chwd writes the same `MODULES+=(…)`.
4. The initramfs is rebuilt when the modules install — `90-mkinitcpio-install.hook` triggers on `usr/lib/modules/*/extramodules/` and `usr/lib/modprobe.d/` (mkinitcpio 42.2).
5. GSP firmware reaches the initramfs — `modinfo -F firmware nvidia` lists `nvidia/620.70.06/gsp_ga10x.bin` and others, and mkinitcpio adds module firmware (`/usr/lib/initcpio/functions:725-745`).
6. `nvidia_drm` modeset and fbdev need no parameter on 620 — NV-CL 595.45.04 "Enabled the nvidia-drm.ko modeset=1 parameter by default", fbdev default since 570; this host reads `Y` for both.
7. modeset is on for the prebuilt 580xx modules too — CY-kernel applies `0001-Enable-atomic-kernel-modesetting-by-default.patch` to the 580xx module build.
8. nouveau and nova stay blacklisted in the initramfs — `nvidia-utils` ships `/usr/lib/modprobe.d/nvidia-utils.conf`, and `modconf` precedes `kms` in `system/mkinitcpio.conf.d/karchy.conf:3`; AW-NVIDIA says removing `kms` is optional.
9. 580xx video-memory preservation goes to btrfs `/var/tmp`, not the tmpfs `/tmp` — CY-580 sets `NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp`; btrfs supports `O_TMPFILE` since 3.16 (open(2)); NV-README 20B recommends non-tmpfs.
10. The open driver's suspend needs no module options (karchy sets none) — NV-README 20A/20C; this host: `UseKernelSuspendNotifiers: 1`.
11. Sessions aren't frozen during NVIDIA sleep — `nvidia-utils` ships `systemd-{suspend,hibernate,suspend-then-hibernate}.service.d/10-nvidia-no-freeze-session.conf`.
12. `LIBVA_DRIVER_NAME=nvidia` and `__GLX_VENDOR_LIBRARY_NAME=nvidia` when NVIDIA drives the display (`default/hypr/nvidia.lua:18-21`) — HW-NV (`cba1dbc509`) "Environment variables"; VAAPI's env table.
13. `NVD_BACKEND=direct` on Turing and newer (`default/hypr/nvidia.lua:17`) — VAAPI "Upstream regressions"; HW-NV (`cba1dbc509`) VA-API section.
14. No `GBM_BACKEND` is set — no current Arch Wiki NVIDIA, Wayland or Hyprland page asks for it (grep of the fetched pages); `nvidia-utils` depends on `egl-gbm`.
15. Hybrid laptops don't get NVIDIA's VA-API/GLX forced (`bin/karchy-hw-nvidia-display`, `boot_vga`) — matches AW-PRIME's per-app `__GLX_VENDOR_LIBRARY_NAME` model; libva ≥ 2.20 maps `nvidia-drm` → `nvidia` itself (https://github.com/intel/libva/blob/2.24.0/va/drm/va_drm_utils.c).
16. `libva-nvidia-driver` is in both NVIDIA packages — AW-Chromium "you must install libva-nvidia-driver"; VAAPI requires `nvidia-drm.modeset=1`, which is the default (item 6).
17. Hardware cursors on NVIDIA need no setting — HW-Opts `cursor.use_cpu_buffer` default `2` "auto (enabled with NVIDIA)"; `no_hardware_cursors` default `2`; karchy sets neither.
18. Explicit sync needs no setting — the Hyprland options have no switch; AW-NVIDIA "Wayland configuration" needs driver ≥ 555 with `linux-drm-syncobj-v1`; the driver is 620.
19. Chromium/Electron explicit sync needs no `WaylandLinuxDrmSyncobj` flag now — Chromium `ui/ozone/platform/wayland/host/wayland_connection.cc` binds `wp_linux_drm_syncobj_manager_v1` whenever the kernel is ≥ 6.11 (https://github.com/chromium/chromium/blob/main/ui/ozone/platform/wayland/host/wayland_connection.cc); the kernel is 7.3.
20. 32-bit graphics libraries: `nvidia-580xx-utils` depends on `lib32-nvidia-580xx-utils`, so `[multilib]` is enabled (`install/setup.sh:15-18`); Steam's `gpu32` adds `lib32-nvidia-utils`, `lib32-vulkan-radeon` or `lib32-vulkan-intel` (`bin/karchy-quick-install:135-157`) — AW-NVIDIA "For 32-bit application support…"; AW-AMDGPU "Installation".
21. Vulkan on NVIDIA: `nvidia-utils` ships `/usr/share/vulkan/icd.d/nvidia_icd.json` and provides `vulkan-driver`.
22. AMD VA-API needs no extra package — `mesa` provides `libva-mesa-driver` and ships `radeonsi_drv_video.so`; AW-AMDGPU "Install the mesa package, which provides … VA-API/VDPAU drivers".
23. No amdgpu kernel parameters by default — AW-FW13 lists `amdgpu.dcdebugmask=0x10` and `amdgpu.sg_display=0` only as workarounds ("should be resolved with the latest BIOS update"); AW-AMDGPU needs none for RDNA3 (Phoenix).
24. `linux-firmware` (base.txt) pulls `linux-firmware-amdgpu` and `linux-firmware-nvidia` — `pacman -Si linux-firmware` depends on all split packages.
25. Mixed scaling under XWayland: `force_zero_scaling = true` plus one integer `GDK_SCALE` from the saved scales (`default/hypr/envs.lua:70-72`, `bin/karchy-settings-displays:103-107`) — HW-Opts XWayland page uses exactly this and says "GDK_SCALE won't conflict with Wayland-native GTK programs".
26. Scales offered in Settings and on the bar are snapped to values Hyprland accepts (`bin/karchy-hyprland-monitor-scaling:55-67`, `shell/plugins/settings/DisplaysSection.qml:236-247`) — HW-Opts monitors: scale must give whole logical pixels.
27. The fallback monitor rule is `preferred`/`auto`/`auto` (`config/hypr/monitors.lua:3`) — HW-Opts monitors' own fallback example; per-monitor rules key on `desc:`, which the HW-Opts monitors table allows ("Output name or `desc:...` description prefix").
28. Screen sharing: XDPH plus `xdg-desktop-portal-gtk` as fallback (`packaging/pkgbuilds/karchy/PKGBUILD:18`), `XDG_CURRENT_DESKTOP=Hyprland`, and `custom_picker_binary`/`allow_token_by_default` in `config/hypr/xdph.conf` — HW-Opts XDPH page ("recommended to install xdg-desktop-portal-gtk alongside XDPH"; option table).
29. The software-rendering check reads the right renderer on the 5080 — `eglinfo -B -p wayland` and `-p gbm` on this host print "OpenGL core profile renderer: NVIDIA GeForce RTX 5080/PCIe/SSE2", which `bin/karchy-hw-renderer:35` parses; `eglinfo` comes from `mesa-utils`, a `karchy` dependency.
30. Secure Boot doesn't block the prebuilt NVIDIA modules — `modinfo -F signer nvidia` shows the kernel's build key, `CONFIG_MODULE_SIG_FORCE` is unset, and lockdown is `none` on this host.

## Not settled from documentation

Each of these needs the real machines.

- **Desktop with an AMD Ryzen 7000/9000 CPU:** if its iGPU is enabled, check which GPU Hyprland renders on (`hyprctl systeminfo`, `karchy-hw-renderer`). HW-Opts multi-GPU says to pin it with `AQ_DRM_DEVICES` and a udev symlink if the wrong one is picked. karchy sets nothing.
- **High-refresh monitors on the 5080:** `preferred` is "the display's preferred size and refresh rate" (HW-Opts modes). Check `hyprctl monitors` for the expected refresh rate. If it's low, pick it in Settings › Displays or use `highrr`.
- **HDMI on NVIDIA:** AW-NV-TS lists "Refresh-rate limited to 120Hz" (`nvidia-modeset.hdmi_deepcolor=0`) and "Wrong color space on 60Hz on Wayland with HDMI" (`nvidia-modeset.debug_force_color_space=2`). Only relevant if a monitor uses HDMI and shows those symptoms.
- **Framework 13 AMD:** with power-profiles-daemon (karchy-laptop), AW-FW13 "Washed-out colors when using power-profiles-daemon in power-saver or balanced mode" describes ABM. It is a cosmetic tradeoff and the owner's call; the wiki gives a PPD drop-in (`--block-action=amdgpu_panel_power`).
- **Hibernate image size on the desktop:** the open driver copies used VRAM into memory during hibernate (NV-README 20B), and the swap file equals RAM. After item 1, also check that hibernating with a game open still fits.
