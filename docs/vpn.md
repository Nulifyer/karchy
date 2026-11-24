# The VPN

Your WireGuard VPN, with a kill switch, as part of karchy (D-68, D-156).

Connect automatically on networks you don't trust, stay off the VPN at home,
or require VPN protection everywhere. The network icon in the bar shows a lock
while the VPN protects the connection, and the network panel shows what it is
doing and whether the tunnel is healthy.

It used to be an add-on, `karchy-vpn`. Since D-156 `karchy-settings` installs
it at the same paths, so a VPN set up with the add-on carries on unchanged.

## What it does

- **Automatic protection.** Connect on untrusted Wi-Fi and Ethernet networks.
- **Your choice of mode.** Off, Auto or On, from the network panel or
  Settings › Network › VPN.
- **A kill switch.** Ordinary internet traffic is blocked while a required
  VPN connection is unavailable.
- **Café sign-in pages work.** The block pauses for up to five minutes to sign
  in; protection comes back by itself once you're online.
- **Home stays home.** In On mode on a trusted network, your NAS, printers and
  the router's own names (`nas.lan`) keep working beside the tunnel.
- **Health you can see.** The last handshake with the server, the server's
  address and the data carried, in the network panel and in Settings.

karchy doesn't provide a VPN account or server: bring the WireGuard file your
provider (or your own server) gives you.

## What you need

- A WireGuard configuration with one IPv4 peer and full-tunnel routing
  (`AllowedIPs = 0.0.0.0/0`).
- A DNS server reachable through your VPN that responds to ping. A file with
  a `DNS =` line has one; otherwise Settings asks for its address.

## Setup

In Settings › Network › VPN, choose **Import WireGuard file…**, then
**Set up VPN**. Setting it up asks for an administrator's password once. It
starts in Auto mode: on networks you haven't trusted, the internet is blocked
until the tunnel connects.

What Set up VPN does (`karchy-network-vpn setup <uuid> [dns]`): it gives the
profile a fixed listen port, the VPN's DNS for every name
(`ipv4.dns-search ~.`, `ipv4.dns-priority -100`) and no autoconnect, writes
the VPN's configuration from the profile, and hands it to `karchy-vpn setup`,
whose root helper checks it and installs it as `/etc/karchy-vpn/config`.

By hand:

```bash
nmcli connection import type wireguard file wgclient.conf
mkdir -p ~/.config/karchy-vpn
cp /usr/share/karchy-vpn/config.example ~/.config/karchy-vpn/config
${EDITOR:-nano} ~/.config/karchy-vpn/config
karchy-vpn setup
```

Match the connection name, interface, endpoint, ports and VPN DNS address to
your WireGuard connection; the example explains each setting. Run
`karchy-vpn setup` again after editing the file.

**Trusted networks.** Mark networks as trusted in Settings › Network; the VPN
reads karchy's list (`karchy-trusted-networks status --json`), which
recognises a network by its router. Untrusted networks use karchy's own DNS
setting.

## Everyday use

| Mode | Behavior |
| --- | --- |
| Auto | Use the VPN on untrusted networks and connect directly on trusted networks. |
| On | Require the VPN on every network. On a trusted network, local devices stay reachable. |
| Off | Use your normal internet connection without the VPN. |

From a terminal:

```bash
karchy-vpn status          # what the VPN does now
karchy-vpn mode auto       # or off, on
karchy-vpn reconnect       # restart the tunnel, keeping the mode
karchy-vpn portal-pause    # let a captive portal's sign-in page through
```

`mode`, `reconnect` and `portal-pause` need no password for members of
`wheel` in the active local session; the polkit rule allows exactly these
commands.

**Signing in to a café network.** While the VPN can't connect, the kill switch
also blocks the network's sign-in page. `karchy-vpn portal-pause` opens web
traffic (TCP 80 and 443) and the network's DNS on that network for at most five
minutes, with the tunnel down. It ends by itself once NetworkManager reports
full connectivity, or at the deadline; then the kill switch closes and the
tunnel connects. The network panel's "Sign in to network" runs it for you.

**Is it healthy?** The network panel's VPN row and Settings › Network › VPN
show the last handshake, the server and the data received and sent.
WireGuard shakes hands with the server again every two minutes while traffic
flows, so on a tunnel that carries everything a handshake older than three
minutes means the server stopped answering; Settings says so in red. The
kernel tells only root, so both read it with
`pkexec /usr/lib/karchy/wireguard-status` (no password in the active
session; it never prints a private or preshared key).

**"Limited" while protected.** NetworkManager checks the internet on the Wi-Fi
or Ethernet link itself, outside the tunnel, and the kill switch stops that
check. So `nmcli networking connectivity` says `limited` while the internet
works through the VPN. The panel goes by the VPN's own check instead (a fresh
handshake and its DNS answering through the tunnel, every minute) and says
"VPN protecting".

**Removing a profile.** Each VPN profile in Settings › Network › VPN has
Remove, which deletes it with its keys. Removing the profile the VPN uses
turns the VPN off first, so nothing is blocked waiting for a tunnel that is
gone; the VPN then waits to be set up with another. A profile deleted another
way (`nmcli connection delete`) has the same effect: the status says
`off (no-profile)` and nothing is blocked.

## Status

`/run/karchy-vpn/status` is JSON, replaced atomically whenever something
changes (never on a timer), so the panel and Settings watch it instead of
polling:

```json
{"version": 1, "mode": "auto", "state": "protecting", "reason": "tunnel-up",
 "network": {"device": "wlan0", "name": "CoffeeBar", "uuid": "…", "type": "wifi",
             "trusted": false, "trust": "not trusted"},
 "tunnel": {"name": "wgclient", "interface": "wgclient"},
 "until": null, "since": 1794700000}
```

| state | reason | Internet |
| --- | --- | --- |
| `off` | `mode` | direct |
| `off` | `no-profile` (its profile is gone) | direct |
| `standing-by` | `trusted` (Auto on a trusted network), `no-network` | direct, or none |
| `connecting` | `starting`, `no-handshake` | blocked |
| `protecting` | `tunnel-up` | through the tunnel |
| `failed` | `no-handshake`, `activation-failed` | blocked; retried every minute |
| `paused` | `sign-in` (`until`: the deadline) | web and DNS on that network only |

`since` is when the state last changed.

## How it works

- Nothing runs until `karchy-vpn setup` writes `/etc/karchy-vpn/config` and
  enables the units.
- `karchy-vpn-guard.service` closes the kill switch at boot, before
  NetworkManager starts, unless the mode is Off.
- The kill switch is its own nftables table, `inet karchy_vpn_guard`. It
  filters outgoing traffic only and never touches ufw's chains. While it is
  closed, only DHCP, IPv6 neighbour discovery, NTP, the WireGuard endpoint,
  encrypted DNS, a ping to the router and the tunnel's health probe leave.
- The policy (`/usr/lib/karchy-vpn/policy`) runs when something changes:
  NetworkManager's dispatcher, a command, or a trust change in karchy.
  WireGuard has no event for a handshake, so the policy also sets itself a
  one-shot timer: every 2 seconds while the tunnel connects, every 60 seconds
  while it protects (a server that stopped answering sends no event either),
  every 10 seconds after a failure, and at the end of a sign-in pause. In Off
  mode and while standing by, nothing runs.
- On a trusted network in On mode, the local network stays reachable and the
  tunnel's live connection (not the saved one) gets NetworkManager's default
  VPN DNS priority instead of the negative one, so the router answers for its
  own domains (`nas.lan`) and the VPN for everything else.
- If your VPN server is behind your home router and the router's hairpin NAT
  answers from its own address, set `TRUSTED_GATEWAY` to the router's address:
  on that network the kill switch's table gives those replies the endpoint's
  address back before connection tracking sees them.

Where the files are: the root helpers in `/usr/lib/karchy-vpn` (from
`system/vpn` in karchy's repository), its units in `/usr/lib/systemd/system`,
the dispatcher hook `90-karchy-vpn`, the polkit action and rule
(`org.karchy.vpn`), and the command `/usr/bin/karchy-vpn`. The design and the
contract with the rest of karchy are in `docs/architecture.md`, "Networking
ownership".
