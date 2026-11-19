# Report a bug to karchy

Bugs go to https://github.com/Nulifyer/karchy/issues. The repository is public, so everything in a report is public.

## Before writing

1. Confirm the fault is karchy's: it involves a `karchy-*` command, the shell, karchy's Hyprland layer, a karchy package or the installer. A fault in an app, the kernel or an Arch package belongs upstream. Say so and stop.
2. Reproduce it once more and note the exact steps.
3. Check whether an update already fixes it: `karchy version`, then `karchy-update --plan` prints what an update would install as JSON and changes nothing.
4. Search the existing issues for the error text: `gh issue list -R Nulifyer/karchy --search '<error text>'`, when `gh` is installed and signed in.

## What to collect

- `karchy version`. It prints the release and channel.
- `pacman -Q` for the karchy packages involved, for example `pacman -Q karchy karchy-settings hyprland quickshell`.
- The steps, what was expected, and what happened.
- The log excerpt: only the lines around the fault, from the source in [logs.md](logs.md), with the command that produced them.
- Hardware only where it matters: GPU vendor and `karchy-hw-renderer` for drawing faults, laptop or desktop for power faults.

Do not attach whole journals, core dump files, screenshots of the full desktop, or config files in full.

## Remove private data

Redact before the user sees the draft, then let the user check it. Replace each item with a placeholder such as `<user>` or `<ssid>`, and use the same placeholder for the same value so the log still reads.

| Remove | Where it hides |
| --- | --- |
| User name and home path | `/home/<user>/...` in every path, the shell prompt, unit names with a UID |
| Host name | The second column of every journal line |
| IP addresses, public and local, and the router's address | Network status, DNS and VPN output |
| MAC addresses | `karchy-trusted-networks`, `nmcli`, `iw`, kernel lines |
| Wi-Fi names (SSIDs) and saved network names | Network output, the VPN status file |
| Keys, tokens, passwords, VPN endpoints, WireGuard keys | Config files, environment lines in `coredumpctl info`, command lines |
| Serial numbers and disk IDs | `smartctl`, `lsblk`, `fwupdmgr` output |
| File names and file contents of the user's documents | Paths in app logs, clipboard and notification text |
| Window titles, notification text, clipboard content | Shell and Hyprland logs |

`journalctl --no-hostname` drops the host name column. Check the result by reading it. Do not rely on a search and replace alone.

## Get the user's OK

1. Show the user the complete text of the report, title included, exactly as it will be posted.
2. Ask whether to file it. Do not file, comment on or edit an issue without a yes for that text.
3. File it with `gh issue create -R Nulifyer/karchy --title '<title>' --body-file <file>` if `gh` is installed and signed in. Otherwise give the user the text and the link above.

If the user says no, keep the draft local and say where it is.

## Shape of a report

```text
Title: <what fails, in one line>

karchy <version> (<channel> channel)
Packages: <name version>, ...

Steps
1. ...
2. ...

Expected: ...
Actual: ...

Log (journalctl -t karchy-shell, redacted):
<the lines around the fault>

Tried: <what was ruled out>
```

Write the title as the fault, not the guess at its cause. Keep guesses under "Tried" and label them as guesses.
