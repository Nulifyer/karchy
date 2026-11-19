# Diagnose the VPN

Every command here only reads, except where a step says otherwise. Do not paste keys, endpoints, public IP addresses or network names into a bug report. See the `karchy-troubleshoot` skill for reporting.

## Read the state

```bash
karchy-vpn status           # one line: state (reason), mode, network
karchy-vpn status --json    # the status file
karchy-vpn-status --json    # the bar widget's view: adds tunnel address, handshake age, guard
```

`/run/karchy-vpn/status` is JSON. The policy replaces it on every change and never on a timer. "karchy-vpn is not running." means the file is missing: the VPN is not set up (`/etc/karchy-vpn/config` is missing), or the package was just removed.

| state | reason | Internet |
| --- | --- | --- |
| `off` | `mode` | direct |
| `standing-by` | `trusted`, `no-network` | direct, or none |
| `connecting` | `starting`, `no-handshake` | blocked |
| `protecting` | `tunnel-up` | through the tunnel |
| `failed` | `no-handshake`, `activation-failed` | blocked, retried every minute |
| `paused` | `sign-in`, with the deadline in `until` | web and DNS on that network only |

`network.trusted` and `network.trust` show how the policy classified the current network. `since` is the time of the last state change.

## Units and journals

All are system units and exist only to run while `/etc/karchy-vpn/config` exists.

| Unit | Job |
| --- | --- |
| `karchy-vpn-guard.service` | Closes the kill switch at boot, before NetworkManager, unless the mode is `off`. |
| `karchy-vpn-policy.path` | Starts the policy when `/run/karchy-vpn/pending` appears. |
| `karchy-vpn-policy.service` | One policy run after a network event, a command or a trust change. |
| `karchy-vpn-check.service` | Tunnel health check, started by a transient `karchy-vpn-check.timer`. |

```bash
journalctl -t karchy-vpn -b                     # the policy's own log lines
journalctl -b -u karchy-vpn-policy.service -u karchy-vpn-check.service -u karchy-vpn-guard.service
systemctl status karchy-vpn-policy.path karchy-vpn-guard.service
journalctl -b -u NetworkManager | grep -i wireguard
```

The check timer runs every 2 seconds while connecting, every 60 seconds while protecting and every 10 seconds after a failure. In `off` mode and while standing by, nothing runs. That is expected.

## The kill switch

The kill switch is the nftables table `inet karchy_vpn_guard`. It filters outgoing traffic only and never touches ufw's chains. `/run/karchy-vpn/guard-mode` holds its mode: `closed`, `ready` (closed plus everything through the tunnel) or `portal`.

```bash
sudo nft list table inet karchy_vpn_guard
```

While closed it lets out only loopback, DHCP, IPv6 neighbour discovery, NTP, the WireGuard endpoint, encrypted DNS (TCP 853) to karchy's configured servers, a ping to the router and the tunnel's health probe. Everything else hits a `counter drop` rule, so the counter shows whether traffic is blocked there. No table means the guard is off.

Incoming rules belong to ufw. A blocked incoming connection is not the kill switch.

## The tunnel does not connect

Work down the list. Stop at the first failed check.

1. `karchy-vpn status`. If the state is `standing-by (trusted)`, the mode is `auto` and the network is trusted. That is the design, not a fault.
2. The underlying link: `karchy-network-status --verbose`. No network means no tunnel.
3. A captive portal: `nmcli networking connectivity` prints `portal`. Use `karchy-vpn portal-pause` or "Sign in to network".
4. The profile exists and matches the configuration: `VPN_CONNECTION` and `VPN_INTERFACE` in `/etc/karchy-vpn/config` (readable without root) against `nmcli -f NAME,TYPE,DEVICE connection show`. A renamed or deleted profile gives `activation-failed`.
5. The handshake: `sudo wg show <interface> latest-handshakes`. `0` means the server never answered. Causes: wrong endpoint or port, the network blocks UDP to that port, the endpoint's host name does not resolve, or the server rejects the key.
6. The health probe: the state stays `connecting` or turns `failed` with a recent handshake when `VPN_DNS` does not answer ping through the tunnel.
7. Home network with the VPN server behind the same router: replies come from the router's own address. Set `TRUSTED_GATEWAY` in the configuration, then run `karchy-vpn setup`. This is a configuration change: follow the change rules.

`karchy-vpn reconnect` restarts the tunnel and keeps the mode. Try it once after fixing a cause, not as the first step.

## The internet is blocked

- State `connecting` or `failed`: the kill switch is working as designed. Fix the tunnel, or ask the user whether to run `karchy-vpn mode off`. Say that `off` removes the protection.
- State `protecting` but names do not resolve: check `resolvectl status <interface>` for the VPN's DNS and that `VPN_DNS` answers `ping`.
- State `off` or `standing-by` and still blocked: the VPN is not the cause. Confirm that `sudo nft list table inet karchy_vpn_guard` reports no such table, then use the `karchy-troubleshoot` skill.
- A local device (NAS, printer) is unreachable in `on` mode on the home network: the network must be trusted and `HOME_LAN` must be `yes` (`karchy-network-vpn status` prints `home_lan`).

## After a package update

`pacman` restarts `karchy-vpn-policy.path` and asks the policy to look again. No manual step is needed. If the status file is stale after an update, `karchy-vpn reconnect`.
