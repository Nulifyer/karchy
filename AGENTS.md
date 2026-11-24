# Repository agent instructions

karchy is a personal Arch-based Linux setup built from selected Omarchy v4.5.0 code, which karchy now owns (D-46, D-47). It ships as pacman packages; `packaging/` holds the PKGBUILDs and the build that publishes the `[karchy]` repository (D-51). Read `.agents/README.md` for the work state. The binding product specs are `docs/components.md`, `docs/keybindings.md` and `docs/menu.md`.

## Rules

- Install software only with pacman, or paru when a package is missing from the configured repos. No mise, no `curl | bash` installers, no Flatpak in the base.
- Keep the base install minimal: small, fast, few dependencies. Basic hardware and desktop functions must work out of the box.
- Don't add keybindings, menu entries, packages or bar modules beyond the specs without the user's approval.
- Never install Omarchy's pacman config, mkinitcpio drop-ins, update guard hook, limine defaults, `omarchy-reinstall-configs`, or anything that writes into the dotfiles user layer (D-23).
- Omarchy's code is karchy's own: change it freely. `vendor/upstream.tsv` maps each file to its Omarchy origin, and `tools/rebrand` maps names, so upstream changes can be reviewed by hand with `tools/upstream-review`. Keep real Omarchy names (the `[omarchy]` repo, its packages, URLs) as `tools/rebrand` protects them.
- Code that root runs must come from the packaged, root-owned `/usr/bin` and `/usr/share/karchy`, never from `$KARCHY_PATH` in a dev checkout (D-50, D-55).
- Where a file is installed is decided by the PKGBUILDs in `packaging/pkgbuilds/`. A new file under `system/`, `config/`, `default/systemd/` or `themes/` goes into the owning PKGBUILD in the same change.
- A karchy machine is updated, never reinstalled. A change that alters files in a user's home, or in `/etc` beyond what the package itself replaces, ships a migration in `migrations/` in the same commit (`<unix time>-<what>.sh`, idempotent, run by `karchy update`); packaged files in `/usr` need none. The rules: `docs/maintenance.md` › Changes pacman can't make.
- karchy owns the core package set (D-108): retire a core package by adding it to `default/karchy/retired-packages`; demote one to a removable app with a migration that marks it `--asexplicit`. Removable apps (the catalog's `default` entries) are installed on fresh installs only; an update never installs or removes an app because the defaults changed. See `docs/maintenance.md` › The package set.
- karchy ships agent skills in `skills/<name>/` (D-115), each installed by the package it describes. A change that alters something a skill describes (a command, its arguments, a file location, a Settings area, a default) updates that skill in the same commit. A new skill is added to its package's PKGBUILD; `tests/agent-skills.sh` checks both.
- karchy maintains only what it has to own (D-89). A new pin, fork, rebuilt third-party package or copied upstream file gets a row in `docs/maintenance.md` in the same change.
- Keybindings are layered (D-134, `docs/keybindings.md` › Layers and the editor): karchy's defaults, add-ons, the Settings editor, the user's `bindings.lua`. A new default is one `o.bind(keys, name, action)` line in `karchy/hypr/bindings.lua` under its `o.bind_group`; an add-on's go in its own `hypr.d` file. The name is the action's identity in the editor and in users' saved changes: unique, and not renamed without a migration. Don't bind keys anywhere else, and don't call `hl.bind` past `o.bind`. `tests/keybindings.py` runs the layer code.
- Follow Omarchy's bash style for scripts: `#!/bin/bash`, `[[ ]]` for string and file tests, `(( ))` for numeric tests, two-space indent.
- A script the menu runs in its floating terminal (`karchy-launch-floating-terminal-with-presentation`) exits 130 when a prompt is cancelled (Esc) or declined, so the window closes instead of showing Failed. A wrong answer asks again, keeping what was typed (a password is asked again empty, as login prompts do). The wrapper shows Done or Failed and waits for a key, so the script doesn't add its own "Press Enter".
- Long-running code reacts to events instead of polling (Omarchy's rule; this applies to plugins too).
- Common screens use what people already know. For something as common as an OS settings page, start from how the same thing is worded, grouped and controlled in Windows Settings (then macOS, GNOME, KDE) and depart only where karchy behaves differently; don't coin new phrasing or design a new pattern where a familiar one exists. The effort goes into the setting working (user, 2026-11-24).

## Delivery

- Atomic commits, one logical change each (D-26). Commit subjects are `type(scope): sentence` (`fix(quick-install): every installed app shows Installed`; types feat, fix, docs, test, build, refactor, chore; user, 2026-11-24). Earlier history reads "Area: sentence" and stays as it is. During initial development, tested work goes straight to `main`, which only feeds the nightly channel (user, 2026-11-17). Tagging an rc or stable release needs the user's go-ahead.
- Don't create, rename, delete or push GitHub repos without the user's approval at the time.

## Project continuity

For substantial work, read `.agents/README.md` and only the relevant task records. Use `project-continuity` to preserve user intent, verified progress, and coordination across sessions or independent tasks. Project status owns coordination priorities; each independent task owns its next action and acceptance evidence. Do not create ledgers for routine one-off work or every worker. Deliver verified logical batches regardless of commit permission. Stage and commit only inspected batch changes when authorized; otherwise preserve verified uncommitted work and continue within existing authority.
