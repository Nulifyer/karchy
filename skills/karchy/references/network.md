# Network, trusted networks, DNS and sharing

Read this before you change a network setting, the trusted-network list, DNS, the firewall, or local sharing. Each command's header comment in `/usr/share/karchy/bin` holds the detail.

## Who owns what

Each job has one owner. Change a setting through its owner, not around it.

| Job | Owner | How to change it |
| --- | --- | --- |
| Connections and saved networks | NetworkManager | `karchy-network-profile`, `nmcli` |
| Name resolution | systemd-resolved | Do not edit `/etc/resolv.conf` |
| Upstream DNS servers | karchy | `karchy-network-dns set` |
| Which networks are trusted | karchy | `karchy-trusted-networks set` |
| `.local` names and announcements | avahi, switched by karchy | Follows trust. No setting |
| Incoming firewall rules | ufw | `sudo ufw ...` for the user's own rules |
| VPN tunnel, its DNS and kill switch | the `karchy-vpn` package, when installed | The `karchy-vpn` skill |

## Reading the state

All of these need no password. Prefer them to parsing files.

- `karchy-network-status --json` describes the real link (Wi-Fi or Ethernet), never a VPN tunnel. A VPN is a separate block.
- `karchy-trusted-networks status --json` lists active connections with `trusted` and a `reason`.
- `karchy-network-dns status` shows the DNS settings and each device's state.
- `karchy-localsend-firewall status` shows whether ufw is on and where karchy opened sharing ports.
- `karchy-network-privacy status` prints `announcing` or `quiet`.
- `karchy-network-profile list --json` lists saved Wi-Fi and Ethernet networks.
- `karchy-network-country status` shows the Wi-Fi country.

`karchy settings network` opens Settings at the Network page.

## Trusted networks

Trust decides three things at once: sharing ports, DNS, and the VPN's Auto mode.

- Mark a network with `karchy-trusted-networks set <connection-uuid> <true|false>`. It asks for a password through polkit. The network must be connected, because trust records the router's MAC address and, for Wi-Fi, the name and security.
- Never edit `/etc/karchy/trusted-networks`. The command is its only writer.
- Trust is a security decision. Trust a network only when the user names it. Do not trust a network to make something work.
- If `reason` is `different router`, `router unknown` or `needs re-trust`, the network is not trusted even though a record exists. Report the reason. Trust it again only if the user confirms that the network is theirs.

## DNS

On a network that is not trusted, karchy applies its own DNS to the live connection. The default is Quad9 over TLS. A trusted network keeps the router's DNS, so names like `nas.lan` work.

- Change settings with `karchy-network-dns set key=value...`. It asks for a password through polkit and writes `/etc/karchy/dns`. Do not write that file by hand.
- Keys: `provider=quad9|cloudflare|custom|network`, `servers=` (custom only), `encrypted=yes|no`, `trusted=yes|no`, `fallback=yes|no`.
- `fallback=no` means "encrypted only". On a network that blocks DNS over TLS, or behind a sign-in page, name lookups then fail. Warn the user before you set it.
- Do not set DNS on a saved profile with `nmcli connection modify`, with `resolvectl`, or globally. karchy changes only the applied connection. A global setting overrides a VPN's DNS.
- Device states in `status`: `applied`, `network`, `waiting`, `portal`, `fallback`, `blocked`. `fallback` means the encrypted servers did not answer and the network's DNS is in use until the next connect.
- Log: `journalctl -t karchy-network-dns`.

## Sharing and the firewall

- ufw is on and denies incoming connections.
- karchy opens LocalSend's port (53317), and KDE Connect's ports (1714 to 1764) while KDE Connect is installed, only on the devices of trusted connections. `karchy-localsend-firewall` does this as root from NetworkManager's dispatcher. Do not run it by hand and do not remove its ufw rules.
- avahi runs only while a trusted network is connected and is masked otherwise. If `.local` names or printers do not resolve, check trust first. Do not unmask or enable avahi by hand.
- To open a port for the user's own service, plan it with the user and add the user's own rule with `sudo ufw allow ...`. Prefer a rule limited to an interface or source network. Say how to remove it (`sudo ufw delete allow ...`).

## Saved networks and Wi-Fi

- `karchy-network-profile set <uuid> <setting> <value...>` changes a saved network without a password: `autoconnect`, `metered`, `band`, `private-address`, `ip auto`, `ip manual <address/prefix> <gateway> [dns...]`. Exit 2 means the value was refused and nothing changed.
- A change to IP settings or the private address reconnects a network in use. Tell the user first when they work over that connection.
- `karchy-network-profile forget <uuid>` deletes a saved network and its password.
- `karchy-network-profile join-hidden <ssid> open|wpa` reads the password from stdin. Never put a Wi-Fi password on a command line.
- `karchy network band [auto|2.4|5|6]` pins the Wi-Fi band for the active connection.
- `karchy-network-country set <XX|auto>` sets the Wi-Fi country. It asks for a password through polkit. Without a country, 6 GHz stays off.
- `karchy-restart-wifi` unblocks and restarts Wi-Fi.
- `karchy airplane on|off|toggle|status` controls every radio. No password.
- `karchy-network-password <interface>` prints the active Wi-Fi password. Do not run it unless the user asks for the password, and do not repeat the output elsewhere.

## Sign-in pages

karchy detects a captive portal and opens a sign-in window (`karchy-network-captive-portal <url>`). While a portal waits, the connection uses the network's DNS. This is expected. Do not change DNS settings to "fix" it.

## VPN

Without the `karchy-vpn` package, `karchy-network-vpn switch <uuid> on|off` connects a NetworkManager VPN or WireGuard profile, and `karchy-network-vpn import <file.conf>` adds a WireGuard profile. With `karchy-vpn` installed (`pacman -Q karchy-vpn`), use the `karchy-vpn` skill. The VPN and the firewall are system-level changes: plan them with the user.
