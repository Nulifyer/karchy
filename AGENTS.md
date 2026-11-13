# Repository agent instructions

karchy is a personal Arch-based Linux setup that reuses selected parts of Omarchy. Read `.agents/README.md` for the work state. The binding product specs are `docs/components.md`, `docs/keybindings.md` and `docs/menu.md`.

## Rules

- Install software only with pacman, or paru when a package is missing from the configured repos. No mise, no `curl | bash` installers, no Flatpak in the base.
- Keep the base install minimal: small, fast, few dependencies. Basic hardware and desktop functions must work out of the box.
- Don't add keybindings, menu entries, packages or bar modules beyond the specs without the user's approval.
- Never install Omarchy's pacman config, mkinitcpio drop-ins, update guard hook, limine defaults, `omarchy-reinstall-configs`, or anything that writes into the dotfiles user layer (D-23).
- Vendored Omarchy files keep their upstream paths and names. Change them only when necessary, and record each local change so the sync script can show it. karchy's own commands use the `karchy-` prefix.
- Follow Omarchy's bash style for scripts: `#!/bin/bash`, `[[ ]]` for string and file tests, `(( ))` for numeric tests, two-space indent.
- Long-running code reacts to events instead of polling (Omarchy's rule; this applies to plugins too).

## Delivery

- One logical change per branch and PR, with atomic commits (D-26). Don't commit to `main` directly.
- Don't create, rename, delete or push GitHub repos without the user's approval at the time.

## Project continuity

For substantial work, read `.agents/README.md` and only the relevant task records. Use `project-continuity` to preserve user intent, verified progress, and coordination across sessions or independent tasks. Project status owns coordination priorities; each independent task owns its next action and acceptance evidence. Do not create ledgers for routine one-off work or every worker. Deliver verified logical batches regardless of commit permission. Stage and commit only inspected batch changes when authorized; otherwise preserve verified uncommitted work and continue within existing authority.
