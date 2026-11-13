# Project status

Updated: 2026-11-13
State: phase 1; architecture approved, PR #1 waiting to be merged

## Project state

- Inception records are on `main` (`c2ab371`) at github.com/Nulifyer/karchy (public).
- The old launcher repo is Nulifyer/karchy-launcher (archived).
- No implementation yet.

## Current batch

Phase 1 architecture proposal: `docs/architecture.md`, on branch `phase1-architecture-proposal`.

## In progress

- PR #1 (architecture): approved, with Q1–Q4 answered (D-41 to D-44). Waiting for the user to merge it (D-26).

## Next action

Owner: coordinating agent. Start phase 1 implementation, one branch and PR each, in this order:
1. `tools/vm`
2. `tools/vendor-sync` + `vendor/omarchy.lock`
3. installer form + disk/base
4. setup
5. the karchy Hyprland layer and menu

## Blockers

- None.

## Verification

- The command trace was run against Omarchy v4.5.0 (`ac2690cd7`): 560 commands, 205 reached after pruning, plus 11 inert theme and restart commands.
- archinstall 4.5 source checked: it forces the busybox `encrypt` hook without a hardware security key (`installer.py:125`), and its swap support is zram only.
- Host VM tooling present: qemu-desktop 11.1.3, libvirt, edk2-ovmf with the Secure Boot firmware, swtpm, `/dev/kvm`.

## Project notes

- Omarchy references: `/home/nulifyer/Projects/Omarchy/reference/omarchy-v4.5.0` (worktree at the release tag) and `/home/nulifyer/Projects/Omarchy/audit/`.
