# Omarchy since v4.5.0: what karchy should take before the laptop install

Date: 2026-11-17. Read-only review. Nothing in karchy changed except this file.

## Summary

- Omarchy has **no release after v4.5.0**. All changes below are unreleased.
- Two upstream branches hold the changes: `v4-5-1` (the pending patch release) and `quattro` (the main branch, next feature release).
- karchy has none of the upstream fixes yet. That is expected, because karchy took v4.5.0 a few days ago.
- Six items are worth porting before the Framework 13 AMD install. Two of them affect stability or security. The other four are small or prevent false findings during hardware tests.
- Upstream changed nothing in the fingerprint, FIDO2, lid, sleep hook, hibernation setup, battery or power profile scripts since v4.5.0. There is no Framework-specific change.
- No upstream security fix since v4.5.0 touches code that karchy carries.

## 1. Releases and branches

| Ref | Commit | Date | State |
|---|---|---|---|
| `v4.5.0` (karchy's base) | `ac2690cd7` | tagged 2026-11-04, GitHub release published 2026-11-05 | Latest release |
| `origin/v4-5-1` | `bb7222752` | last commit 2026-11-17 | Unreleased. 61 commits after v4.5.0, 234 files changed. Mostly bug fixes backported from `quattro` |
| `origin/quattro` (default branch) | `c6be7abb9` | last commit 2026-11-17 23:41 UTC | Unreleased. 2,327 files differ from v4.5.0 |

Evidence:

- `gh release list -R basecamp/omarchy` and `gh api repos/basecamp/omarchy/releases` show v4.5.0 as the newest release. They show no draft or prerelease after it.
- The newest tag in the fetched clone is `v4.5.0`.
- The stable `[omarchy]` package repository (the one karchy uses) still carries `omarchy 4.5.0-3`.

Two facts about the branches matter when you read upstream history:

- `v4.5.0` is an ancestor of `v4-5-1`. A commit range there is exact.
- `v4.5.0` is **not** an ancestor of `quattro`. The two split on 2026-10-27, and v4.5.0 received squashed backports. A commit log `v4.5.0..origin/quattro` therefore lists some commits that v4.5.0 already contains. Example: #16991 (hidden bar and fullscreen clicks) appears in that log, but v4.5.0 and karchy already have it. For `quattro`, I trusted file content, not the commit log.

I ran `git fetch --tags origin` in `/home/nulifyer/Projects/Omarchy/reference/omarchy`. The local `quattro` checkout there is still at `60cb9bf30` (2026-11-13). Use `origin/quattro` and `origin/v4-5-1`.

## 2. `tools/upstream-review` results

The list mode only reads the upstream clone, so I ran it. I did not run `merge`, because `merge` rewrites karchy files.

| Command | Result |
|---|---|
| `tools/upstream-review --to origin/v4-5-1 --log` | 42 of 700 mapped files changed (36 changed, 6 deleted) |
| `tools/upstream-review --to origin/quattro` | 120 of 700 mapped files changed (111 changed, 8 deleted, 1 renamed) |

All 120 files still exist in karchy. Upstream deleted the terminal screensaver and the startup cursor files (six on `v4-5-1`). On `quattro` it also deleted `omarchy-launch-config-editor` and `shell/Ui/ScreenMoveRemap.qml` (see sections 4 and 5).

I also applied each `v4-5-1` change to a scratch copy of the karchy file with `patch --dry-run`. Result: 27 of 36 apply without a failed hunk. These need a hand port: `bin/karchy`, `bin/karchy-plugin-remove`, `bin/karchy-remove-launcher-entry`, network `Model.js` and `Panel.qml`, power `Model.js` and `Panel.qml`, idle `Service.qml`, `BackgroundIntro.qml`.

Limits of the tool for this review:

- The default target is `origin/HEAD`, which is `quattro`. For bug fixes only, pass `--to origin/v4-5-1`.
- With `quattro` as the target, the commit counts and `--log` lists include commits that v4.5.0 already has (see section 1). The file list is correct.
- The tool only sees mapped files. Upstream changes in `etc/`, `install/` and `default/uwsm/` are invisible to it. Three of the port-now items came from those unmapped areas.

## 3. Port now (before the laptop install)

Order: most important first.

### 3.1 PipeWire clients must ask rtkit directly

- **Upstream:** `b58e5b999` (#16824), `quattro` only. Files: `etc/pipewire/client.conf.d/50-omarchy-rtkit.conf` and `etc/pipewire/jack.conf.d/50-omarchy-rtkit.conf`. Each sets `module.rt.args = { rtportal.enabled = false }`.
- **Problem upstream found:** PipeWire clients ask `xdg-desktop-portal` for their realtime budget. The portal reads the budget from rtkit once, at start. If that read fails, the portal reports a budget of 0. PipeWire then sets a hard `RLIMIT_RTTIME` of 0 on the client, rtkit grants realtime, and the kernel kills the process with SIGKILL. The shell is such a client, and everything it starts inherits the limit. Upstream counted 44 and 79 killed processes in test VMs.
- **karchy:** karchy added rtkit on its own (D-79, `packaging/pkgbuilds/karchy-desktop/PKGBUILD:19`). v4.5.0 has no rtkit, so karchy did not get the protection that upstream ships with it. `grep -rn rtportal` finds nothing in karchy.
- **Risk class:** stability, and loss of unsaved work in a killed app. Upstream saw most kills when rtkit arrived on a running system. A fresh install has rtkit from the first boot, so the trigger there is the portal's single failed read (xdg-desktop-portal issue 2110). I did not reproduce a kill.
- **Recommendation: port now.** Two ten-line files in `karchy-settings` (for example `system/pipewire/…`, installed to `/etc/pipewire/client.conf.d/` and `/etc/pipewire/jack.conf.d/`). Upstream's 282-line `omarchy-realtime-repair` is for existing installs and is not needed.
- **Check on the laptop:** `grep 'Max realtime timeout' /proc/$(pgrep -x quickshell)/limits` must not show a hard limit of 0.

### 3.2 Re-arm the idle monitor after a timeout change

- **Upstream:** `7e1adfa77` on `v4-5-1`, `c5f98c652` on `quattro` (#9570). File: `shell/plugins/services/idle/Service.qml`.
- **Problem:** when the first idle timeout changes at run time, Quickshell replaces the idle notification. The new one can land at the old address, so `isIdle` never follows it. The screensaver, the lock and everything after them then stop until the shell restarts.
- **karchy:** has the bug. `shell/plugins/services/idle/Service.qml:314` still binds `timeout:` directly. karchy's idle suspend (D-59) hangs on the same monitor, so a laptop on battery would also stop suspending.
- **Risk class: security-relevant.** Automatic lock silently stops after someone edits `idle.screensaver` or `idle.lock` in `shell.json`. A new laptop is where those values get tuned.
- **Recommendation: port now, by hand.** Take only the re-arm part: `retimeIdleMonitor()`, the 150 ms `idleMonitorRearmTimer`, the unbound `timeout`, and the call in `Component.onCompleted`. About 30 lines. Do not take the rest of the upstream diff, which removes the terminal screensaver (section 4.1).
- **Check:** change `idle.lock` in `~/.config/karchy/shell.json` while the session runs, wait, and confirm that the lock still starts.

### 3.3 Keybinding viewer runs the wrong thing on Hyprland 0.57

- **Upstream:** `96cc8a7e9` (#18558), `quattro` only. File: `bin/omarchy-menu-keybindings`.
- **Problem:** Hyprland 0.56 reported a Lua bind as `__lua`. Hyprland 0.57 reports `HL.Dispatcher(<name>)` or `function: 0x…`. The viewer knew only `__lua`. It dispatched the reported text, which Hyprland rejects, and it listed binds without a description, such as lid switches.
- **karchy:** has the bug. `bin/karchy-menu-keybindings:422` and `:428` test only `__lua`. Arch ships Hyprland 0.57.2 (`pacman -Si hyprland` on this host: `extra` 0.57.2-1). Omarchy stable still pins 0.56.2, which is why v4.5.0 did not need the fix.
- **Recommendation: port now.** Four changed lines plus the cache key `v19` to `v20`. One of four hunks needs a hand merge.
- **Check:** Super+K, choose Lock, and confirm that the screen locks. I could not test this, because Hyprland is not installed on this host.

### 3.4 Mute the Hyprland 0.57 system bell

- **Upstream:** `c019850d7` (#17152) and `598e4ebc5` (#18047), `quattro` only. File: `default/hypr/looknfeel.lua`, one line in the `misc` block: `bell_sound = hl.get_config("misc.bell_sound") ~= nil and "none" or nil`.
- **Problem:** Hyprland 0.57 plays a sound for each `xdg-system-bell` ring. foot forwards each terminal BEL there. Each failed tab completion chimes.
- **karchy:** lacks it. `grep -rn bell_sound` finds nothing. karchy uses foot and Hyprland 0.57.2, and that Hyprland depends on `libcanberra`. I did not hear the chime myself. The VMs may have had no audible output.
- **Recommendation: port now.** One line at `default/hypr/looknfeel.lua:106-118`. The patch applies cleanly. A laptop is used in quiet rooms.

### 3.5 Battery icon and label right after plugging in

- **Upstream:** `14264bb8b` on `v4-5-1`, `d7586fb52` on `quattro` (#19046). Files: `shell/plugins/panels/power/Model.js`, `Panel.qml`.
- **Problem:** some batteries report a new charge rate only every 30 seconds. Until then the rate reads 0 W, and the panel shows "Threshold" (a charge limit holding the battery) with a plain battery icon. Upstream now waits up to 90 seconds before it trusts a rate of 0.
- **karchy:** has the bug (`shell/plugins/panels/power/Model.js:53`, `Panel.qml:73`). It only shows on a machine with a battery, so no VM test could find it.
- **Recommendation: port now.** `.agents/TESTING.md` asks the Framework test to confirm that the battery panel shows the charge limit. This bug gives a false "Threshold" reading in exactly that test. About 25 lines. One hunk in each file needs a hand merge, because karchy changed the icon names.

### 3.6 Wi-Fi panel shows stale or false states

Three fixes on `v4-5-1`, all in `shell/plugins/panels/network/Model.js` and `Panel.qml`:

| Fix | Commit (`v4-5-1` / `quattro`) | Problem | karchy |
|---|---|---|---|
| Rows follow NetworkManager (#18702) | `884f4e92d` / `8b6ce318e` | Rows are rebuilt only when the list changes. A network that connects, drops, is saved or is forgotten by autoconnect or `nmcli` keeps its old row: a dropped network still "Connected", a saved one asks for its password | Has the bug. Same rebuild triggers as v4.5.0 (`Panel.qml:421`, `:922`, `:1186`) |
| Wait out the "Limited" state (#18869) | `86e702f47` / `9eb4d2260` | NetworkManager reports Limited for each new link until its first probe answers. The red limited-access warning flashes on each connect | Has the bug (`Model.js:60`, `Panel.qml:534`). karchy's attention row makes the flash more visible |
| Signal bars (#18091) | `f669a63df` / `9305a184f` | NetworkManager has two strength formulas. A strong link flips between three and four bars | Has the bug (`Model.js:19-22`) |

- **Recommendation: port now, by hand.** The laptop is the first machine with real Wi-Fi, and these three would look like hardware or driver faults during the Wi-Fi tests. The `Model.js` parts are small. karchy rewrote `Panel.qml` (D-68), so 10 of 22 upstream hunks fail there. Take `wifiStateKey`, `rebuildWifiRows`, `limitedSettled` with its 3-second timer, and the new thresholds. Leave #19106 for later (section 4).

### 3.7 Checks for the laptop checklist (no port)

- **Hyprland must be 0.57.2 or newer.** Hyprland 0.57.0 and 0.57.1 take realtime scheduling from rtkit. A slow kernel call (monitor probe, wake from display power-off) then gets the compositor killed with SIGKILL, and the session is lost. Upstream worked around it with `HYPRLAND_NO_RT=1` (`cf71857c2`, #17103). Hyprland fixed it in 0.57.2 ("init: stop acquiring realtime scheduling", Hyprland discussion 16648). Arch has 0.57.2-1, so karchy needs no change. On the laptop, confirm `pacman -Q hyprland` and that `chrt -p $(pgrep -x Hyprland)` shows `SCHED_OTHER`.
- **Hibernation can be switched off by a running app.** The kernel refuses hibernation while any process holds `memfd_secret` memory. Bitwarden does since 2026.6 (section 4.2). Test hibernation and suspend-then-hibernate with the password manager and the browser open, not only on a clean session. What logind does with the lid when suspend-then-hibernate is refused is unverified.

## 4. Port later

### 4.1 Native screensaver

- **Upstream:** `58a32eba6` (#16800, backport #19068), `bb668889d` (#17511) on `v4-5-1`. The terminal screensaver (`ttfx` in a terminal window) is replaced by the `omarchy-screensaver` package. Follow-up fixes: exit on mouse movement, no lock for a user who returned during the launch grace, cursor restored when the lock stops the screensaver.
- **karchy:** still has the terminal screensaver (`bin/karchy-screensaver`, `bin/karchy-launch-screensaver`, three terminal configs, the idle service's window tracking).
- **Later, because:** `omarchy-screensaver` is only in Omarchy's `edge` repository today (1.3.1-1). The `stable` repository that karchy uses does not have it. Port after Omarchy 4.5.1 ships.

### 4.2 Hibernation while Bitwarden runs

- **Upstream:** `88111a2dd` on `v4-5-1`, `61887f238` on `quattro` (#16212). New `bin/omarchy-hibernation-encrypted`. `default/uwsm/default` sets `SECURE_KEY_CONTAINER_BACKEND=mlock` when every swap is on LUKS.
- **karchy:** lacks it. karchy's swap file is on the LUKS root, so the same setting would be safe.
- **Later, because:** the user's password manager is Proton Pass, not Bitwarden. The variable only affects Bitwarden. Port it if Bitwarden is ever installed. Keep the checklist item from 3.7.

### 4.3 NVIDIA: OpenGL renderer for GTK 4

- **Upstream:** `5cf5e7f59` on `v4-5-1`, `fc3fd084a` on `quattro` (#9814). `default/hypr/nvidia.lua` sets `GSK_RENDERER=gl`. GTK 4.16 and newer default to Vulkan, which leaves GTK 4 apps blank or crashing on NVIDIA.
- **karchy:** lacks it. Mission Center and GNOME Disks are GTK 4.
- **Later, because:** the Framework is AMD. **Port before the RTX 5080 desktop install (phase 5).** The patch applies cleanly.

### 4.4 Small fixes to carried code (one batch, any time)

All on `v4-5-1`. karchy has none of them. Most apply cleanly.

| Area | Commits | What it fixes | karchy file |
|---|---|---|---|
| Notifications | `d8441842a` (#18349) | Identical notifications arriving together (a web app open in several tabs) stack as separate cards. A regression in v4.5.0's new engine | `shell/plugins/notifications/Service.qml`, `Store.js` |
| Notifications | `474996434` (#18556) | A one-time code is cut at a search window's edge, so the Copy button can copy part of a code | `shell/plugins/notifications/Detect.js` |
| Menu | `781146fea` (#18565), `91701f5b7` (#19122) | A click into a submenu does not select the row under the pointer. The launcher closes after deleting an app | `shell/plugins/menu/Menu.qml`, `shell/services/AppLibrary.qml`, `bin/karchy-remove-launcher-entry` |
| Plugins | `d7b609abb` (#18198) | Adding a plugin reloads every running plugin, which closes panels and blanks the wallpaper | `shell/shell.qml`, `bin/karchy-plugin-update` |
| Capture | `cad9d7041` (#19030) | Region and window snapping covers only the focused monitor. Matters when docked | `bin/karchy-capture-region` |
| Recording | `328230d95` (#18551) | wf-recorder never stops on a still screen. This is the exact fault that made karchy reject the wf-recorder fallback (STATUS.md, D-78). The fix is the `-D` flag | `bin/karchy-capture-screenrecording` |
| Recording | `f9a765447` (#7188), `bedd86209` (#10125) | The portal setting is ignored for full-screen recording. AMD Polaris cards hang during hardware encoding. Not the Framework's GPU | `bin/karchy-capture-screenrecording` |
| Commands | `5ff6e6ea2` (#18559), `4acf5a9ec` (#18557), `f92fc049a` (#18561), `c17ab7c0f` (#18794), `34dbb5423` (#18819), `77fd08563` (#18797), `7914daf23` (#13237) | No microphone, theme found by display name, empty picker, missing clipboard history, `--help`, exit codes, help column width | `bin/karchy-audio-input-mute`, `karchy-theme-set`, `karchy-theme-remove`, `karchy-menu-images`, `karchy-theme-bg-switcher`, `karchy-plugin-remove`, `karchy-clipboard-paste-text`, `karchy-notification-send`, `bin/karchy` |
| Icons | `9c4a3bbb9` (#16382) | The launcher indexes whichever PNG size `find` returns first. Low value with Papirus, which is SVG | `shell/services/AppLibrary.qml` |
| Themes | `dfcf95914` (#7240) | VS Code list hover uses the accent colour | `default/themed/vscode-theme.json.tpl` |

### 4.5 Features that need the user's decision

| Feature | Upstream (`quattro` only) | karchy today | Note |
|---|---|---|---|
| Wi-Fi passphrase field: spaced dots and a show-password switch | `b1f70c379` (#19103) | Lacks it | Useful when joining networks on the laptop. `shell/Ui/TextField.qml` needs a hand merge |
| Hold the network panel's layout while switching networks | `fa342abaa` / `e25a57bf9` (#19106, also on `v4-5-1`) | Lacks it | Larger change in the rewritten `Panel.qml` |
| Reboot to firmware setup (`system firmware`, Alt in the power menu) | `c0cd26e8e` (#19003) | Lacks it | Handy for Secure Boot Setup Mode (D-31). A menu row needs approval (D-18). `bin/karchy-system` patch applies cleanly |
| Exit message only after two seconds | `23f560e5f` (#19006) | Lacks it | Comes with the same file |
| More touchpad gestures: three fingers up and down, four fingers to move a window or go full screen | `1e452a0c4` (#16891) | Has only the three-finger workspace swipe (`karchy/hypr/bindings.lua`) | New bindings need approval (D-17) |
| Touchpad: stop taps from dragging, ignore the three-finger middle click | `29fbc4e2d` (#19017) | Lacks the documented options | Candidates for Settings › Input after the first week on the laptop |
| No titlebar for apps that draw their own header (Chromium browsers, GNOME Disks) on floating workspaces | `32b3b2017` (#18663) | Lacks it | `default/hypr/workspace-modes.lua`, `helpers.lua`. Both apply cleanly. Affects Brave Origin and GNOME Disks |
| Bar blinks after a monitor move | `796e169ab` (#17229) | Lacks it | Check when docking. Touches `Bar.qml` and `Commons/IpcRegistry.qml` |
| Animations off when Hyprland renders on the CPU | `cfd8106fa` (#17035) | Has a warning only (`karchy-hw-renderer`) | Helps the test VMs, not the laptop |
| Translation files reread without losing a change | `d9cc361cd` (#18101), `60cb9bf30` (#18734) | Lacks it | karchy is English only (D-49). Matters only when a package update replaces the catalog under a running shell |
| Update indicator rechecks when the network comes online | `cd53bfdf2` (#18083, `v4-5-1`) | Own solution: a timer 10 minutes after login, then every 6 hours, keeping the last result | A laptop that wakes offline waits up to 6 hours. Low |
| Omaview replaces imv and mpv | `9599f7661` (#19034) | Ships imv and mpv (D-71) | `omaview` is only in the `edge` repository today |
| Qt theming through qtengine | `df3d01ce8` (#18325) | Uses the GTK 3 platform theme | `qtengine` is only in `edge` today |

### 4.6 Upstream hardening that is not merged

Branch `origin/harden-root-kptr-setuid` (four commits, 2026-11-13 and 14, not merged) came from a vendor security scan. It sets `kernel.kptr_restrict=1` and adds a pacman hook that removes the setuid bit from `mount.cifs` and `ksu`. It also locked root, and its last commit took the root lock back out.

- karchy already locks root (`install/base.sh:244`).
- karchy sets no `kptr_restrict` (`system/sysctl.d/` has only `60-karchy-network.conf`).
- karchy pulls in `mount.cifs` through gvfs-smb. karchy's kept shares mount through systemd as root, so they should not need the setuid bit. That is my inference. Test it before removing the bit.

Decide after the laptop install. It is not in any upstream release.

## 5. Skip

### Already solved in karchy, or not applicable

| Upstream change | Why skip |
|---|---|
| `HYPRLAND_NO_RT=1` (`cf71857c2`, #17103) | Fixed in Hyprland 0.57.2, which Arch ships. See 3.7 |
| Signing keys without public keyservers (`64daf7988`, #18508) | karchy ships the Omarchy, CachyOS and karchy keys with the installer and uses a keyserver only as a fallback (D-79, `install/base.sh:72-86`). Upstream reported `keyserver.ubuntu.com` down on 2026-11-11. It answered HTTP 200 today, so `system/gnupg/dirmngr.conf` needs no change |
| Update ends when its terminal closes (`8a3e62958`, #16045), update lock keeps the holder's PID, test-race fixes in `omarchy-security-functions` and `omarchy-kernel` (`7011e55c7`, #19096) | karchy has its own updater (D-62) without the `script` wrapper, and does not carry those files. I did not test closing the terminal during `karchy update` |
| Pointer no longer hidden at startup (`913ecc965`, #17999) | karchy never loads `default/hypr/startup-cursor.lua`. The file, its cursor folder and the restore calls in `shell/services/BackgroundIntro.qml` are dead code that can be deleted |
| Input device names quoted in Lua (branch `fix/input-device-lua-injection`, unmerged since August) | `bin/karchy-toggle-input-device` already stores the name as data and escapes it |
| Yaru icon theme removed | karchy already dropped Yaru (D-64) |

### Hardware karchy does not target

- AMD: GPU may map nearly all RAM (`c3c8acf1e`, #19164). It is for local AI models on machines with more than 16 GB.
- AMD: `thunderbolt.host_reset=0` (`f24713c23`, #18211). Upstream reverted it the same day (`dace4c1a9`, #18213), because it left the screen black on a Framework Desktop. Do not copy it from older notes.
- HP ZBook Ultra G3a: resume freeze, fingerprint USB port, speakers (#19233, #17634, #17618).
- ChromeOS EC lid switch (`5ab2f1222`, #18777). karchy leaves the lid to logind (`system/laptop/logind.conf`) and has no Hyprland lid binding.
- Keyboard top-row mode for ASUS and Apple keyboards (#17258).
- Snapdragon, Apple T2 and Apple Silicon, Surface, Raspberry Pi, ASUS, Acer, Lenovo, Samsung board fixes. About 80 of the 486 `quattro` commit subjects that v4.5.0 lacks (keyword count). Dropped by D-48.

### Areas karchy dropped or replaced on purpose

- **Display panel rework** (#17159 to #17232, #18292), with the related changes in `karchy-hyprland-monitor-clamshell`, `-internal-mirror`, `-scaling` and `karchy-monitor-state`. karchy has Settings › Displays (D-56, D-79).
- **Default apps:** Google Chrome as the browser, Files (`folio`) for Nautilus and for file dialogs, Plain as the editor, Papers for Evince, Cards and Checkmate, Netflix and Spotify web apps, Moonlight removed. karchy chose its own apps (D-34, D-71, `docs/components.md`).
- **Look:** every window glassy (#18186), icon sets apart from the theme (#18879, #18976), animation timing (#16889, #17001, #17144), background intros (#16875, #16877, #16884, with the `karchy-theme-bg-set` and `-bg-next` changes). Dropped by D-48 and D-64.
- **Agents, local models, Tailscale, Dropbox, Herdr, dictation, Slack and Chrome extension policies.** About 95 of the 486 commit subjects (keyword count). Dropped (`docs/components.md` "Dropped", D-19).
- **Wine tray icons, Battle.net, video wallpaper double-clicks.** Not shipped.
- **Installer and first boot:** first-boot questions (#18783), OEM branding (#18841), keyring made in the background (#19022). karchy has its own installer (D-41, D-54).
- **Commands:** hardware controls moved to `omarchy device` (#19229), `omarchy-launch-config-editor` removed, shells from other checkouts stopped on restart. Naming and developer conveniences.
- **Menu:** Agent in the root menu, About moved, Setup reordered. karchy has its own tree (D-73).
- **Translations.** 90 of the 486 commits are "Update translations". English only (D-49).

## 6. What I could not check

- **No test ran on a karchy system.** Hyprland is not installed on this host. "Has the bug" means that karchy's file still has the code that upstream fixed. I did not reproduce any fault.
- **Bell sound (3.4) and keybinding viewer (3.3):** taken from upstream's description and from karchy's Hyprland version. Not heard, not run.
- **rtkit kills (3.1):** upstream's measurements are from existing installs that received rtkit later. How often a fresh install hits the zero budget is unknown.
- **Hyprland version on the install day.** 0.57.2-1 is from this host's pacman database. Confirm on the laptop.
- **4.5.1 release date and final content.** The branch is still moving (three commits on 2026-11-17). Its content may change before release.
- **`quattro` shell changes read in part.** I read every `v4-5-1` change to mapped files. For `quattro` I read the commands, the Hyprland files, `Commons` and `Ui`, and the first half of `Bar.qml`. I did not read the monitor panel (about 850 added lines), `Background.qml`, `BackgroundIntro.qml`, `Indicators.qml`, `MenuModel.js` or the i18n catalogs line by line. Their commit subjects show features in dropped areas.
- **Unmapped karchy code.** karchy's installer, packages and Settings have no upstream mapping. I compared them with upstream only where an upstream commit pointed there (rtkit, keys, root lock, lid, update check).
- **The v4.5.0 comparison itself.** Not repeated, as instructed. Several late-October upstream commits are in v4.5.0 already. They belong to the other review.
- **Omarchy issue tracker.** I did not search open issues for Framework 13 AMD reports. Only merged and branch commits were reviewed.

## 7. Port-now list

1. PipeWire drop-ins with `rtportal.enabled = false` (`b58e5b999`, #16824). New files in karchy-settings. Stability.
2. Idle monitor re-arm (`7e1adfa77`, #9570). `shell/plugins/services/idle/Service.qml`. Security: automatic lock.
3. Keybinding viewer on Hyprland 0.57 (`96cc8a7e9`, #18558). `bin/karchy-menu-keybindings`.
4. Mute the system bell (`c019850d7`, `598e4ebc5`). `default/hypr/looknfeel.lua`.
5. Charging icon with a stale charge rate (`14264bb8b`, #19046). `shell/plugins/panels/power/Model.js`, `Panel.qml`.
6. Wi-Fi rows, Limited wait, signal bars (`884f4e92d`, `86e702f47`, `f669a63df`). `shell/plugins/panels/network/Model.js`, `Panel.qml`.

No code change, but check on the laptop: Hyprland is 0.57.2 or newer, and hibernation works with the password manager open.
