# karchy networking: stack audit and design proposal

Date: 2026-11-14. Read-only audit; nothing in the repo or on the host was changed.

Path prefixes used for evidence:
- no prefix: `/home/nulifyer/Projects/karchy` (working tree as of today, uncommitted rebrand included)
- `vpn/`: `/home/nulifyer/Projects/Omarchy/reference/omarchy-vpn-plugin` (commit 408778a, manifest 1.5.2)
- `omarchy/`: `/home/nulifyer/Projects/Omarchy/reference/omarchy-v4.5.0`
- `host:`: read-only commands on this CachyOS host (NM 1.58.1, Quickshell 0.3.2, linux-cachyos 7.3.3)

What was not verified: nothing ran in a VM (both are busy). The VM has no Wi-Fi anyway. The VPN plugin was not loaded under karchy's shell. Findings marked *inferred* come from reading code and docs, not from a run.

---

## 0. Summary

- **The stack:** NetworkManager with wpa_supplicant, systemd-resolved through the stub link, avahi + nss-mdns, ufw deny-incoming. karchy adds a LocalSend trusted-network hook, a band pin, a QR share, captive-portal sign-in and the Wi-Fi regulatory domain. The VPN is a separate, unpackaged WireGuard policy plugin. It brings its own kill switch (nftables), its own DNS (dnscrypt-proxy) and its own trust list.
- **Biggest problems:** the plugin and karchy don't share anything yet. There are two trust lists, two DNS owners and three writers to the packet filter. The captive-portal flow knows about Tailscale, which karchy dropped, but not about karchy's own VPN kill switch. That kill switch blocks the portal page, so a café network can't be signed into while the VPN is in Auto or On.
- **Proposal:**
  - One "Trusted network" concept owned by karchy. It decides LocalSend, VPN Auto and DNS.
  - The panel answers "am I online, am I protected, what needs me now".
  - Settings › Network holds saved networks, DNS, VPN profiles and the firewall summary.
  - The VPN plugin keeps the tunnel and the kill switch, and is packaged.

---

## 1. The stack as installed

| Layer | What karchy installs or sets | Evidence |
|---|---|---|
| Link manager | `networkmanager` (base pacstrap and `karchy` depends), enabled at install | `install/packages/base.txt:27`, `packaging/pkgbuilds/karchy/PKGBUILD:22`, `install/base.sh:171` |
| Wi-Fi backend | **wpa_supplicant**: NM's default, a hard dependency of Arch's `networkmanager`. No `wifi.backend` override is shipped. (This host uses iwd via an unowned `/etc/NetworkManager/conf.d/30-wifi-backend.conf`; karchy doesn't.) | `host: pacman -Si networkmanager` (Depends … wpa_supplicant); no NM `conf.d` in `system/` |
| Resolver | systemd-resolved enabled; `/etc/resolv.conf` → `/run/systemd/resolve/stub-resolv.conf`, linked last from outside the chroot. NM then picks `dns=systemd-resolved` on its own. No `resolved.conf.d` drop-in, so Arch's defaults apply: **LLMNR=yes, MulticastDNS=yes, DNSOverTLS=no, DNSSEC=no** | `install/base.sh:171,208-211`; `host: resolvectl status` shows `+LLMNR +mDNS -DNSOverTLS`; `host: man NetworkManager.conf` ("connection.llmnr … with systemd-resolved the default currently is yes") |
| mDNS | avahi + nss-mdns (karchy-desktop), `mdns_minimal [NOTFOUND=return]` put before `resolve` in nsswitch, avahi enabled. resolved's own mDNS responder is also on (row above) | `packaging/pkgbuilds/karchy-desktop/PKGBUILD:21`, `install/setup.sh:39-41,48` |
| Firewall | ufw (karchy-desktop), `ENABLED=yes`, unit enabled. Default deny incoming, allow outgoing, forward drop | `install/setup.sh:43-44,48` |
| LocalSend port | NM dispatcher `90-karchy-localsend` → `karchy-localsend-firewall` (root) opens 53317 (tcp+udp) with `ufw allow in on <dev>`, only on interfaces of active connections whose UUID is in `/etc/karchy/trusted-networks` | `system/NetworkManager/dispatcher.d/90-karchy-localsend:5`, `bin/karchy-localsend-firewall:20-44`, packaged at `packaging/pkgbuilds/karchy-settings/PKGBUILD:46-47` |
| Trust list | `/etc/karchy/trusted-networks` (root, 0644), edited by `karchy-trusted-networks set` through `pkexec`; Settings › Network lists Wi-Fi and Ethernet profiles with a toggle | `bin/karchy-trusted-networks:46-74`, `shell/plugins/settings/NetworkSection.qml:79-95` |
| Connectivity check | **Arch's** `http://ping.archlinux.org/nm-check.txt` from `networkmanager`'s own `20-connectivity.conf`; karchy ships no override (D-15) | `host: /usr/lib/NetworkManager/conf.d/20-connectivity.conf` (owned by networkmanager) |
| Captive portal | Panel shows "Sign into network" when NM reports `Portal`; the click runs `karchy-network-captive-portal http://ping.omacom.io/nm-check.txt`, which opens a floating web-app window and polls `nmcli networking connectivity check` until `full`. It pauses a **Tailscale** exit node if one is active | `shell/plugins/panels/network/Model.js:47`, `Panel.qml:530-548`, `bin/karchy-network-captive-portal:17-35,91-123`, `default/hypr/apps/captive-portal.lua:3` |
| Band pinning | `karchy-network-band` writes `802-11-wireless.band` on the active profile (persisted) and reconnects, reverting on failure | `bin/karchy-network-band:127-168` |
| QR share / password | `karchy-network-qr` and `karchy-network-password` read the PSK with `nmcli --show-secrets` (no prompt: see §3 S-6), stdout only, never argv | `bin/karchy-network-qr:39-41`, `bin/karchy-network-password:13-34`, `shell/plugins/panels/wifiqr/Panel.qml:145-209` |
| Regulatory domain | udev rule on `ieee80211` add → `karchy-wifi-regdomain.service`; path unit on `/etc/localtime`; `iw reg set` from zone.tab, `/etc/karchy/wifi-country` overrides | `system/wifi/*`, `packaging/pkgbuilds/karchy-settings/PKGBUILD:78-80`, `install/setup.sh:50` |
| Bluetooth tethering | None. bluez is installed and NM can do PAN/DUN, but karchy has no UI or command for it | no matches for tether/panu/nap in `bin`, `shell/plugins` |
| Ethernet | Handled by NM's auto profile ("Wired connection 1"); panel hero shows "Ethernet (2.5gbit)" | `Panel.qml:436-447,1178`, `Model.js:91-95` |
| Airplane mode | None. The panel toggles NM's `WirelessEnabled` only; `Networking.wifiHardwareEnabled` (exposed by Quickshell 0.3.2) is unused; no `XF86RFKill` binding. linux-cachyos has `CONFIG_RFKILL_INPUT=y`, so the Framework's airplane key probably toggles radios in the kernel with no OSD or panel state (*inferred*) | `Panel.qml:131,201-205,1234-1250`; `host: quickshell-network.qmltypes`; `host: /proc/config.gz` |
| Polkit / sudo | karchy adds **no** network sudo or polkit rule. NM 1.58's own `org.freedesktop.NetworkManager.rules` grants `settings.modify.system` to local wheel users without a password; `settings.modify.global-dns` stays `auth_admin_keep` | `system/sudoers.d/karchy`; `host: /usr/share/polkit-1/rules.d/org.freedesktop.NetworkManager.rules` |
| Containers (D-63) | Rootless Podman with `netavark`, `aardvark-dns`, `passt`. No bridges on the host, no ufw rules. Container DNS goes through pasta to the host resolver. Published ports are host sockets, so ufw blocks them from the LAN (*inferred*) | `bin/karchy-feature-containers:20` |
| VMs (D-63) | QEMU `-netdev user` (slirp): no bridge, no dnsmasq, no libvirt `virbr0`. Guest DNS goes through slirp to the host resolver, and guest traffic follows the host's routes (so through the VPN) | `bin/karchy-vm:384-388` |

### The VPN plugin (`nulifyer.vpn`, own repo per D-21)

- **Type:** WireGuard only. One NM WireGuard profile, one IPv4 peer, full tunnel `0.0.0.0/0`, fixed listen port (`vpn/README.md:21-26`, `vpn/scripts/system.py:141-162`). No OpenVPN, no Tailscale.
- **Modes:** Off, Auto (VPN on untrusted networks, direct on trusted) and On (`vpn/libexec/nulifyer-vpn-control:72-130`).
- **How it uses NM:**
  - It flips `connection.autoconnect` on the WireGuard profile and runs `nmcli connection up/down` from a root **monitor run every 5 s** (`vpn/systemd/nulifyer-vpn-monitor.timer:5-6`, `vpn/libexec/nulifyer-vpn-monitor:105-184`).
  - A dispatcher hook, also linked into `pre-up.d`, rewrites DNS on every untrusted Wi-Fi or Ethernet profile (`vpn/networkmanager/90-nulifyer-vpn:15-30`, `vpn/scripts/system.py:243-246`).
- **Kill switch:** its own nft table `inet nulifyer_vpn_guard`, an output-hook chain that drops everything except loopback, DHCP, IPv6 ND, DoH to Quad9, the WireGuard endpoint and (when ready) the tunnel (`vpn/libexec/nulifyer-vpn-guard:104-124`). It also inserts iptables rules into ufw's `ufw-before-input` (`vpn/libexec/nulifyer-vpn-home-reply:16-87`).
- **DNS:**
  - On untrusted networks, each saved profile is **persistently** changed to `127.0.0.1`, a dnscrypt-proxy instance forwarding to Quad9 DoH, and snapshotted under `/var/lib/nulifyer-vpn/profiles` (`vpn/libexec/nulifyer-vpn-configure-dns:112-132`).
  - While the tunnel is up, the WireGuard profile's `dns-priority -100` makes the VPN's DNS exclusive (`vpn/README.md:61-64`).
  - On trusted networks the original profile DNS is restored.
- **Trust:** `TRUSTED_UUIDS` in `/etc/nulifyer-vpn/config` (`vpn/examples/config:9-14`). This list is separate from karchy's `/etc/karchy/trusted-networks`.
- **Privileges:**
  - Install: `sudo python3 scripts/system.py install` run from the plugin checkout (`vpn/README.md:79-95`). It copies helpers to `/usr/local/{bin,libexec}`, units to `/etc/systemd/system`, and a per-user polkit rule letting the user `pkexec` the control helper with no password (`vpn/polkit/49-nulifyer-vpn.rules.in:3-6`).
  - Runtime root code is root-owned and hash-checked against a receipt (`vpn/scripts/system.py:264-280`).
- **Shell side:** runs `nulifyer-vpn-status --json` on a timer, **every 2 s even with the panel closed** (`vpn/Panel.qml:268-274`). Each run spawns about 10 processes (nmcli ×4, ip ×2, jq, sed) (`vpn/bin/nulifyer-vpn-status:11-55`). It reads theme colors from `~/.local/state/omarchy/...`, a path karchy renamed (`vpn/Panel.qml:244`), and draws a raw glyph `""` outside the icon map (`vpn/Panel.qml:306`).
- **Packaging:** not in karchy. There is no PKGBUILD, and the plugin isn't in the default `shell.json` (`karchy/shell.json:77` `"plugins": []`), although D-52 says "each plugin is its own package".

### Who reads NM state

| Reader | How | Cost |
|---|---|---|
| Network bar icon and panel | `Quickshell.Networking` (NM D-Bus, events) for devices, networks and connectivity | good |
| Panel details | `karchy-network-status --verbose` every 1.5 s **while open** (ip, jq, iw, 2 pings) (`Panel.qml:966-972`) | fine (open only) |
| Band | `karchy-network-band` every 4 s while open (several nmcli) (`Panel.qml:933-943`) | fine (open only) |
| OWE edge case | nmcli every 5 s while the connected network reports no strength, **even closed** (`Panel.qml:895-902`) | rare |
| Portal wait | `nmcli networking connectivity check` every 2 s, then every 15 s, during sign-in (`bin/karchy-network-captive-portal:91-105`) | bounded |
| VPN bar widget | `nulifyer-vpn-status --json` every 2 s, **always** | breaks the AGENTS.md event rule (`AGENTS.md`, "Long-running code reacts to events") |
| VPN root monitor | systemd timer every 5 s, always | root process churn; ~17k unit runs a day (*inferred* journal noise) |

---

## 2. Ownership: one owner per concern

Ownership test (codebase-design): "This owns ___ for the external system ___, or is shared by ___ and ___."

| Concern | Owner today | Duplication or gap | Proposed owner |
|---|---|---|---|
| Wi-Fi/Ethernet connections | NM + Quickshell.Networking (panel) | none | unchanged |
| "Is this network trusted?" | **Two lists**: `/etc/karchy/trusted-networks` (karchy, Settings) and `TRUSTED_UUIDS` (VPN plugin, hand-edited) | D-33 says one shared list; it isn't | **karchy owns the list** (`karchy-trusted-networks`, root file). The VPN plugin reads it instead of `TRUSTED_UUIDS`. A trust entry records the network's identity (UUID + gateway MAC, see S-2) |
| Upstream DNS | Nobody in karchy (DHCP). The VPN plugin rewrites saved profiles to dnscrypt-proxy on untrusted networks | Two writers to per-connection DNS if Settings ever edits a profile's DNS: the plugin's snapshot and restore would silently undo it (`vpn/libexec/nulifyer-vpn-configure-dns:29-59`) | **karchy owns upstream DNS policy** (one root helper, Settings › Network › DNS) using resolved's native DNS-over-TLS and NM's runtime or global DNS (NM 1.58 accepts `dns+tls://ADDR#SNI`; `host: man NetworkManager.conf` "global-dns-domain"). **The VPN owns DNS only while its tunnel is up** (its negative `dns-priority` already does that). dnscrypt-proxy goes away. Amends D-44 (decision N-2) |
| mDNS / `.local` | **Two responders**: avahi and resolved | both answer and announce the hostname; avahi typically renames to `host-2.local` on a conflict | **avahi** (D-38 keeps it for NAS/printers). resolved: `LLMNR=no`, `MulticastDNS=no` |
| Packet filter | ufw (rules), karchy (`ufw allow` for LocalSend), VPN plugin (raw iptables into `ufw-before-input` + its own nft table) | three writers; the plugin's iptables inserts are lost on `ufw reload` until the next 5 s monitor run re-adds them (`vpn/libexec/nulifyer-vpn-monitor:105`; *inferred*) | ufw stays the owner of *inbound* policy (karchy writes only its comment-tagged rules). The VPN plugin owns only its *outbound* guard table. The hairpin reply rule should become a ufw `before.rules` include the plugin package ships, not a live insert |
| Captive portal | NM detects (Arch URL); karchy opens a different URL (omacom.io); the helper pauses Tailscale | URL mismatch with D-15; no VPN awareness | karchy owns the sign-in flow. It asks the VPN for a timed **portal pause** through one command (`nulifyer-vpn portal-pause`, new), replacing the Tailscale code |
| VPN status | Plugin status file `/run/nulifyer-vpn/status`, read by polling | polling | the plugin publishes the file (it already writes it atomically, `vpn/libexec/nulifyer-vpn-control:15-29`). The shell watches it (`FileView watchChanges`). The network panel reads it through a small adapter in `panels/network/Model.js` |
| Band pin, metered, MAC privacy, auto-connect | Band: `karchy-network-band`; others: nobody | none | all are **NM profile properties**. The NM profile is the only store (no karchy JSON), shown in Settings. Unlike D-27's JSON pattern, these are already system state with one owner |
| Connection details (IP, gateway) | `karchy-network-status` via `ip route get 1.1.1.1` | picks the tunnel while the VPN is up (B-4) | `karchy-network-status` reports the **underlying link** (NM primary connection or default route excluding VPN devices) plus a separate VPN block |
| Wi-Fi country | udev/path units + `/etc/karchy/wifi-country` | no UI | Settings › Network › Advanced (read the effective country with `iw reg get`) |

Polkit seams that already exist and are enough:
- NM's wheel rule covers profile edits (band, metered, MAC, auto-connect).
- `pkexec` with a named polkit action covers root-file changes (trust list, DNS policy).
- The VPN's control helper keeps its passwordless rule for mode changes only.

---

## 3. Bugs and risks

### Bugs (B) and risks (S), most important first

**B-1. The VPN kill switch and the captive portal deadlock** (high).
- On a café network in Auto or On, the guard is in `connecting`. Its output chain then drops everything except DoH to Quad9, DHCP, ND and the WireGuard endpoint (`vpn/libexec/nulifyer-vpn-guard:104-124`).
- NM's HTTP connectivity probe and the portal's login page are dropped. The handshake can't complete because the portal blocks UDP.
- *Inferred:* NM reports `none` or `limited`, not `portal`, so karchy's "Sign into network" button never appears (`Panel.qml:500,1255-1274`).
- `karchy-network-captive-portal` only knows how to pause a **Tailscale** exit node (`bin/karchy-network-captive-portal:17-35,111-114`), and karchy dropped Tailscale (`docs/components.md:59`).
- **What the user sees:** "Limited internet access" or "Tunnel unreachable" forever. The only way out is VPN Off.

**B-2. Two trust lists; D-33 isn't implemented as written** (high).
- Settings › Network edits only `/etc/karchy/trusted-networks` (`shell/plugins/settings/NetworkSection.qml:91`). The VPN reads `TRUSTED_UUIDS` (`vpn/libexec/nulifyer-vpn-control:92-98`).
- When "Home" is trusted in Settings but not in the VPN config, Auto mode raises the VPN at home. The guard's `ready` rule then allows only the tunnel interface (`vpn/libexec/nulifyer-vpn-guard:97-98,117-120`). With NM's WireGuard routing (*inferred*), LAN traffic still leaves on `wlan0`, so it is dropped.
- **What breaks:** NAS automounts (D-24), printers, LocalSend replies. Settings still says "trusted".

**B-3. The network panel misreports while a full-tunnel VPN is up** (medium, *inferred*).
- `karchy-network-status` picks the interface with `ip route get 1.1.1.1` (`bin/karchy-network-status:25,88`). With the tunnel up that resolves to the WireGuard device.
- The device has no `/wireless`, so `type` is `ethernet` (`:111-128`). The panel then:
  - shows the tunnel IP as "IP Address" with no gateway (`Panel.qml:1304-1305`)
  - hides the QR share, because `canShareWifi` needs `info.type === "wifi"` (`Panel.qml:127`)
  - labels the speed test "Ethernet" (`Panel.qml:743-744`)

**B-4. The captive-portal URL contradicts D-15** (medium).
- The panel opens `http://ping.omacom.io/nm-check.txt` (`Model.js:47`), and the floating window rule matches that host (`default/hypr/apps/captive-portal.lua:3`). NM itself checks Arch's URL.
- This can't be fixed by switching to Arch's URL. Omarchy's own comment explains that archlinux.org is HSTS-preloaded for every subdomain, so browsers force HTTPS and the portal can't intercept (`omarchy/etc/NetworkManager/conf.d/omarchy-connectivity.conf:1-8`). The sign-in URL needs a plain-HTTP, non-HSTS host. Decision N-3.

**B-5. Two mDNS responders, and LLMNR on** (medium).
- No resolved drop-in ships, so Arch's defaults apply. This host shows `+LLMNR +mDNS` with mDNS scopes on `wlan0` alongside avahi.
- Symptoms: hostname conflicts (`name-2.local`) and duplicate answers. The machine also answers LLMNR name queries on public Wi-Fi.
- Omarchy's fix is three lines (`omarchy/etc/systemd/resolved.conf.d/10-disable-multicast.conf`).

**B-6. The LocalSend firewall rule survives a reboot** (medium).
- `ufw allow in on wlan0 … 53317` is persistent (ufw writes `user.rules`) (`bin/karchy-localsend-firewall:42-44`).
- NM doesn't deactivate connections at shutdown, so no `down` event removes the rule. After a reboot at a café, the port is open on `wlan0` until the first dispatcher `up` runs.
- The window is short but real. The same happens if NM never connects.
- Fix: run the script once at boot, before NetworkManager. With nothing active, it removes every karchy rule.

**B-7. The password prompt always says "Wrong password"** (low).
- Inside the expanded prompt, the failure text is hard-coded (`Panel.qml:1865`), although `failureReason` may be "Network lost", "Connection failed" or a timeout (`Model.js:394-403`, `Panel.qml:1007-1026`).
- The message also vanishes after 2 s (`Panel.qml:1772-1781`), before most people have read it.

**B-8. Wi-Fi blocked by hardware or airplane mode is invisible** (low).
- The switch binds to `Networking.wifiEnabled` only (`Panel.qml:1237`). With a hard block the switch flips and nothing happens, with no message. `wifiHardwareEnabled` exists and is unused.

**B-9. Dead Tailscale code** (low).
- In `bin/karchy-network-captive-portal:10-35,111-114` and the `tailscale.*` strings (`default/i18n/en/shell.json:459+`). Replace it with the VPN pause from B-1.

**B-10. The VPN panel polls and won't follow the theme under karchy** (low).
- Polling is described above. Under karchy the theme path doesn't exist (`vpn/Panel.qml:244`), so the "protected" green falls back to the accent.
- The raw glyph `` (`vpn/Panel.qml:306,371`) bypasses `icons.json` (D-64). It is the Font Awesome shield, not the Material family.
- Its help text and README use `omarchy plugin add` and `--after omarchy.network` (`vpn/README.md:39-40`).

**B-11. The trust-change prompt shows a raw command, and Cancel shows as an error** (low).
- The polkit card reads "Authorize running '/usr/bin/karchy-trusted-networks set 9370cec8-… true'" (design-audit §5). No polkit action gives it a message.
- Dismissing the prompt (pkexec exit 126) is reported as "Couldn't change whether that network is trusted." (`NetworkSection.qml:36-43,50-56`).

### Security risks

**S-1. The VPN plugin installs root code from a user-writable checkout** (medium).
- The README has the user run `sudo python3 scripts/system.py install` inside `~/.config/.../plugins/nulifyer.vpn` (`vpn/README.md:79-95,118-121`). That script and everything it copies are writable by any process of the user at the moment root runs them.
- Runtime is safe afterwards (root-owned copies, receipt hashes, `vpn/scripts/system.py:264-280`). The install and update path breaks the spirit of D-50/D-55 and bypasses D-51 (pacman delivery).
- Fix: a `nulifyer-vpn` package with the helpers in `/usr/lib/nulifyer-vpn`, units in `/usr/lib/systemd/system`, the dispatcher in `/usr/lib/NetworkManager/dispatcher.d`, and a wheel-group polkit rule instead of a generated per-user one.

**S-2. Trust follows a profile UUID, which isn't a network identity** (medium-high once trust also turns the VPN off).
- NM's auto-created "Wired connection 1" is reused for **every** Ethernet jack. Trusting home Ethernet trusts every hotel and office cable.
- An open Wi-Fi profile is joined by any access point with the same SSID (evil twin).
- Today the cost is an open LocalSend port. After N-1 it would also mean VPN off and DHCP DNS.
- Evidence: trust is a bare UUID match (`bin/karchy-localsend-firewall:22-26`, `vpn/libexec/nulifyer-vpn-monitor:131-140`).
- Fix: Windows' approach. Record the gateway's MAC address (and, for Wi-Fi, the security type) when trusting. Trust applies only when both match. Settings shows "Trusted, but a different router: not trusted now".

**S-3. Enterprise Wi-Fi without server verification** (medium for eduroam/office users).
- The panel's 802.1X flow creates PEAP/MSCHAPv2 with no `ca-cert`, `system-ca-certs` or `domain-suffix-match` (`Model.js:385-392`).
- An evil-twin RADIUS server can capture the MSCHAPv2 exchange, which is crackable offline.
- Fix: `802-1x.system-ca-certs yes` plus `domain-suffix-match` defaulted from the identity's realm. "Connect without checking the server" only behind an explicit warning.

**S-4. The kill switch has no LAN exception, even on trusted networks in On mode** (medium, usability).
- See B-2's mechanism. On mode at home blocks the NAS and printers.
- Recommendation: allow local-network output on *trusted* networks in On mode. Keep it blocked on public networks.

**S-5. The guard blocks NTP while connecting** (low).
- `udp/123` isn't in the guard's allow list (`vpn/libexec/nulifyer-vpn-guard:109-120`), so the clock can't sync until the tunnel is up.
- With a sane RTC this doesn't matter. With a dead RTC battery, DoH TLS validation could fail.

**S-6. NM's wheel rule exposes every saved secret to any user process** (accepted, documented).
- Arch's NM 1.58 ships a rule giving local wheel users `settings.modify.system` without a password. Any process in the session can therefore read all Wi-Fi passwords and the WireGuard private key (`nmcli --show-secrets`) and rewrite DNS or routes.
- This is how QR share and band pinning work without prompts.
- No cheap mitigation. Agent-owned secrets would break boot-time auto-connect. Note it in docs; don't fight upstream.

**S-7. Verified OK.** Root-run karchy network code is path-safe:
- The dispatcher calls `/usr/bin/karchy-localsend-firewall`, a link into the root-owned `/usr/share/karchy`.
- `pkexec` targets `/usr/bin/karchy-trusted-networks`, which calls the firewall script by absolute path. Neither follows `KARCHY_PATH`, so D-55's dev mode can't redirect them.
- Device names are validated before reaching `ufw` (`bin/karchy-localsend-firewall:23`), UUIDs before writing (`bin/karchy-trusted-networks:48`). The Wi-Fi country override reaches `iw` as an argument, not shell.
- Secrets: the PSK goes in-process (`connectWithPsk`), the 802.1X password through stdin (`Model.js:381-392`, `Panel.qml:842-850`), the QR and password helpers write stdout only. Nothing secret appears in argv.

---

## 4. UI/UX proposal (frontend-design pass)

### 4.1 User stories (assumed from the brief and the audits; no user research)

| # | Who, when | Wants | Success | Frequency, cost of a mistake |
|---|---|---|---|---|
| U1 | Laptop at a café or airport | Join Wi-Fi, sign in, be protected without thinking | Online, VPN protecting, no leak in between | weekly; a leak or being stuck offline |
| U2 | At home, docked | NAS, LocalSend, printer just work; VPN stands by | Local devices reachable, VPN off | daily; high annoyance if the NAS breaks |
| U3 | "It's slow" | See whether it's Wi-Fi, the router or the internet; maybe pin the band | Knows where the problem is in one look | monthly |
| U4 | A guest asks for the Wi-Fi | Show a QR | Phone joins | monthly |
| U5 | A site blocks VPN | Turn the VPN off for now, then back to Auto | One click each way, state visible | monthly; forgetting it's off |
| U6 | Privacy setup, once | Encrypted DNS from a provider they trust | Set once, applies where it should | once; local names breaking |
| U7 | On a plane | All radios off | One key or one click, clearly shown | rare |
| U8 | Desktop, wired only | No Wi-Fi clutter; Ethernet + VPN status | Panel shows only what exists | daily glance |

### 4.2 The model the screens depend on

- Network state is a combination, not a single value:
  - **link**: none, wifi-off, airplane, hardware-blocked, disconnected, connecting, connected
  - **internet**: unknown, full, portal, limited, none
  - **trust**: trusted, public, trusted-but-different-router
  - **VPN**: absent, off, standing-by (Auto on trusted), connecting (internet blocked), protecting, failed (internet blocked), paused-for-sign-in
- Combinations that never happen: VPN protecting with link none; portal while VPN protecting (the portal page wouldn't load); standing-by on a public network.
- What finishes each task:
  - "connect": the network is connected *and* internet is full, or the portal is shown as the next step
  - "sign in": internet full, then the VPN pause ends by itself
  - "VPN off": the mode is saved and the guard is down
- **One name per concept everywhere:** "Trusted network", "VPN", "Sign in to network", "Airplane mode", "Encrypted DNS".

### 4.3 What goes where (the panel-vs-window rule from design-audit §6.3)

A **panel** answers "am I online, am I protected, and what needs me now?" with one-step actions. **Settings › Network** answers "show me everything and let me change it".

| Item | Bar icon | Network panel | Settings › Network | Why |
|---|---|---|---|---|
| Link type and strength | glyph (`net.wifi.0-4`, `net.ethernet`) | hero | status card | glance |
| Restricted (portal or limited) | `*.restricted` glyph, warning color | hero status + attention row | — | needs action |
| VPN protecting | **glyph variant** (lock overlay on the network icon; see N-4) | VPN row: status + Off/Auto/On | VPN page: profile, policy, LAN access | U1, U5 |
| VPN connecting or failed | warning or error color on the icon | attention row: "Internet is blocked until the VPN connects" + Retry / "Use without VPN" | — | U1 recovery |
| Captive portal sign-in | — | primary button in the attention row; with a VPN it says it pauses protection | — | U1 |
| Wi-Fi on/off | — | hero switch (only if a radio exists) | — | U7, U8 |
| Airplane mode | `net.airplane` glyph | hero state "Airplane mode" + "Turn off" (a key toggles it, N-5) | — | U7 |
| Connect / disconnect / forget Wi-Fi | — | network list (as today) | saved-networks list (forget, plus networks out of range) | daily |
| Wrong password | — | inline prompt keeps the field, says "Wrong password for X", stays until edited | — | recovery without retyping the name |
| Band pin | — | band row (as today) | per saved network (clear pins out of range) | audit-distros §3 |
| QR share | — | hero action (as today) | per saved network (optional) | U4 |
| Speed test | — | hero action (as today) | — | U3 |
| Ping, loss, IP, gateway | — | compact details (keep ping, loss, IP, gateway; drop Downloaded/Uploaded totals, which change nothing) | full per-connection details: IPv4/IPv6, DNS servers in use, MAC, link speed | U3 |
| Trusted network | — | shown in the VPN row's status ("Standing by on trusted network") | toggle per saved network, with the router check (S-2) | consequential, needs a password |
| Upstream DNS, presets, DoT | — | — | DNS page | U6, set once |
| Per-connection IP/DNS manual | — | — | saved network › IP settings | rare, expert |
| Metered | — | — | saved network | rare |
| Private Wi-Fi address (MAC) | — | — | saved network: Off (default) / Per network (`cloned-mac-address=stable`) | rare; default off so DHCP reservations keep working |
| Hidden network | — | — | "Join hidden network…" | rare |
| VPN profiles import / remove | — | — | VPN page: import `.conf` (WireGuard), `.ovpn` later | rare |
| Firewall / LocalSend | — | — | "Sharing and firewall": LocalSend receives on trusted networks (state), firewall on, open ports right now (read-only) | trust |
| Wi-Fi country | — | — | Advanced (effective country + override) | rare |
| Connectivity check on/off | — | — | Advanced (privacy) | rare |
| Hotspot | — | not now | not now | needs dnsmasq and ufw forward rules (ufw's forward policy drops); later feature |
| Proxy | — | — | not planned | apps don't read NM's proxy; env-based setups belong to the user |
| Bluetooth tethering | — | — | not planned | NM can do PAN; add only if asked |

### 4.4 Comparison

| Topic | Windows 11 | KDE Plasma 6 | karchy proposal |
|---|---|---|---|
| Quick surface | Quick settings tiles: Wi-Fi (toggle + list), Airplane, Hotspot, VPN (list), Nearby sharing | Networks applet: list, per-connection details with speed graph, Wi-Fi and airplane toggles, hotspot toggle, "Configure" link | One network panel: hero (link + switch), attention row, VPN row, details, band, Wi-Fi list, "Network settings…" footer |
| VPN | Separate tile and Settings › VPN (add, connect, options) | VPN connections listed in the applet like any connection | VPN row in the network panel (policy-level: Off/Auto/On); profiles in Settings |
| Trust | Network profile type per network: Public / Private (firewall and discovery follow it) | Firewall zone per connection (firewalld) | "Trusted network" per saved network, bound to the router; drives LocalSend, VPN Auto and DNS |
| DNS | Per adapter: Automatic / Manual, with DNS over HTTPS per server | Per connection, IPv4/IPv6 DNS fields | Global "DNS servers" (Automatic / preset / custom) + "Encrypted DNS", applied to public networks by default; per-connection override in the saved network |
| Details | Hardware and connection properties page | Details tab in the applet; connection editor | Compact in the panel, full in Settings |
| Captive portal | Opens the browser automatically | Notification and browser | Panel attention row; with the VPN, an explicit "Sign in (pauses the VPN)" |

### 4.5 Panel wireframe (380 wide, existing anatomy and components)

```
┌────────────────────────────────────────┐
│ [net.wifi.3]  Home-5G           [qr][⏱][●━]│  PanelHero: title = network, trailing QR, speed test, Wi-Fi switch
│               CONNECTED · VPN STANDING BY  │  real conclusion, not rotating phrases
├────────────────────────────────────────┤
│ ⚠ Sign in to this network        [Sign in] │  InlineMessage (warning), only when needed
├────────────────────────────────────────┤
│ VPN   Standing by on trusted network       │  ListRow + ButtonGroup
│       [ Off | Auto | On ]                  │
├────────────────────────────────────────┤
│ Ping 12 ms   Loss 0%   IP 192.168.50.23  …│  KeyValueGrid, 2 columns, 4 rows max
├────────────────────────────────────────┤
│ WI-FI BAND: 5GHZ              AUTOMATIC ●━ │  as today
├────────────────────────────────────────┤
│ KNOWN NETWORKS                             │
│ [▂▄▆] Home-5G           Connected          │
│ OTHER NETWORKS                             │
│ [▂▄_] CoffeeBar                       [🔒] │
├────────────────────────────────────────┤
│ [ Network settings…                     ↗] │  footer Button → Settings › Network at this connection
└────────────────────────────────────────┘
```

Rules:
- The attention row exists only while a state needs the person. One primary action, its consequence in the label:
  - captive: "Sign in" (with the VPN in Auto/On: "Sign in, VPN paused until online")
  - VPN failed: "Retry", plus a quieter "Use without VPN" that switches the mode to Off and says so
  - airplane: "Turn off airplane mode"
  - hardware switch: info only, no action
  - NM not running: "Restart networking" (`karchy-restart-wifi`)
- The VPN row appears only when a VPN is configured. Without the policy plugin, plain NM WireGuard/OpenVPN profiles appear as switch rows (generic adapter). With it, the segmented Off/Auto/On control.
- The rotating phrases are removed ("Bending light", `Panel.qml:58-68,974-995`; the VPN panel has its own set, `vpn/Panel.qml:33-38`). They take the place of real status and animate without reason. Decorative motion is a habitual default the frontend-design skill rules out.
- The footer follows the Containers/VMs precedent ("Manage containers…", `shell/plugins/containers/Panel.qml:89-121`).
- Keyboard: the focus chain becomes header → attention → VPN → band → list → footer, extending today's model (`Panel.qml:120-123`).
- Icons: add `net.airplane` (md-airplane) and a VPN-protected network glyph to `default/karchy/icons.json`. The VPN uses `net.vpn` everywhere (`icons.json:77`). Don't reuse `security.secureboot`'s shield: one icon, one meaning.

### 4.6 States table (what the person sees)

| State | Bar | Hero title / status | Attention row | Wi-Fi list |
|---|---|---|---|---|
| No adapter | `net.network`, dimmed | "No network adapter" / — | EmptyState: "Plug in Ethernet or a USB Wi-Fi adapter" | hidden |
| NM not running | `net.wifi.off`, dimmed | "Networking is off" | "Restart networking" | hidden |
| Airplane | `net.airplane` | "Airplane mode" | "Turn off airplane mode" | hidden |
| Wi-Fi off (soft) | `net.wifi.off` | "Wi-Fi is off" + switch | — | hidden |
| Hardware blocked | `net.wifi.off` | "Wi-Fi is off with the hardware switch" (no switch) | info | hidden |
| Disconnected | `net.wifi.off` | "Not connected" | — | focused |
| Connecting | animated strength | "Connecting to CoffeeBar…" | — | row "Connecting…" |
| Wrong password | `net.wifi.off` | "Not connected" | — | row expanded: "Wrong password for CoffeeBar", field kept, focus in it |
| Connected, full | strength | SSID / "CONNECTED" (+ " · VPN PROTECTING") | — | normal |
| Portal | `net.wifi.restricted`, warning | SSID / "SIGN-IN REQUIRED" | "Sign in" (+ VPN pause note) | row "Sign-in required" |
| Limited | restricted, warning | SSID / "NO INTERNET" | "Connected to the router, but the internet doesn't answer" (no action; Reconnect is the row) | normal |
| VPN connecting | strength + warning | … / "VPN CONNECTING · INTERNET BLOCKED" | only after 20 s: "Taking longer than usual" + Retry | normal |
| VPN failed | error color | … / "VPN CAN'T CONNECT · INTERNET BLOCKED" | "Retry" / "Use without VPN"; if the network looks like a portal: "Sign in to network (pauses the VPN)" | normal |
| VPN protecting | VPN glyph variant | … / "CONNECTED · VPN PROTECTING" | — | normal |
| VPN standing by | strength | … / "CONNECTED · TRUSTED NETWORK" | — | normal |

### 4.7 Settings › Network (window; Settings geometry and Cards)

Pages in the Settings sidebar's Network section, top to bottom on one scroll:

1. **Status**: one Card per active connection (Wi-Fi, Ethernet, VPN) with a KeyValueGrid: IP, gateway, DNS in use (from `resolvectl`), link speed or band, MAC. Same names and icons as the panel.
2. **Saved networks**: list, active first. Each row expands in place (the list is worked through item by item):
   - Trusted network (switch; the password prompt names the action; shows "different router" when S-2 detects it)
   - Connect automatically
   - Metered
   - Wi-Fi band (Automatic / 2.4 / 5 / 6, from `karchy-network-band`)
   - Private Wi-Fi address
   - IP settings (Automatic / Manual: address, gateway, DNS)
   - Share (QR)
   - **Forget** (destructive, at the end, confirmed with Cancel focused)
   - Below the list: "Join hidden network…".
3. **DNS**:
   - "DNS servers": Automatic (from the network) / Quad9 / Cloudflare / Custom, one Dropdown.
   - "Encrypted DNS": a switch, shown for presets and custom servers with a TLS name.
   - "Use on trusted networks too": a switch, off by default, so `nas.lan`-style names from the home router keep working.
   - One line of consequence: "While the VPN is connected, it uses the VPN's DNS."
4. **VPN**:
   - The WireGuard profile (import `.conf` → `nmcli connection import type wireguard`).
   - Default mode.
   - "Block the internet while the VPN connects" (the kill switch; on).
   - "Allow local devices on trusted networks" (on; S-4).
   - Last check (handshake age, reachability) as facts.
5. **Sharing and firewall**: "LocalSend can receive files on trusted networks" (state, with the trusted count); firewall "On, blocking incoming connections"; "Open right now: LocalSend on wlan0" (read-only). No rule editor (audit-settings: KDE's firewall kcm is out of scope).
6. **Advanced**: Wi-Fi country (effective + override), connectivity check (on/off with what it sends to whom).

Copy rules:
- Name tasks, not mechanisms ("Encrypted DNS", not "DNSOverTLS").
- Errors say what to do. For example, an import failure: "This file isn't a WireGuard configuration. Choose a .conf file exported by your VPN provider."
- Cancelling a password prompt is not an error (B-11).

### 4.8 The five questions, walked for U1 (café)

1. **Where am I?** The panel hero names the network and says "SIGN-IN REQUIRED".
2. **What can I do, which matters?** One warning row with one button: "Sign in, VPN paused until online".
3. **What will happen?** The label says the VPN pauses. The window opens floating.
4. **Did it work?** The window closes by itself. The hero flips to "CONNECTED · VPN PROTECTING", and a toast says "VPN protecting again".
5. **If it failed?** After 5 minutes the pause ends and protection returns. The row offers "Sign in again", and the toast names the network.

---

## 5. The undecided network tuning rows (`docs/ownership-audit.md`, "Omarchy's system tuning")

| Row | Recommendation | What changes for you |
|---|---|---|
| Wi-Fi power save off (`[connection] wifi.powersave = 2`, `omarchy/etc/NetworkManager/conf.d/omarchy-wifi-powersave.conf`). NM's own default is `ignore`, which leaves the driver's power save on (`host: man NetworkManager.conf` "wifi.powersave … ignore") | **Keep** | No 20–300 ms lag spikes when the Wi-Fi has been idle, and fewer link drops on flaky firmware (the Framework's MT7922 is a known case, audit-distros §1a). Costs a fraction of a watt on battery. |
| ARP only for the interface's own address (`arp_ignore=1`, `arp_announce=2`) | **Keep** | Docked with Ethernet and Wi-Fi on the same network, traffic moves to the cable as it should instead of staying on Wi-Fi. Nothing you'd notice otherwise. |
| TCP MTU probing (`tcp_mtu_probing=1`) | **Keep** | SSH and VPN sessions stop hanging on networks that silently drop large packets (common on hotel Wi-Fi and tunnels). It only kicks in after a stall, so normal links don't change. |
| BBR + fq (`tcp_congestion_control=bbr`, `default_qdisc=fq`). The kernel default is cubic/fq_codel; BBR is a module in linux-cachyos (`host: CONFIG_TCP_CONG_BBR=m`) | **Keep** | Uploads (pushes, backups to the NAS, video calls) hold up better on lossy or long links, with less lag while uploading. On a clean wired LAN, nothing changes. |
| resolved multicast off (`LLMNR=no`, `MulticastDNS=no`) | **Keep, and treat as a bug fix** (B-5) | `.local` names keep working through avahi. No more name conflicts (`laptop-2.local`), and the laptop stops answering name queries on public Wi-Fi. You lose nothing: nsswitch already asks avahi first (`install/setup.sh:40`). |
| Connectivity check URL | **Keep NM's Arch default for detection**; change only the URL the panel opens for sign-in (N-3) | Detection pings Arch's server, which ships with NetworkManager, not Basecamp's. The sign-in button keeps working, because it opens a plain-HTTP page the portal can intercept. |
| Zram swap half of `99-omarchy-sysctl.conf` | Skip (already the audit's advice; D-10 uses zswap) | — |

All five Keep rows go into karchy-settings as drop-ins (`/usr/lib/NetworkManager/conf.d/`, `/usr/lib/sysctl.d/`, `/usr/lib/systemd/resolved.conf.d/`), so hand-made files in `/etc` still win.

---

## 6. Plan

### 6a. Bug fixes (no new features)

| # | Fix | Size | Where |
|---|---|---|---|
| F1 | resolved multicast drop-in (B-5) | S | karchy-settings |
| F2 | Tuning drop-ins after N-5 (power save, ARP, MTU, BBR/fq) | S | karchy-settings |
| F3 | Run `karchy-localsend-firewall` once at boot before NM (B-6): oneshot unit, `After=ufw.service Before=NetworkManager.service` | S | karchy-settings + `bin/` |
| F4 | Password prompt shows the real failure and keeps it until the field is edited (B-7) | S | `Panel.qml:1772-1870` |
| F5 | Use `wifiHardwareEnabled`; show the hardware-switch state (B-8) | S | `Panel.qml` |
| F6 | Polkit action with a message for trust changes; exit 126 = cancelled, not an error (B-11) | S | karchy-settings, `NetworkSection.qml` |
| F7 | `karchy-network-status` reports the underlying link and a separate VPN block (B-3) | S–M | `bin/karchy-network-status`, `Model.js`, `Panel.qml` |
| F8 | Sign-in URL per N-3, in both places (B-4) | S | `Model.js:47`, `captive-portal.lua:3` |
| F9 | 802.1X server verification (S-3) | S–M | `Model.js:385-392`, prompt gets a "Domain" field defaulted from the realm |
| F10 | VPN panel: watch `/run/nulifyer-vpn/status` instead of polling; karchy theme path; icon map (B-10; already in PLAN phase 3) | S | plugin repo |
| F11 | One trust list read by the VPN (B-2, N-1) | M | both repos |
| F12 | Portal pause instead of the Tailscale pause (B-1, B-9): `nulifyer-vpn portal-pause` opens tcp/80+443 on the upstream interface for at most 5 minutes or until connectivity is full; the guard re-closes on its own | M | both repos |
| F13 | Package the VPN plugin (S-1): `/usr/lib` paths, wheel polkit rule, hairpin rule via a ufw `before.rules` include, config written by a root helper | M | plugin repo + `packaging/` |
| F14 | Trust bound to the router (S-2) | M | `karchy-trusted-networks`, `karchy-localsend-firewall`, the VPN's trust read |
| F15 | LAN allowed on trusted networks in On mode (S-4) | S | plugin guard |

Order: F1, F3, F4–F6, F8 first (independent, small). Then F7 and F10. Then F11 + F14 together (they change the trust file format once), then F12, F13, F15.

### 6b. New features

| # | Feature | Size | Depends on |
|---|---|---|---|
| N-a | Panel: attention row, VPN row, compact details, "Network settings…" footer, real status line | M | F7, F10, F11 |
| N-b | Settings › Network: status cards, saved networks expanding in place (trusted, auto-connect, metered, band, MAC, IP, forget, QR), join hidden network | L | F14 |
| N-c | Settings › DNS: presets, Encrypted DNS, applied by one root helper (`karchy-network-dns`, pkexec, NM global or runtime DNS with `dns+tls://`); dnscrypt-proxy removed from the plugin | M–L | N-2, F11 |
| N-d | Settings › VPN: import WireGuard `.conf`, policy options; generic NM VPN switches when the policy plugin isn't installed | L | F13 |
| N-e | Airplane mode: `karchy-airplane` (rfkill all, persisted by systemd-rfkill), OSD, panel state, `XF86RFKill` binding | S–M | N-5 |
| N-f | Settings › Advanced: Wi-Fi country, connectivity check switch | S | — |
| — | Not planned: hotspot (needs `dnsmasq` + ufw forward rules), proxy, Bluetooth tethering | — | — |

---

## 7. Decisions you need to make

| # | Question | Recommendation |
|---|---|---|
| **N-1** | Should "Trusted network" be one list owned by karchy (Settings › Network), meaning LocalSend can receive, VPN Auto stands by, and DNS comes from the network, with the VPN plugin reading it? | **Yes.** It is what D-33 already says, and it fixes B-2. Bind trust to the router at the same time (S-2), since trust will then also switch the VPN off. |
| **N-2** | Who owns upstream DNS? D-44 says the VPN plugin. | **Amend D-44:** karchy owns upstream DNS (Settings › DNS, resolved's built-in DNS-over-TLS, applied on untrusted networks by default); the VPN owns DNS only while its tunnel is up. One fewer daemon (dnscrypt-proxy), and no rewriting of your saved networks. |
| **N-3** | Which plain-HTTP page should "Sign in to network" open? (Arch's URL can't be used: HSTS forces HTTPS.) Options: keep `ping.omacom.io` (Basecamp sees sign-in clicks), `http://neverssl.com` (made for exactly this; a third party too), or host one yourself. | **`http://neverssl.com`**, only on an explicit click; detection stays on Arch's URL. Check in the VM that a test portal intercepts it. |
| **N-4** | How does the VPN show up in the bar? | **Inside the network panel** (VPN row with Off/Auto/On), and the network icon gets a VPN variant while protecting. The plugin's own shield shows only while connecting or failed, so a blocked internet is never hidden. |
| **N-5** | Approve the network tuning set (Wi-Fi power save off, ARP, MTU probing, BBR + fq, resolved multicast off) and an `XF86RFKill` (airplane key) binding? | **Yes to all.** The binding is the only new keybinding, and AGENTS.md needs your approval for it. |
