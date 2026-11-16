# Testing and evidence

## Evidence standard

- A milestone closes only on a fresh install in the target environment, with the evidence saved under `docs/evidence/<milestone>/`: the install log, screenshots, and a filled checklist with the date and karchy commit.
- Static checks (shellcheck, `bash -n`, `hyprctl configerrors`) show that files parse. They don't show that a feature works.
- Results from the VM don't cover NVIDIA, fingerprint, suspend or docking. Phases 4 and 5 test those on hardware.
- A checklist item passes only when it was observed in that run. Items that are untested or skipped stay unticked, with a reason.

## Milestone 1 checklist (VM boots to a working desktop)

Environment: QEMU/KVM on this host, UEFI (OVMF), virtio-gpu with 3D (virgl), and a virtual disk of at least 40 GiB.

- [ ] From the stock Arch ISO, the karchy installer form runs an unattended install with no other manual steps.
- [ ] After reboot: the LUKS text prompt, then greetd auto-login, then Hyprland with the Omarchy shell bar.
- [ ] Super+Return opens foot, Super+E opens Thunar, Super+Space opens the menu, and Alt+F4 closes a window.
- [ ] Super+L locks and unlocking works; Super+Escape opens the power menu.
- [ ] Print and Super+Shift+S take screenshots.
- [ ] A notification and a polkit password prompt both appear.
- [ ] A theme switch changes the shell, Hyprland and foot.
- [ ] After a change in the checkout and a rebuild, `karchy update` installs only the changed karchy packages and the session picks up the change.
- [ ] Only the chosen packages are installed: `pacman -Qqe` is `install/packages/base.txt` plus microcode and `karchy-desktop` (and the detected metas).

## Fast checks

```text
shellcheck tools/vm          # extend to install/ and karchy's own bin/ as they land
tools/quick-install-search-check   # the Quick install window's search ranking, against the real list
```

## Full checks

```text
tools/vm fetch                       # download + verify (sha256 and Arch keyring signature) the Arch ISO
tools/vm new [--secureboot] [--tpm]  # 40 GiB qcow2 + blank UEFI vars (Setup Mode), defined in libvirt as karchy-<vm>
tools/vm run --iso [--headless]      # boot the ISO and open the console in virt-manager; repo shared read-only as 9p tag "karchy"
tools/vm screenshot <file.png>       # evidence screenshots via virsh
tools/vm type <text> / key <combo>   # drive the VM for unattended checks
tools/vm click <x> <y>               # click at a screenshot pixel
tools/vm exec [--user] <command>     # run in the guest (as root, or in the desktop session) via the guest agent
tools/vm stop [--force]              # clean shutdown; --force pulls the plug (recent guest writes can be lost)
tools/vm snap/restore <name>         # retry installs from a known state
tools/vm repo                        # serve out/repo-<channel> (from packaging/build) to guests at http://10.0.2.2:8090
```

Inside the live ISO: `mount -t 9p -o trans=virtio,version=9p2000.L,ro karchy /root/karchy` (not under `/mnt`, which the installer mounts over), then `/root/karchy/install/karchy-install --config /root/karchy/tests/vm-install.conf`. Build the packages first with `packaging/build`.

Dev mode in a test VM (D-55), to try shell and command changes without rebuilding packages: add `karchy /mnt/karchy 9p trans=virtio,version=9p2000.L,ro,nofail 0 0` to the guest's fstab and `KARCHY_PATH=/mnt/karchy` to `/etc/karchy.conf`, reboot, then `karchy-restart-shell` after each change. System files still come from the packages.

## Environment

- Host: CachyOS with KDE Plasma, RTX 5080, 31 GiB RAM. Test VMs are libvirt domains on `qemu:///system` (the user is in the `libvirt` group), visible in virt-manager. `tools/vm` needs libvirt, virt-manager, qemu-desktop, edk2-ovmf, acl (setfacl), imagemagick, gpg and archlinux-keyring, and swtpm for `--tpm`.
- VM files: `${KARCHY_VM_DIR:-~/.local/state/karchy-vm}`. Override the VM size with `KARCHY_VM_CPUS`, `KARCHY_VM_MEMORY` and `KARCHY_VM_DISPLAY`.
- Install media: the current stock Arch Linux ISO, from `geo.mirror.pkgbuild.com/iso/latest`.

## Known gaps

- The VM cannot test NVIDIA, fingerprint, laptop power or suspend, real docking, or Wi-Fi.

## Project notes

- Phase 2 extends this checklist to everything in `docs/components.md`, `docs/keybindings.md` and `docs/menu.md`, and adds:
  - Secure Boot in the VM using `OVMF_CODE.secboot.4m.fd`: enroll, boot signed, and boot a snapshot entry.
  - Hardware detection: a VM with no battery and no NVIDIA gets none of the Detected-tier packages.
  - The Settings window: a hand edit overrides a GUI value.
  - A mirror-ranking failure, simulated, keeps the old list.
  - The LocalSend port is open on a trusted network and closed on an untrusted one.

## On the real machines (from the docs audit, D-79)

Things a VM can't show. Write down what happened for each.

Both machines:
- Boot a snapshot from the Limine menu: the desktop comes up (writable overlay), then reboot normally.
- `vainfo` and brave://gpu show hardware video decode.
- A data disk: mounted at boot; the 3.6 TB disk comes up without "timed out waiting for device" (`journalctl -b`).
- Firmware: Update Firmware lists devices; with Secure Boot on, a BIOS update applies (the signed `fwupdx64.efi.signed` is used).
- Secure Boot recovery, before relying on it: what turning Secure Boot off in the firmware does to booting, written down.

Desktop (RTX 5080, Ryzen 7 3700X):
- `pacman -Q linux-cachyos` comes from `cachyos-v3`.
- Both monitors at their full refresh rate; HDMI color and refresh look right; VRR and 10-bit where the monitors take them.
- Suspend and resume work; Hibernate is not offered. To check NVIDIA issue #1343 once a driver says it's fixed: save everything, then follow the test in .agents/research/docs-audit/nvidia-hibernation.md (resume keeps the session, `boot_id` unchanged, no `nv_pmops_freeze -5`).
- Idle VRAM use (`nvidia-smi`) with the desktop running; only act if it's gigabytes.
- If the CPU's integrated GPU is enabled, Hyprland draws on the NVIDIA card.

Framework 13 AMD:
- `pacman -Q linux-cachyos` comes from `cachyos-znver4` (Ryzen 7040).
- Lid on battery: suspend, then hibernate after 2 h; lid on AC, unplug, wait 2 h: it hibernates.
- Idle suspend on battery; resume with the Wi-Fi card (MT7922) working, no reboot instead of resume.
- Headphone jack: no buzz or pop at idle (if there is, `snd_hda_intel power_save=0` for Framework).
- Fingerprint: lock screen and polkit prompts take it, sudo asks for the password.
- A USB4 dock: Ethernet and USB behind it work (bolt).
- Suspend with a VM running.
- Charge limit set in the BIOS or with `framework_tool --charge-limit`; the battery panel shows it.
- Console text at the disk password prompt is readable.
