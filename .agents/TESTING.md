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
- [ ] `karchy update` completes.
- [ ] Only the chosen packages are installed: `pacman -Qqe` matches the package manifest.

## Fast checks

```text
shellcheck tools/vm          # extend to install/ and karchy's own bin/ as they land
```

## Full checks

```text
tools/vm fetch                       # download + verify (sha256 and Arch keyring signature) the Arch ISO
tools/vm new [--secureboot]          # 40 GiB qcow2 + blank UEFI vars (Setup Mode)
tools/vm run --iso                   # boot the ISO; repo is shared read-only as 9p tag "karchy"
tools/vm screenshot <file.png>       # evidence screenshots via QMP
tools/vm snap/restore <name>         # retry installs from a known state
```

Inside the live ISO: `mount -t 9p -o trans=virtio,version=9p2000.L,ro karchy /mnt/karchy`.

## Environment

- Host: CachyOS with KDE Plasma, RTX 5080, 31 GiB RAM. QEMU/KVM via `tools/vm`; it needs qemu-desktop, edk2-ovmf, socat, gpg and archlinux-keyring, and swtpm for `--tpm`.
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
