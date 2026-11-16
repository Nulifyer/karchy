# Docs audit: networking, sound, Bluetooth and desktop services

Date: 2026-11-16. Scope: NetworkManager, systemd-resolved and karchy's DNS policy, mDNS, ufw and LocalSend, Wi-Fi regulatory domain, network sysctls, PipeWire/WirePlumber, BlueZ, portals, polkit agent, keyring and PAM, greetd auto-login, time sync, printing, udisks2/gvfs, SMB kept mounts.

Method: I read karchy's files and compared them with the Arch Wiki (raw pages fetched 2026-11-16 with `index.php?title=PAGE&action=raw`), the man pages installed on this host (NetworkManager 1.58.1, systemd 262.2, BlueZ 5.88, avahi 0.9rc5, ufw 0.36.2, all from Arch or CachyOS), package metadata (`pacman -Si`, `pacman -Ql`, the archlinux.org file lists) and upstream sources on GitHub. Nothing on the host or in a VM was changed.

Severity scale: **breaks-boot/data-loss**, **broken-feature**, **suboptimal**, **cosmetic**.

Two facts about package sources affect everything below:
- The generic `[cachyos]` repository karchy uses overrides only `linux-firmware` among these packages (`pacman -Sl cachyos`). The network, audio and Bluetooth stack therefore comes from Arch's builds.
- CachyOS's `linux-firmware` depends on `linux-firmware-mediatek`, which holds the Framework 13 AMD's MT7922/MT7925 firmware.

---

## Findings, most severe first

### 1. A restored home folder can't open its keyring (decision risk: D-57 combined with D-25 and D-35)

- **Severity:** data-loss (conditional). This is a decision risk, raised separately as the brief asks.
- **What karchy does:** `system/keyring/keyring-key:22-31` writes a random key once per user to `/etc/credstore/karchy.keyring.<uid>`, and `install/base.sh:143` creates it at install time. The oo7 login keyring in `~/.local/share/keyrings` is encrypted with that key.
- **What the docs say:**
  - D-57 itself: "the keyring is protected at rest by LUKS and the root-only key … a copy of the home folder alone (a backup) still can't be opened".
  - D-25: "Moving to real hardware is a fresh install followed by a data restore".
  - D-35 plans a home backup to the NAS.
  - A fresh install generates a new key (`keyring-key:24`, `[[ -s $key ]] && exit 0` is checked only on the new disk).
- **The risk:** restoring `$HOME` onto a reinstall, or a new laptop, leaves the keyring unopenable. That loses Brave's "Safe Storage" key, and with it Brave's saved passwords and cookies, which `--password-store=gnome-libsecret` keeps there. It also loses every libsecret password. Nothing in `docs/` or `.agents/` mentions backing up `/etc/credstore`; I searched for "credstore", "keyring backup" and "keyring restore".
- **Fix:** make `/etc/credstore/karchy.keyring.<uid>` part of the D-35 backup, as a root-only file. Add an installer or `karchy-keyring-key import` path that places an existing key before the first login. Until then, document "export or copy the key before reinstalling". For this week's move from the VM: nothing in the VM keyring is worth keeping, so the move is safe, but the first real-hardware restore after it is not.
- **Check:** VM. Install, store a secret, back up home, reinstall, restore home, then `oo7-cli` or `secret-tool lookup`.

### 2. "Keep this mount" fails for NAS names that only NetBIOS or LLMNR resolve, and blames the password

- **Severity:** broken-feature, for that case.
- **What karchy does:**
  - `bin/karchy-mount-keep:99-110` takes the server name from gvfs (`smb-share:server=NAS,…`) or from `smb://NAS/share`.
  - It probes with `mount -t cifs //NAS/share` (`:231`) and writes `//NAS/share … cifs …` to fstab (`:199`).
  - On failure it says "the username or password is wrong, the share's name is, or the server is away" (`:179`).
  - `system/systemd/resolved.conf.d/10-karchy-multicast.conf:7` turns LLMNR off.
- **What the docs say:**
  - Arch Wiki [Samba#NetBIOS/WINS host names](https://wiki.archlinux.org/title/Samba#NetBIOS/WINS_host_names): "Samba clients handle NetBIOS host names automatically by default … Other programs (including mount.cifs) typically use Name Service Switch, which does not handle NetBIOS by default."
  - resolved.conf(5), `ResolveUnicastSingleLabel=`: "When false (the default), systemd-resolved will not resolve A and AAAA queries for single-label names over classic DNS. Note that such names may still be resolved if search domains are specified …, or using other mechanisms, in particular via LLMNR".
  - The result: gvfs (libsmbclient) opens `smb://NAS/`, but `mount.cifs` can't resolve `NAS` unless the router hands out a search domain. On untrusted networks `ignore-auto-dns` drops search domains too (nm-settings-nmcli(5), `ipv4.ignore-auto-dns`). The user then retypes the password in a loop.
- **Fix:**
  - Before the probe, run `getent hosts "$server"`.
  - If that fails, try `$server.local` (avahi answers it) and offer to use it.
  - Otherwise say "this computer can't find the server by the name NAS; use its .local name or IP address".
  - Write the resolvable name into fstab.
- **Check:** needs a real LAN with a NAS or Windows share. The VM's user network has no NetBIOS or multicast peers.

### 3. ufw makes reverse-path filtering strict, overriding systemd's loose default

- **Severity:** suboptimal. The impact is unverified because NetworkManager mitigates some cases.
- **What karchy does:** it enables ufw (`install/setup.sh:74`, the `ufw.service` enable at `:80`) and ships no rp_filter setting.
  - Arch's unmodified `/etc/ufw/sysctl.conf` (backup file of the ufw package) sets `net/ipv4/conf/all/rp_filter=1` and `default/rp_filter=1`.
  - `/etc/default/ufw` points `IPT_SYSCTL` at it.
  - `ufw.service` runs `After=systemd-sysctl.service`, so it overrides systemd's `/usr/lib/sysctl.d/50-default.conf` (`net.ipv4.conf.*.rp_filter = 2`).
  - On this host, `/proc/sys/net/ipv4/conf/all/rp_filter` is `1`.
- **What the docs say:**
  - Kernel ip-sysctl ([docs.kernel.org/networking/ip-sysctl.html](https://docs.kernel.org/networking/ip-sysctl.html), rp_filter): "The max value from conf/{all,interface}/rp_filter is used". So `all=1` makes every interface strict.
  - NetworkManager.conf(5), CONNECTIVITY SECTION: "your distribution might set /proc/sys/net/ipv4/conf/*/rp_filter to strict filtering. That works badly with per-device connectivity checking … A strict rp_filter setting will reject any response and the connectivity check on all but the best route will fail."
  - Mitigation: NetworkManager loosens rp_filter itself on links whose route also exists on another link ([commit cae3cef60f](https://git.uninsane.org/colin/NetworkManager/commit/cae3cef60fe6b37929e69d103663882274ad46bc)). Newer versions mark incoming WireGuard packets so they pass the check ([RHEL-85763](https://issues.redhat.com/browse/RHEL-85763)). Which release has which change is unverified.
- **Why karchy cares:** `karchy-network-dns` waits for each device's own connectivity verdict (`bin/karchy-network-dns:154-169, 220-227`). Docked with Wi-Fi and Ethernet both up, the non-best device could stay "waiting" on the network's unencrypted DNS. The nulifyer-vpn guard and its hairpin rewrite also depend on reverse-path behaviour.
- **Fix:** drop the two rp_filter lines from `/etc/ufw/sysctl.conf` in `setup_system_files`. The file is a backup file, so pacman keeps the edit, the same way the `ufw.conf` edit is kept. Alternatively, point `IPT_SYSCTL` at a karchy copy without them. systemd's loose `2` then applies.
- **Check:**
  - VM: `sysctl net.ipv4.conf.all.rp_filter` confirms the override.
  - Real hardware (dock plus Wi-Fi, VPN On): `nmcli -f GENERAL.IP4-CONNECTIVITY device show wlan0` and `karchy-network-dns status`.

### 4. PipeWire runs without realtime priority (no rtkit)

- **Severity:** suboptimal.
- **What karchy does:** `packaging/pkgbuilds/karchy/PKGBUILD:22` and `karchy-desktop/PKGBUILD:17` install pipewire, pipewire-pulse, wireplumber, pipewire-alsa and pipewire-jack. Nothing in the repository names `rtkit` or `realtime-privileges` (grep). Whether something else pulls rtkit in is unverified.
- **What the docs say:**
  - `pacman -Si pipewire`, Optional Deps: "rtkit: realtime privileges with rtkit module" and "realtime-privileges: realtime privileges with rt module".
  - [docs.pipewire.org module-rt](https://docs.pipewire.org/page_module_rt.html): realtime "requires RLIMIT_RTPRIO to be set …"; otherwise it will "fall back to using the Portal Realtime DBus API or RTKit".
  - `/usr/share/pipewire/pipewire.conf:112-125` asks for `rt.prio = 88`, `nice.level = -11`, with `rtportal.enabled = false`.
  - Arch users get `RLIMIT_RTPRIO` 0, so without rtkit PipeWire runs at normal priority. Under load (games on the RTX 5080, builds) that is where crackles and xruns come from.
- **Fix:** add `rtkit` to `karchy-desktop` depends. It is D-Bus activated, so nothing needs enabling.
- **Check:**
  - VM: `pacman -Q rtkit`, and `journalctl --user -u pipewire | grep -i rt`.
  - Real hardware: audio under CPU load.

### 5. The machine still announces its name on public Wi-Fi, though the resolved drop-in says it stops

- **Severity:** suboptimal (privacy). Part of it is cosmetic: the comment.
- **What karchy does:** `system/systemd/resolved.conf.d/10-karchy-multicast.conf:1-4` turns resolved's mDNS and LLMNR off so the machine no longer "answers name lookups on public Wi-Fi". avahi stays enabled on every interface (`install/setup.sh:80`), and NetworkManager's DHCP hostname default is unchanged.
- **What the docs say:**
  - avahi-daemon.conf(5): "publish-addresses= … avahi-daemon will register mDNS address records for all local IP addresses … Defaults to "yes"." The host's `/etc/avahi/avahi-daemon.conf` leaves it at the default.
  - Arch Wiki [NetworkManager#Turn off hostname sending](https://wiki.archlinux.org/title/NetworkManager#Turn_off_hostname_sending): "NetworkManager by default sends the hostname to the DHCP server."
  - So `<hostname>.local` is still announced and answered by avahi on café networks, and the hostname goes to every DHCP server. Turning off LLMNR does stop LLMNR answers, as intended.
- **Fix:**
  - At minimum, correct the comment.
  - If the goal matters, set `ipv4.dhcp-send-hostname=0` and `ipv6.dhcp-send-hostname=0` in a `/usr/lib/NetworkManager/conf.d` drop-in. This costs the router's name for the laptop on home networks; trusted profiles can opt back in.
  - Consider `publish-addresses` handling for avahi. avahi has no per-interface runtime switch, so restricting it would need a dispatcher that restarts avahi with `deny-interfaces`. Weigh that against NAS and printer discovery.
- **Check:** real network, with `avahi-browse -art` and `avahi-resolve -n host.local` from another machine on an untrusted network.

### 6. MTU probing without the recommended floor

- **Severity:** suboptimal.
- **What karchy does:** `system/sysctl.d/60-karchy-network.conf:16` sets `net.ipv4.tcp_mtu_probing = 1` and leaves `tcp_mtu_probe_floor` at the kernel default, 48 (host `/proc`).
- **What the docs say:**
  - Arch Wiki [Sysctl#Enable MTU probing](https://wiki.archlinux.org/title/Sysctl#Enable_MTU_probing): "On lossy connections, MTU probing can underestimate the actual MTU, and can sometimes lower the value to the MSS minimum (48 bytes in IPv4). To avoid excessive MSS decreases, it is recommended to increase the minimum MTU probing MSS. `net.ipv4.tcp_mtu_probe_floor = 1024`".
  - Kernel ip-sysctl: tcp_mtu_probe_floor "caps the minimum MSS used for search_low … Default: 48".
- **Fix:** add `net.ipv4.tcp_mtu_probe_floor = 1024` beside it. Lossy Wi-Fi is exactly where probing kicks in.
- **Check:** VM, `sysctl net.ipv4.tcp_mtu_probe_floor`.

### 7. IPv6 temporary (privacy) addresses are off

- **Severity:** suboptimal.
- **What karchy does:** it has no `ipv6.ip6-privacy` setting (grep). NetworkManager falls back to `/proc/sys/net/ipv6/conf/default/use_tempaddr`, which is `0` on Arch's kernel (host).
- **What the docs say:**
  - nm-settings-nmcli(5), `ipv6.ip6-privacy`: "-1 (default) means fallback to global configuration … fallback to read /proc/sys/net/ipv6/conf/default/use_tempaddr".
  - Arch Wiki [IPv6#NetworkManager](https://wiki.archlinux.org/title/IPv6#NetworkManager) recommends `[connection] ipv6.ip6-privacy=2`.
  - Stable-privacy interface IDs are already NetworkManager's default (same page: "NetworkManager uses stable private addresses by default"). So the address isn't derived from the MAC, but it stays the same on a given network.
- **Fix:** add `[connection]` `ipv6.ip6-privacy=2` to a `/usr/lib/NetworkManager/conf.d/` drop-in, in line with D-68's privacy goals. Optional.
- **Check:** VM, with an IPv6 RA network (`ip -6 addr` shows `temporary`).

### 8. USB driverless printers and scanners need ipp-usb

- **Severity:** suboptimal (Optional feature).
- **What karchy does:** `bin/karchy-feature-printing:16` installs `cups cups-browsed cups-filters system-config-printer sane sane-airscan simple-scan`.
- **What the docs say:** Arch Wiki [SANE](https://wiki.archlinux.org/title/SANE): "Install the sane-airscan package if the scanner is known to work in "driverless" mode. If your scanner is using USB, also install ipp-usb and reboot." The CUPS page also flags ipp-usb as missing from it ([CUPS#Installation](https://wiki.archlinux.org/title/CUPS), Expansion note).
- **Fix:** add `ipp-usb` to `PACKAGES` (its udev rule starts it on demand).
- **Check:** real hardware (a USB multifunction printer). The owner has none (D-38), so this is low priority.

### 9. Older headsets' battery level isn't reported

- **Severity:** suboptimal.
- **What karchy does:** it ships no `/etc/bluetooth/main.conf` changes, so `Experimental` stays at `false` (host `main.conf:127`). The Bluetooth panel shows battery when BlueZ offers it (`shell/plugins/panels/bluetooth/Panel.qml:845`).
- **What the docs say:** Arch Wiki [Bluetooth#Enabling experimental features](https://wiki.archlinux.org/title/Bluetooth#Enabling_experimental_features): "enabling D-Bus experimental interfaces currently allows to report battery level for old headsets".
- **Fix:** optional. A drop-in such as `/usr/lib/systemd/system/bluetooth.service.d/` with `--experimental`, or leave it. Modern devices report battery through GATT without it.
- **Check:** real hardware with the owner's headset.

### 10. The Wi-Fi country script ignores Arch's documented setting

- **Severity:** cosmetic.
- **What karchy does:** `system/wifi/wifi-regdomain:29-46` reads only `/etc/karchy/wifi-country`, then the timezone. It runs on every `ieee80211` add (`85-karchy-wifi-regdomain.rules`), after Arch's `85-regulatory.rules`, which applies `/etc/conf.d/wireless-regdom` when cfg80211 loads.
- **What the docs say:** Arch Wiki [Network configuration/Wireless#Respecting the regulatory domain](https://wiki.archlinux.org/title/Network_configuration/Wireless#Respecting_the_regulatory_domain): "To configure the regdomain, install wireless-regdb, then edit /etc/conf.d/wireless-regdom and uncomment the appropriate domain". Someone following the wiki gets their choice overwritten by the timezone guess.
- **Fix:** if `WIRELESS_REGDOM` is set in `/etc/conf.d/wireless-regdom` and no karchy override exists, use it, or have `karchy-network-country status` report it.
- **Check:** VM (the script logic). The effect on channels needs real Wi-Fi.

### 11. The kept-mount marker is a trailing comment on the fstab line

- **Severity:** cosmetic (works today).
- **What karchy does:** `bin/karchy-mount-keep:199` appends `# karchy-kept-mount` after the passno field.
- **What the docs say:**
  - fstab(5): "Lines starting with '#' are comments." Trailing comments aren't documented.
  - libmount's parser stops after field 6 and ignores the rest ([util-linux libmount/src/tab_parse.c](https://github.com/util-linux/util-linux/blob/master/libmount/src/tab_parse.c), `mnt_parse_table_line`), so systemd's generator accepts the line.
  - fstab(5) offers a documented marker: "comment or x-<name> for use by fstab-maintaining programs".
- **Fix:** put `x-karchy-kept` in the options field and match on that. Keep reading the old marker for existing lines.
- **Check:** VM.

### 12. Lockout length differs between the lock screen and sudo

- **Severity:** cosmetic.
- **What karchy does:** `system/pam.d/karchy-lock-password:4,7` passes `deny=10 unlock_time=120`. `install/setup.sh:71` sets `deny = 10` in `/etc/security/faillock.conf` but leaves `unlock_time` at its default.
- **What the docs say:** faillock.conf(5): "unlock_time=n … The default is 600 (10 minutes)." The tally is shared, so ten failures lock the lock screen for 2 minutes and sudo or polkit for 10.
- **Fix:** also set `unlock_time = 120` in faillock.conf from `setup_system_files`, or drop the module arguments so every stack reads faillock.conf.
- **Check:** VM.

---

## Hardware notes from the docs (not karchy bugs; check on the machines)

- **Framework 13 AMD Wi-Fi (MT7922, the 7040 series):**
  - "You will be limited to 802.11n (Wi-Fi 4) and 2.4GHz bands if you do not configure the regulatory domain" ([Framework Laptop 13 (AMD Ryzen 7040 Series)#Wi-Fi](https://wiki.archlinux.org/title/Framework_Laptop_13_(AMD_Ryzen_7040_Series))). karchy's timezone script covers this; check `iw reg get` after first boot.
  - The same page reports better stability with iwd. karchy uses wpa_supplicant by D-15. Keep that unless the link is flaky.
  - For latency spikes, the wiki's fix is `options mt7921e disable_aspm=1` ([Network configuration/Wireless#mt7921 / mt7922](https://wiki.archlinux.org/title/Network_configuration/Wireless#mt7921_/_mt7922)).
  - In the US regdb, 6 GHz stays no-IR on MediaTek cards whatever the country ([MT7922 6GHz article](https://www.michaelstinkerings.org/the-mt7922-6ghz-debacle-why-linux-users-cant-use-wifi-6e-and-how-i-fixed-it/), linked from the wiki).
- **Framework 13 AMD sleep:** "the framework has a chance of rebooting instead of waking up. The wifi module Mediatek MT7921 seems to cause this", and the wiki gives an `rfkill block all` sleep unit. Watch for this with D-32's suspend-then-hibernate.
- **Framework 13 AI 300 (MT7925):** "network speeds over Wi-Fi are very limited" ([Framework Laptop 13#Wi-Fi performance on AMD edition](https://wiki.archlinux.org/title/Framework_Laptop_13)).
- **Framework 13 headphone jack:** the buzz or pop when audio power save toggles is fixed by `snd_hda_intel power_save=0` (same page, "Headset jack").
- **Intel laptops:** `sof-firmware` is usually required ([ALSA#Firmware](https://wiki.archlinux.org/title/Advanced_Linux_Sound_Architecture#Firmware)). It is already recorded as not needed for karchy's targets (`.agents/research/audit-usage.md:99`). Neither of the owner's machines is Intel.

## Could not verify from documentation (check on hardware or in the VM)

- That NetworkManager keeps `nmcli device modify` DNS through DHCP renewals. nmcli(1) says only "temporary changes … not preserved in the connection profile". The architecture doc cites a VM check, and `karchy-network-dns` re-applies on `dhcp4-change` anyway (`:213-219`).
- The `dns+tls://ADDRESS#NAME` form. nm-settings-nmcli(5) renders it as `dns+tls://ADDRESS[:PORT][SERVERNAME]`, without the `#`. The NetworkManager wiki uses `ip#name` (plain form). Confirm with `resolvectl dns`/`status` on hardware that the server name is passed.
- Thunar's Network browsing (NetBIOS or WS-Discovery replies) behind ufw's deny-incoming. Typing `smb://` works regardless (D-76).
- `nss-mdns` with resolved: the Avahi wiki says it works only if `host -t SOA local` returns NXDOMAIN, and calls resolved's old answer a bug of "older versions". Check `getent hosts <nas>.local` on the real LAN.
- Encrypted-only DNS (`fallback=no`) with a badly wrong clock. resolved.conf(5) says DNSOverTLS "requires a DNS server that … has a valid certificate"; whether timesyncd then can't resolve its pool names is inferred, not documented.
- The Secret portal for Flatpak apps. hyprland-portals.conf lists `default=hyprland;gtk`, not oo7-portal. No Flatpak in base, so this is untested and not needed.

---

## Checked and found correct

1. **Wi-Fi backend.** It is wpa_supplicant: NetworkManager.conf(5) "If unspecified, the default is "wpa_supplicant"", and Arch's networkmanager depends on wpa_supplicant (`pacman -Si`).
2. **resolved selection.** `/etc/resolv.conf` → stub (`install/base.sh:236`) makes NetworkManager pick systemd-resolved automatically (NetworkManager.conf(5) `dns`; wiki NetworkManager#systemd-resolved).
3. **resolv.conf link timing.** It is created outside arch-chroot, after the chroot bind mount (`install/base.sh:234-237`).
4. **Dispatcher enablement.** `systemctl enable NetworkManager.service` also enables the dispatcher alias (`Also=NetworkManager-dispatcher.service` in the unit). That satisfies the wiki's "enable NetworkManager-dispatcher.service".
5. **Dispatcher location.** Scripts in `/usr/lib/NetworkManager/dispatcher.d`, root-owned 0755, are run by NetworkManager-dispatcher(8) ("/{etc,usr/lib}/NetworkManager/dispatcher.d … owned by root … not writable by group or other").
6. **Dispatcher actions.** The names used (up, down, dhcp4-change, dhcp6-change, connectivity-change, vpn-up/down, reapply) match NetworkManager-dispatcher(8). Long work is handed to `systemd-run`, as the man page advises ("spawn a child process and have the parent return immediately").
7. **Wi-Fi power save.** `[connection] wifi.powersave = 2` is "disable" (nm-settings-nmcli(5)), and `/usr/lib/NetworkManager/conf.d` is read (NetworkManager.conf(5)). NetworkManager's own default is "ignore". The Framework wiki recommends power save off for the MT7921/MT7922.
8. **MAC randomization.** Scans are randomized by default (`wifi.scan-rand-mac-address` "defaults to yes"). Connections keep the real MAC ("defaults to preserve"), with an opt-in per-profile `stable` mode (`bin/karchy-network-profile:153-161`), which the wiki's MAC address spoofing#NetworkManager describes. Default off is deliberate (network-design §4.3).
9. **DNS over TLS.** `connection.dns-over-tls yes` is strict "use DNSOverTls and disabled fallback". The per-link setting wins over the global one (resolved.conf(5) DNSOverTLS), and `address#name` validates the certificate and sets SNI.
10. **DNS server addresses.** The Quad9 and Cloudflare addresses and TLS names in `bin/karchy-network-dns:78-79` match the systemd 262 compiled `FallbackDNS` list in `/etc/systemd/resolved.conf`.
11. **Per-link DNS.** Using per-link servers rather than NetworkManager's global DNS agrees with the wiki's warning that global `servers=` "do not get sent to systemd-resolved" (NetworkManager#Setting custom global DNS servers).
12. **resolved drop-in path.** `/usr/lib/systemd/resolved.conf.d/` is a valid drop-in path (resolved.conf(5)), and `/etc` overrides it.
13. **LLMNR and mDNS off.** `LLMNR=no` and `MulticastDNS=no` globally disable them on every link ("enabled on a link only if the per-link and the global setting is on"). The Avahi wiki asks for resolved's mDNS to be disabled before using avahi.
14. **nsswitch.** The resulting hosts line `mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns` matches the Avahi wiki verbatim (`install/setup.sh:63-65` against Arch's stock line).
15. **avahi.** `avahi-daemon.service` is enabled and `nss-mdns` installed, per the Avahi wiki's Hostname resolution section.
16. **ufw enablement.** `ENABLED=yes` plus `ufw.service` enabled is what `ufw enable` does at boot (`ufw-init start`). No `iptables.service` (ufw wiki), and the iptables-nft backend is used.
17. **ufw built-in rules.** ufw's stock `before.rules` and `before6.rules` accept mDNS (224.0.0.251 and ff02::fb on 5353) and DHCP replies, so avahi and DHCP work behind deny-incoming. The ufw wiki notes these built-in rules; the Avahi wiki says to open UDP 5353.
18. **LocalSend ports.** The upstream [protocol](https://github.com/localsend/protocol) lists Multicast (UDP) port 53317 on 224.0.0.167 and HTTP (TCP) port 53317, with HTTP discovery to each local IP as the fallback. `ufw allow in on <dev> to any port 53317` without a protocol covers both (ufw wiki: "allow port 51312 UDP and TCP"). Multicast passes `ufw-not-local`. This closes the open decision "LocalSend port: confirm 53317 TCP/UDP".
19. **LocalSend boot reset.** `karchy-localsend-firewall.service` (`After=ufw.service`, `Before=NetworkManager.service`) has no ordering cycle: ufw.service is `DefaultDependencies=no`, `Before=sysinit.target`.
20. **Regulatory domain support.** `wireless-regdb` and `iw` are karchy-settings depends, so the kernel loads `regulatory.db` (wiki). Arch's own `85-regulatory.rules` does nothing while `/etc/conf.d/wireless-regdom` is unset, so there's no conflict.
21. **sysctl ordering.** `systemd-sysctl.service` is `After=systemd-modules-load.service`, so `tcp_bbr` is loaded first. `60-karchy-network.conf` sorts after `50-default.conf`, so `fq` beats `fq_codel`. Per-device keys are applied by the udev rule in `99-systemd.rules`.
22. **ARP settings.** `arp_ignore=1` and `arp_announce=2` mean what the comments say (kernel ip-sysctl), and the all/interface maximum applies.
23. **BBR.** It follows the wiki's "First, load the tcp_bbr module". The wiki's example pairs BBR with `cake` and karchy uses `fq`; both are valid qdiscs for BBR and this is a deliberate choice (network-design §5).
24. **PipeWire user units.** They are enabled by the packages' install scripts (`systemctl --global enable pipewire-pulse.socket`, `wireplumber.service`); the PipeWire wiki says "should be enabled automatically by the package".
25. **Bluetooth codecs.** `pipewire-audio` (pulled by pipewire-pulse and pipewire-jack) brings Bluetooth support with SBC, AAC (libfdk-aac), aptX (libfreeaptx), LDAC, LC3 and Opus (`pacman -Si pipewire-audio`; PipeWire wiki "Bluetooth devices").
26. **pipewire-jack.** It is installed `--asdeps` before the meta-packages so jack2 isn't chosen (`install/setup.sh:35`); the two conflict.
27. **pipewire-alsa.** It is installed, as the PipeWire wiki's ALSA section asks.
28. **WirePlumber.** Stock config. HSP/HFP auto-switching is on by default (Bluetooth headset wiki). BlueZ seat monitoring uses logind, and greetd's session goes through `pam_systemd` via system-local-login.
29. **BlueZ power-on.** BlueZ 5.88 `AutoEnable` defaults to true (`/etc/bluetooth/main.conf:414-417`), so the adapter powers on. `bluetooth.service` is enabled (`install/setup.sh:80`). FastConnectable defaults off, which is right on a laptop (power cost noted in main.conf).
30. **Airplane mode.** `/dev/rfkill` is tagged `uaccess` (`70-uaccess.rules:97`) and systemd-rfkill "restores the RF kill switch state at early boot and saves it on each change" (systemd-rfkill(8)), as `bin/karchy-airplane:8-11` relies on.
31. **Portals.** Hyprland's `hyprland-portals.conf` is `default=hyprland;gtk`, and both backends are installed (`karchy/PKGBUILD:18`). The GTK portal provides the file chooser, which xdg-desktop-portal-hyprland lacks (Hyprland wiki). uwsm `-D Hyprland` sets `XDG_CURRENT_DESKTOP` for the user session (XDG Desktop Portal wiki).
32. **Polkit agent.** It is the shell's `shell/plugins/polkit/PolkitAgent.qml`, and polkit comes with quickshell's depends (Hyprland wiki: "requires the use of an external authentication agent").
33. **Wi-Fi regdomain polkit rule.** `50-karchy-wifi-regdomain.rules` scopes `manage-units` by the `unit` and `verb` details, the documented pattern.
34. **oo7 key import.** The rename syntax `ImportCredential=GLOB:RENAME` and the `/etc/credstore/` search path are both in systemd.exec(5). oo7's upstream `oo7-daemon.service` imports `oo7.keyring-encryption-password` and is `WantedBy=default.target`, so `systemctl --global enable oo7-daemon.service` (`install/setup.sh:86-87`) is right.
35. **D-57 premise.** greetd auto-login skips PAM auth, as the Greetd wiki says: "this setup does not work with greetd because it skips the auth stack entirely".
36. **greetd auto-login.** `[initial_session]` with `user` is the wiki's autologin method, and `greetd.service` is enabled. `/etc/greetd/config.toml` is a greetd backup file, so the installer's copy survives updates.
37. **Time sync.** `systemd-timesyncd` is enabled (`install/base.sh:197`) with Arch's pool servers (timesyncd wiki; host `timesyncd.conf`).
38. **CUPS basics.** CUPS socket activation is fine per the CUPS wiki ("alternatively use socket activation"), and avahi, which DNS-SD needs, is always installed (D-38).
39. **cups-browsed.** The installed cups-browsed 2.1.1 removed legacy UDP 631 browsing ([CHANGES.md](https://github.com/OpenPrinting/cups-browsed/blob/master/CHANGES.md), "Fixes CVE-2024-47176"), so karchy's config (`CreateIPPPrinterQueues Driverless`, `CreateRemoteCUPSPrinterQueues No`) has no exposed listener.
40. **USB drives.** `udisks2` comes with udiskie's depends, plus `gvfs`, `gvfs-mtp`, `gvfs-smb` and `cifs-utils` (`karchy-desktop/PKGBUILD:29`). udiskie is the only automounter started (`karchy/hypr/autostart.lua:33`).
41. **SMB fstab options.** `x-systemd.automount`, `x-systemd.mount-timeout`, `_netdev`, `nofail` and `x-systemd.idle-timeout` (`bin/karchy-mount-keep:199`) match the wiki's fstab#Remote file system and systemd.mount(5). The credentials file is root-owned 0600.
42. **Lock-screen PAM.** The stack (`system/pam.d/karchy-lock-password`) matches the unmodified pambase `system-auth` auth section. Its extra `-auth pam_systemd_home.so` line is harmless with the `-` prefix.
43. **Connectivity check.** It uses Arch's URL from networkmanager's own `/usr/lib/NetworkManager/conf.d/20-connectivity.conf` (wiki NetworkManager#Checking connectivity), as D-15 and D-68 intend.
44. **Firmware.** CachyOS's `linux-firmware` pulls `linux-firmware-mediatek`, the Framework's Wi-Fi and Bluetooth firmware (`pacman -Si cachyos/linux-firmware`).

Count: 44 items checked and found correct, 12 findings, 6 items unverified.
