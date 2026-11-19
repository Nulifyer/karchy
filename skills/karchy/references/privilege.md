# Privilege: root helpers, sudo and what never to add

Read this before a change that needs root. A change that needs root is system-level unless a Settings page offers it as a single switch.

## Order of preference

1. A karchy command or Settings page that makes the change. It uses one of the helpers below, with fixed choices and its own prompt.
2. `sudo <command>` in a terminal, with the user present. The user types the password. sudo keeps it for that terminal for 10 minutes.
3. If neither is possible in your session (no terminal the user can type in), stop. Give the user the exact command to run.

Never do any of these:

- add or edit a file in `/etc/sudoers.d`, or add `NOPASSWD` anywhere
- add or edit a polkit rule in `/etc/polkit-1/rules.d` or `/usr/share/polkit-1`
- ask the user for the password, store it, or pass it with `sudo -S` or a pipe
- add the user to a group to get around a prompt
- change the owner or mode of a root-owned file so that it can be edited without root

If the user asks for a passwordless rule, explain the risk and let the user add it. Do not write it for them.

## karchy's root helpers

Each helper is run through `pkexec` by the command in the second column. Call that command. Do not call `pkexec` on a helper with arguments of your own.

| What it changes | Run it through | Prompt for the person at the computer |
| --- | --- | --- |
| Trusted networks (`/etc/karchy/trusted-networks`) | `karchy-trusted-networks set <connection-uuid> <true\|false>` | administrator's password |
| DNS on untrusted networks, encrypted DNS | `karchy-network-dns set <key=value>...` | administrator's password |
| Wi-Fi country | `karchy network country set <XX\|auto>` | administrator's password |
| Install or remove Quick install apps (`/usr/lib/karchy/app-packages`) | `karchy quick-install apply install\|remove <id>...` | administrator's password, every time |
| Lid actions, hibernate delay (`/usr/lib/karchy/power-settings`) | `karchy-settings-power set ...` | none |
| Storage measurement, bees on or off (`/usr/lib/karchy/storage-settings`) | `karchy-settings-storage bees on\|off`, `measure` | none |
| Browser theme color policy | `karchy theme set` | none (one fixed sudo rule that accepts a color) |

"None" applies to an active, local session of a member of `wheel`. A remote session, such as SSH, gets a password prompt for the same action. If a helper fails over SSH with an authentication error, that is the cause. Ask the user to run the command at the computer.

The password prompt for these appears in the shell's own dialog on the desktop, not in your terminal. A command that waits with no output may be waiting for the user to answer that dialog. Tell the user to look for it.

The helpers accept fixed lists of choices and Quick install catalog ids only. If the change you need is not in the list, the helper is the wrong tool. Use sudo in a terminal and treat the change as system-level.

The polkit actions are in `/usr/share/polkit-1/actions/org.karchy*.policy`. Each helper's header comment explains what it accepts and why. Read it before you rely on a helper for something new.

## Commands that use sudo

These run `sudo` themselves and expect a terminal:

- `karchy update`: asks for the password once and keeps it for the run.
- `karchy pkg add <packages...>`, `karchy pkg install`, `karchy pkg aur-install`, `karchy pkg remove`, `karchy pkg drop`.
- `karchy channel set <stable|rc|nightly>`.
- `karchy-setup-security-*` and `karchy-remove-security-*` (SSH server, fingerprint, FIDO2).
- `karchy-disk-keep` and `karchy-mount-keep` (they write `/etc/fstab`).
- `karchy-secureboot`.
- the feature scripts `karchy-feature-*` that Quick install runs in a terminal.

`karchy commands --all --json` sets `requires_sudo` to true where the command's header declares it. Several of them ask questions. Run them where the user can see the terminal and answer. Do not answer a prompt on the user's behalf unless the user told you the answer.

`karchy-sudo-keepalive` is a helper that karchy's own long scripts source. It runs `sudo -v` once and refreshes the credential until the script ends. Do not start it yourself to hold root across your own steps.

## What the sudo policy is

`/etc/sudoers.d/karchy` gives members of `wheel` sudo with their password, cached for 10 minutes for each terminal. `/etc/sudoers.d/karchy-theme-browser` is the one passwordless rule. It allows `karchy-theme-set-browser-policy` with a single six-digit hex color. Both files belong to the `karchy-settings` package. Leave them as they are.

## System files

- Prefer a drop-in over an edit: `/etc/systemd/*.conf.d/`, `/etc/NetworkManager/conf.d/`, a unit override made with `sudo systemctl edit <unit>`. karchy's packaged defaults are in `/usr/lib`. A file in `/etc` with a name that sorts later wins.
- Settings › Power writes `60-karchy-settings.conf` in `/etc/systemd/logind.conf.d` and `/etc/systemd/sleep.conf.d`. Do not edit those files. For a hand-written override use a later name, such as `90-mine.conf`, and tell the user that it now overrides the Settings page.
- Before you change a file in `/etc`, take the snapshot that the main skill file names. Report the file, the change and the snapshot number.
- Do not run root code from the home folder, and do not point a system unit, a PAM file or a sudo rule at a path that the user can write.
