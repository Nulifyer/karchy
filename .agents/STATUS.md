# Project status

Updated: 2026-11-13
State: phase 1 — architecture proposal awaiting approval

## Project state

- Inception records are on `main` (`c2ab371`) at github.com/Nulifyer/karchy (public).
- The old launcher repo is Nulifyer/karchy-launcher (archived).
- No implementation yet.

## Current batch

Phase 1 architecture proposal: `docs/architecture.md`, on branch `phase1-architecture-proposal`.

## In progress

- The architecture proposal PR. Owner: coordinating agent. Waiting on the user's answers to Q1–Q5 in `docs/architecture.md`.

## Next action

Owner: coordinating agent. After the user approves or adjusts the proposal:
1. Record the answers in `DECISIONS.md`.
2. Merge the PR.
3. Start phase 1 implementation on new branches, in this order: `tools/vm` → `tools/vendor-sync` + `vendor/omarchy.lock` → installer form + disk/base → setup → the karchy Hyprland layer and menu.

## Blockers

- The proposal needs approval, in particular Q1, which would change D-08 from archinstall to karchy's own pacstrap scripts.

## Verification

- The command trace was run against Omarchy v4.5.0 (`ac2690cd7`): 560 commands, 205 reached after pruning, plus 11 inert theme and restart commands.
- archinstall 4.5 source checked: it forces the busybox `encrypt` hook without a hardware security key (`installer.py:125`), and its swap support is zram only.
- Host VM tooling present: qemu-desktop 11.1.3, libvirt, edk2-ovmf with the Secure Boot firmware, swtpm, `/dev/kvm`.

## Project notes

- Omarchy references: `/home/nulifyer/Projects/Omarchy/reference/omarchy-v4.5.0` (worktree at the release tag) and `/home/nulifyer/Projects/Omarchy/audit/`.
