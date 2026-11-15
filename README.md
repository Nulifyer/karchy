# Omarchy VPN

Your WireGuard VPN, with a kill switch, in the Omarchy bar.

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

This plugin does not provide a VPN account or server.

The system half (policy service, kill switch, polkit rule) is a pacman
package, `nulifyer-vpn`; the bar widget is the Omarchy plugin. On
[karchy](https://github.com/Nulifyer/karchy) the network panel has the VPN
controls built in and only the package is needed.

## What you need

- A NetworkManager WireGuard connection with one IPv4 peer, full-tunnel
  routing (`0.0.0.0/0`), and a fixed client listen port.
- A DNS server reachable through your VPN that responds to ping.
- NetworkManager with systemd-resolved.
- Without karchy: DNSCrypt-proxy for encrypted DNS on untrusted networks.

## Setup

### 1. Install the package

On karchy: `sudo pacman -S nulifyer-vpn` (from the `[karchy]` repository).

On stock Omarchy, build it from this repository's release:

```bash
git clone https://github.com/Nulifyer/omarchy-vpn-plugin.git
cd omarchy-vpn-plugin/packaging/arch
makepkg -si
```

Everything root runs is installed under `/usr` by pacman. Nothing runs from
your home folder.

### 2. Prepare the WireGuard connection

Configure the connection to use your VPN DNS for all domains. Replace
`wgclient` and `10.66.0.1` below with your connection name and VPN DNS address:

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
in Auto mode. Run it again after editing the file.

**Trusted networks.** On karchy, mark networks as trusted in Settings ›
Network; the VPN reads karchy's list (`karchy-trusted-networks status --json`),
which recognises a network by its router. On stock Omarchy, list trusted
connection UUIDs in `TRUSTED_UUIDS`:

```bash
nmcli -g connection.uuid connection show 'Home Wi-Fi'
```

**Encrypted DNS without karchy.** Untrusted networks use DNSCrypt-proxy on
`127.0.0.1`, set on their saved connections and restored when the package is
removed. To use the bundled Quad9 configuration:

```bash
sudo pacman -S dnscrypt-proxy
sudo install -m644 /usr/share/nulifyer-vpn/dnscrypt-proxy.toml /etc/dnscrypt-proxy/dnscrypt-proxy.toml
sudo systemctl enable --now dnscrypt-proxy
```

On karchy, karchy's own DNS setting covers untrusted networks and the
package leaves saved connections alone.

### 4. Add the bar widget (stock Omarchy)

```bash
omarchy plugin add https://github.com/Nulifyer/omarchy-vpn-plugin.git --enable
omarchy bar move nulifyer.vpn --after omarchy.network
```

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

## Upgrading from 1.x

1.x installed with `sudo python3 scripts/system.py install`. Remove that
installation first (the script now only does this), then install the package
and run `nulifyer-vpn setup` with your configuration (`STATUS_MAX_AGE` and
`TRUSTED_DNS` are no longer used and are ignored):

```bash
sudo python3 scripts/system.py uninstall
```

## Remove

```bash
sudo pacman -R nulifyer-vpn
omarchy plugin remove nulifyer.vpn
```

Removing the package takes the tunnel down, removes the kill switch, restores
the DNS settings it changed and keeps your WireGuard connection and keys.

## License

[MIT](LICENSE).
