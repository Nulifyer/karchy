---
name: karchy-vpn
description: Use for the karchy-vpn package on a karchy system, the WireGuard VPN with a kill switch. Covers Settings › Network › VPN and "Set up VPN", the commands karchy-vpn (status, mode off|auto|on, reconnect, portal-pause, setup) and karchy-network-vpn (import, setup, switch, home-lan), the files ~/.config/karchy-vpn/config, /etc/karchy-vpn/config and /run/karchy-vpn/status, trusted networks, VPN DNS, the nftables table inet karchy_vpn_guard, captive-portal sign-in with the VPN on, and a tunnel that will not connect or blocks the internet. Do not use for network faults with no VPN involved (karchy-troubleshoot) or for DNS, trust and firewall settings outside the VPN (karchy).
---

# karchy-vpn

karchy-vpn runs one NetworkManager WireGuard profile under a policy: it decides per network whether the tunnel is up, and an outgoing nftables block (the kill switch, also called the guard) stops other traffic while a required tunnel is down. The package supplies no VPN account or server.

Source of truth on the machine: `/usr/bin/karchy-vpn`, `/usr/lib/karchy-vpn/` (`control`, `policy`, `guard`, `configure`, `common.sh`) and `/usr/share/karchy-vpn/config.example`. Read them. Do not edit them.

## Change rules

- Switching the mode, reconnecting and a sign-in pause are small changes. Run them, then say what changed and how to undo it.
- Setting the VPN up, editing its configuration, changing a WireGuard profile, and any change to nftables or ufw are large changes under the `karchy` skill's change rules: plan, get the user's OK, take a snapshot, then apply.
- Never print or copy a WireGuard private key, a preshared key or a provider's `.conf` file. Do not run `wg showconf`, `nmcli --show-secrets` or `cat` on a profile under `/etc/NetworkManager/system-connections`. `wg show <interface> latest-handshakes` and `nmcli -g <field> connection show` on a named field are safe.
- Never remove the guard table by hand to "get the internet back". That sends traffic outside the tunnel. Use `karchy-vpn mode off` and tell the user that protection is off.

## Modes

| Mode | Behavior |
| --- | --- |
| `auto` | Tunnel up on untrusted networks. Direct connection on trusted networks. The default after setup. |
| `on` | Tunnel required on every network. On a trusted network, local devices stay reachable while `HOME_LAN` is `yes`. |
| `off` | No tunnel, no kill switch. |

```bash
karchy-vpn mode            # print the mode
karchy-vpn mode auto       # or off, on
karchy-vpn reconnect       # restart the tunnel, keep the mode
karchy-vpn portal-pause    # open a captive portal's sign-in for at most five minutes
```

These run `/usr/lib/karchy-vpn/control` through pkexec. The package's polkit rule allows exactly `mode off|auto|on`, `portal-pause` and `reconnect` without a password, for a local, active session of a `wheel` member. Over SSH they ask for a password. Everything else asks for an administrator's password. Do not add polkit rules.

The mode is saved in `/var/lib/karchy-vpn/mode`. Do not write that file. Use the command.

## Set up

Prefer the Settings page: `karchy-settings network vpn` opens Settings › Network › VPN. The user imports the provider's WireGuard file there and chooses "Set up VPN". The password prompt belongs to the user.

The same steps from a terminal:

1. `karchy-network-vpn import <file.conf>` adds the profile with autoconnect off and prints its UUID as JSON.
2. `karchy-network-vpn setup <uuid> [dns]` prepares the profile (fixed listen port, peer routes, the VPN's DNS for every name, no autoconnect), writes the configuration from it and passes it to `karchy-vpn setup`.
3. `karchy-vpn setup` has the root helper check the configuration, install it as `/etc/karchy-vpn/config`, and enable and start the units. It asks for an administrator's password.

`karchy-network-vpn setup` refuses a profile the package cannot use: more than one peer, not a full tunnel (`0.0.0.0/0`), or no IPv4 endpoint with a port. Exit 3 means the profile names no DNS server. Ask the user for the address of a DNS server inside the VPN and pass it as `[dns]`. That server must answer ping, because the ping is the tunnel's health probe.

To set up by hand, copy `/usr/share/karchy-vpn/config.example` to `~/.config/karchy-vpn/config`, edit it, and run `karchy-vpn setup`. The example explains each key. After any edit, run `karchy-vpn setup` again. The file in `~/.config` has no effect until then. Root's copy in `/etc/karchy-vpn/config` is the one in use, and only `karchy-vpn setup` writes it.

`karchy-network-vpn home-lan yes|no` changes `HOME_LAN` in root's copy through the same helper.

Without the karchy-vpn package, `karchy-network-vpn switch <uuid> on|off` connects or disconnects a NetworkManager VPN profile with no policy and no kill switch.

## Trusted networks and DNS

- The VPN reads trust from karchy. It has no list of its own. Trust is set in Settings › Network, or with `karchy-trusted-networks set <connection-uuid> <true|false>` while that network is connected. Query it with `karchy-trusted-networks status --json`. See the `karchy` skill.
- A trust change takes effect at once. No reconnect is needed.
- The VPN sets DNS only on its tunnel. While the tunnel is up, its DNS is the only one in use. On a trusted network in `on` mode with `HOME_LAN=yes`, the router answers for its own names such as `nas.lan` and the VPN answers the rest.
- DNS on networks without the tunnel belongs to `karchy-network-dns`, not to the VPN.
- Do not edit saved Wi-Fi or Ethernet profiles to fix VPN DNS. The package never writes them.

## Sign in to a café or hotel network

While the tunnel cannot connect, the kill switch also blocks the sign-in page. `karchy-vpn portal-pause` opens TCP 80 and 443 and the network's own DNS on that link for at most five minutes. The pause ends when NetworkManager reports full connectivity, or at the deadline. Then the kill switch closes and the tunnel connects. karchy's "Sign in to network" (`karchy-network-captive-portal <url>`) runs the pause itself.

## Diagnose

Start with `karchy-vpn status`. For the state table, what the kill switch lets through, the units and their journals, and the checks for a tunnel that does not connect, read [references/diagnosis.md](references/diagnosis.md).

## Remove

Quick install › karchy › WireGuard VPN › Remove, or `sudo pacman -R karchy-vpn`. Removal takes the tunnel down, deletes the guard table, restores DNS, and deletes `/etc/karchy-vpn` and the saved mode. It keeps the WireGuard profile, its keys and `~/.config/karchy-vpn/config`.
