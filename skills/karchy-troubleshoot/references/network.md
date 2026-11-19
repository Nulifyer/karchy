# Network diagnosis

One owner per job on karchy: NetworkManager connects, systemd-resolved resolves, avahi answers `.local`, ufw owns incoming rules, karchy owns the trusted-network list and upstream DNS, and karchy-vpn (when installed) owns its tunnel and its outgoing block. Find which owner fails before changing anything.

## Read the state

```bash
karchy-network-status --verbose      # the real link (never a VPN tunnel), plus a separate VPN block
karchy-network-status --json         # the same for Settings: addresses, gateway, DNS in use, link
nmcli general status
nmcli networking connectivity        # full, limited, portal or none
nmcli device status
karchy-network-dns status            # karchy's DNS settings and the state per device
karchy-trusted-networks status --json
resolvectl status
rfkill list
```

## Work down the layers

1. Radio. `rfkill list` shows a block. Airplane mode is `karchy-airplane on|off|toggle`. `karchy-restart-wifi` unblocks and restarts Wi-Fi.
2. Link. `nmcli device status` shows `connected`. For Wi-Fi faults read `journalctl -b -u NetworkManager` and `journalctl -k -b | grep -i -E 'iwl|ath|mt7|rtw|brcm|wlan'`.
3. Address and gateway. `karchy-network-status --verbose` lists them. Ping the gateway.
4. Internet without names: `ping -c 3 1.1.1.1`.
5. Names: `resolvectl query archlinux.org`.
6. A sign-in page: `nmcli networking connectivity` prints `portal`.
7. A VPN: if `karchy-vpn` is installed, `karchy-vpn status`. States `connecting`, `failed` and `paused` block ordinary traffic on purpose. Use the `karchy-vpn` skill.

## DNS

On a network that is not trusted, karchy puts its own DNS on the live connection: Quad9 over TLS unless `/etc/karchy/dns` says otherwise. A trusted network keeps the router's DNS, so names such as `nas.lan` work there. Saved profiles are never changed.

`karchy-network-dns status` gives one state per device:

| State | Meaning |
| --- | --- |
| `applied` | karchy's DNS is in use. |
| `network` | The network's own DNS is in use: the network is trusted, or the provider is `network`. |
| `waiting` | NetworkManager has given no connectivity verdict yet. |
| `portal` | A sign-in page is pending, so the network's DNS is in use. |
| `fallback` | The encrypted servers did not answer here. The network's DNS stays until the connection next comes up. |
| `blocked` | "Encrypted only" is set (`fallback=no`) and the servers do not answer on this network. No name lookups work. |

`journalctl -t karchy-network-dns` records each decision. A local name that fails on the home network usually means the network is not trusted, or the reason in `karchy-trusted-networks status --json` is `different router`, `router unknown` or `needs re-trust`.

Changing DNS settings (`karchy-network-dns set key=value...`) or trust (`karchy-trusted-networks set <uuid> <true|false>`) asks for a password and is a change. Follow the `karchy` skill.

## Sign-in pages

The network panel's "Sign in to network" runs `karchy-network-captive-portal <url>`, which opens the page in a floating window and closes it once the internet is reachable. With karchy-vpn connecting, failed or paused, it also runs the VPN's sign-in pause. If the page does not load under `fallback=no`, the network's DNS is blocked by the user's own "encrypted only" choice.

## Incoming connections and local discovery

- ufw denies incoming connections by default. `sudo ufw status verbose` lists the rules.
- karchy writes one kind of rule: LocalSend's port 53317, and KDE Connect's 1714 to 1764 while it is installed, open only while a trusted network is connected. `karchy-localsend-firewall status` shows the state. If LocalSend cannot find devices, check trust first.
- avahi (`.local` names and discovery) runs only on trusted networks. `karchy-network-privacy status` shows it.
- Opening a port is a firewall change: a large change under the `karchy` skill.

## Speed and Wi-Fi quality

```bash
karchy-network-speedtest down     # or up
nmcli -f IN-USE,SSID,CHAN,RATE,SIGNAL,SECURITY device wifi list
iw dev                            # then: iw dev <interface> link
karchy-network-country status     # the Wi-Fi regulatory domain
```

A wrong Wi-Fi country limits channels and power. `karchy-network-country set <XX|auto>` changes it and asks for a password. `journalctl -t karchy-wifi-regdomain` shows what was applied.

## Saved networks

`karchy-network-profile list` prints the saved Wi-Fi and Ethernet profiles. `set` and `forget` change them. Forgetting a network also loses its password, so ask first.

## Private data

SSIDs, MAC addresses, IP addresses, the router's address and saved network names all appear in this output. Keep them out of bug reports. See [reporting.md](reporting.md).
