# nulifyer-vpn

Your WireGuard VPN, with a kill switch, on karchy.

Connect automatically on public networks, stay off the VPN at home, or require
VPN protection everywhere. A shield in your bar shows whether your connection
is protected, with a panel for switching modes and checking connection health.

## Why use it?

- **Automatic protection.** Connect on untrusted Wi-Fi and Ethernet networks.
- **Your choice of mode.** Switch between Auto, On, and Off from the panel.
- **A built-in kill switch.** Block ordinary internet traffic while a required
  VPN connection is unavailable.
- **Café sign-in pages work.** Pause the block for up to five minutes to sign
  in; protection comes back by itself once you're online.
- **Home stays home.** In On mode on a trusted network, your NAS, printers and
  the router's own names (`nas.lan`) keep working beside the tunnel.
- **Bring your own VPN.** Use an existing WireGuard connection in NetworkManager.

This package does not provide a VPN account or server.

It is one of karchy's add-ons (`addons/vpn` in karchy's repository), built and
released with karchy as the `nulifyer-vpn` package: the policy service, kill
switch and polkit rule, plus the bar widget in `/usr/share/karchy/plugins`.
karchy's network panel and Settings › Network › VPN have the VPN controls too.

## What you need

- A NetworkManager WireGuard connection with one IPv4 peer, full-tunnel
  routing (`0.0.0.0/0`), and a fixed client listen port.
- A DNS server reachable through your VPN that responds to ping.

## Setup

### 1. Install the package

Quick install › karchy › WireGuard VPN, or `sudo pacman -S nulifyer-vpn`.
Everything root runs is installed under `/usr` by pacman. Nothing runs from
your home folder.

### 2. Prepare the WireGuard connection

Import your WireGuard configuration in Settings › Network › VPN, or with
`nmcli connection import type wireguard file <file>.conf`. Then configure the
connection to use your VPN DNS for all domains. Replace `wgclient` and
`10.66.0.1` below with your connection name and VPN DNS address:

```bash
nmcli connection modify wgclient wireguard.peer-routes yes \
  ipv4.dns 10.66.0.1 ipv4.dns-search '~.' ipv4.dns-priority -100
```

### 3. Configure and start it

```bash
mkdir -p ~/.config/nulifyer-vpn
cp /usr/share/nulifyer-vpn/config.example ~/.config/nulifyer-vpn/config
${EDITOR:-nano} ~/.config/nulifyer-vpn/config
nulifyer-vpn setup
```

Match the connection name, interface, endpoint, ports and VPN DNS address to
your WireGuard connection; the example explains each setting. `setup` asks for
your password, checks the connection, installs the configuration as
`/etc/nulifyer-vpn/config` and starts the service. A new installation starts
in Auto mode. Run it again after editing the file. Until then the widget says
the VPN isn't set up.

**Trusted networks.** Mark networks as trusted in Settings › Network; the VPN
reads karchy's list (`karchy-trusted-networks status --json`), which
recognises a network by its router. Untrusted networks use karchy's own DNS
setting.

### 4. The bar widget

Quick install turns the widget on next to the network icon. It takes its
colors from the shell's theme roles and reads the status file when the file
changes; while the file is missing it looks for it every 30 seconds.

## Everyday use

Left-click the shield to open the panel. Right-click to cycle through modes.

| Mode | Behavior |
| --- | --- |
| Auto | Use the VPN on untrusted networks and connect directly on trusted networks. |
| On | Require the VPN on every network. On a trusted network, local devices stay reachable. |
| Off | Use your normal internet connection without the plugin's protection. |

From a terminal:

```bash
nulifyer-vpn status          # what the VPN does now
nulifyer-vpn mode auto       # or off, on
nulifyer-vpn reconnect       # restart the tunnel, keeping the mode
nulifyer-vpn portal-pause    # let a captive portal's sign-in page through
```

`mode`, `reconnect` and `portal-pause` need no password for members of
`wheel` in the active local session; the package's polkit rule allows exactly
these commands.

**Signing in to a café network.** While the VPN can't connect, the kill switch
also blocks the network's sign-in page. `nulifyer-vpn portal-pause` opens web
traffic (TCP 80 and 443) and the network's DNS on that network for at most five
minutes, with the tunnel down. It ends by itself once NetworkManager reports
full connectivity, or at the deadline; then the kill switch closes and the
tunnel connects. karchy's "Sign in to network" runs it for you.

## Status

`/run/nulifyer-vpn/status` is JSON, replaced atomically whenever something
changes (never on a timer), so a bar or panel can watch it instead of polling:

```json
{"version": 1, "mode": "auto", "state": "protecting", "reason": "tunnel-up",
 "network": {"device": "wlan0", "name": "CoffeeBar", "uuid": "…", "type": "wifi",
             "trusted": false, "trust": "not trusted"},
 "tunnel": {"name": "wgclient", "interface": "wgclient"},
 "until": null, "integration": "karchy", "since": 1794700000}
```

| state | reason | Internet |
| --- | --- | --- |
| `off` | `mode` | direct |
| `standing-by` | `trusted` (Auto on a trusted network), `no-network` | direct, or none |
| `connecting` | `starting`, `no-handshake` | blocked |
| `protecting` | `tunnel-up` | through the tunnel |
| `failed` | `no-handshake`, `activation-failed` | blocked; retried every minute |
| `paused` | `sign-in` (`until`: the deadline) | web and DNS on that network only |

`since` is when the state last changed.

## How it works

- `nulifyer-vpn-guard.service` closes the kill switch at boot, before
  NetworkManager starts, unless the mode is Off.
- The kill switch is its own nftables table, `inet nulifyer_vpn_guard`. It
  filters outgoing traffic only and never touches ufw's chains. While it is
  closed, only DHCP, IPv6 neighbour discovery, NTP, the WireGuard endpoint,
  encrypted DNS, a ping to the router and the tunnel's health probe leave.
- The policy (`/usr/lib/nulifyer-vpn/policy`) runs when something changes:
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

## Remove

Quick install › karchy › WireGuard VPN › Remove, or `sudo pacman -R nulifyer-vpn`.

Removing the package takes the tunnel down, removes the kill switch, restores
the DNS settings it changed and keeps your WireGuard connection and keys.

## License

[MIT](LICENSE).
