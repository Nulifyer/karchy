# Before the laptop install: review of 2026-11-17

Four read-only reviews, asked for by the user before installing karchy on the Framework 13 AMD:

| File | Question |
|---|---|
| `01-earlier-audits-status.md` | What is still open from the 2026-11-14 audits (vs Omarchy and CachyOS, Settings vs Windows 11 and KDE, the user's own desktop usage)? |
| `02-desktop-os-gaps.md` | What do a KDE or Windows 11 user's everyday features and CachyOS's defaults have that karchy lacks or never tested? |
| `03-framework-readiness.md` | Framework 13 AMD quirks, what to do before wiping it, recovery commands, first-day and first-week tests |
| `04-omarchy-since-4.5.0.md` | Omarchy's unreleased fixes since v4.5.0 that karchy's copies still need |

Nothing in them was tested on hardware; "karchy handles it" means the code was read.
Two findings were re-checked by hand: the kernel command line has no `quiet loglevel=3`
(`install/base.sh`), and the installer does not carry the ISO's Wi-Fi connection into the
installed system.
