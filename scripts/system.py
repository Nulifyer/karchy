#!/usr/bin/env python3
"""Remove a 1.x installation (root-owned helpers copied by this script).

From 2.0 the helpers are the nulifyer-vpn pacman package (see README.md);
this script only takes a 1.x installation back out before switching.
"""

import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import pwd
import re
import shlex
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import time
import tomllib
import uuid

REPO = Path(__file__).resolve().parent.parent
CONFIG = "/etc/nulifyer-vpn/config"
STATE = "/var/lib/nulifyer-vpn/installation"
UNITS = ["nulifyer-vpn-guard.service", "nulifyer-vpn-home-reply.service",
         "nulifyer-vpn-monitor.timer"]
REQUIRED = {
    "VPN_CONNECTION", "VPN_INTERFACE", "VPN_ENDPOINT_HOST", "VPN_ENDPOINT_PORT",
    "VPN_CLIENT_PORT", "VPN_DNS", "TRUSTED_UUIDS", "TRUSTED_DNS",
    "TRUSTED_INTERFACE", "TRUSTED_GATEWAY", "DOH_IPV4", "HANDSHAKE_MAX_AGE",
    "CONNECT_TIMEOUT", "STATUS_MAX_AGE",
}
DNS_PROPERTIES = [f"ipv{version}.{key}" for version in (4, 6)
                  for key in ("ignore-auto-dns", "dns", "dns-search", "dns-priority")]


def read_config(path):
    """Parse assignments without executing a configuration as shell code."""
    values = {}
    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        parts = shlex.split(line, comments=True)
        if not parts:
            continue
        if len(parts) != 1 or "=" not in parts[0]:
            raise ValueError(f"Invalid configuration assignment on line {number}")
        key, value = parts[0].split("=", 1)
        if key not in REQUIRED or key in values:
            raise ValueError(f"Unknown or duplicate configuration key: {key}")
        values[key] = value
    missing = REQUIRED - values.keys()
    if missing:
        raise ValueError("Missing configuration keys: " + ", ".join(sorted(missing)))
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 _.-]*", values["VPN_CONNECTION"]):
        raise ValueError("VPN_CONNECTION must be a NetworkManager profile name or UUID")
    for key in ("VPN_INTERFACE", "TRUSTED_INTERFACE"):
        if values[key] or key == "VPN_INTERFACE":
            if not re.fullmatch(r"[A-Za-z0-9_.-]{1,15}", values[key]):
                raise ValueError(f"Invalid interface name: {key}")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]{0,252}", values["VPN_ENDPOINT_HOST"]):
        raise ValueError("VPN_ENDPOINT_HOST must be an IPv4 address or DNS hostname")
    for key in ("VPN_ENDPOINT_PORT", "VPN_CLIENT_PORT"):
        if not values[key].isdigit() or not 1 <= int(values[key]) <= 65535:
            raise ValueError(f"Invalid UDP port: {key}")
    for key in ("HANDSHAKE_MAX_AGE", "CONNECT_TIMEOUT", "STATUS_MAX_AGE"):
        if not values[key].isdigit() or not 1 <= int(values[key]) <= 86400:
            raise ValueError(f"Invalid timeout: {key}")
    if int(values["STATUS_MAX_AGE"]) < 10:
        raise ValueError("STATUS_MAX_AGE must cover the five-second monitor interval")
    ipaddress.IPv4Address(values["VPN_DNS"])
    for key in ("TRUSTED_DNS", "TRUSTED_GATEWAY"):
        if values[key]:
            ipaddress.IPv4Address(values[key])
    for address in values["DOH_IPV4"].split(","):
        ipaddress.IPv4Address(address.strip())
    for trusted in values["TRUSTED_UUIDS"].split():
        if str(uuid.UUID(trusted)) != trusted:
            raise ValueError("Trusted network UUIDs must use their canonical form")
    if values["TRUSTED_UUIDS"] and not values["TRUSTED_DNS"]:
        raise ValueError("Trusted networks require TRUSTED_DNS")
    if bool(values["TRUSTED_INTERFACE"]) != bool(values["TRUSTED_GATEWAY"]):
        raise ValueError("Set both TRUSTED_INTERFACE and TRUSTED_GATEWAY for hairpin replies")
    return values


def run(*args, check=True):
    return subprocess.run(args, check=check, text=True, capture_output=True)


class System:
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.live = self.root == Path("/")
        if self.live and os.geteuid() != 0:
            raise ValueError("System setup requires root. Use sudo in a terminal or pkexec from the desktop.")
        self.state = self.path(STATE)

    def path(self, name):
        return self.root / name.lstrip("/")

    def write(self, name, content, mode):
        target = self.path(name)
        target.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as stream:
            temp = Path(stream.name)
            stream.write(content)
            stream.flush()
            os.fchmod(stream.fileno(), mode)
        try:
            os.replace(temp, target)
        finally:
            temp.unlink(missing_ok=True)

    def remember(self, record, name):
        if name in record["originals"]:
            return
        target = self.path(name)
        if target.is_symlink():
            item = {"kind": "symlink", "target": os.readlink(target)}
        elif target.is_file():
            backup = str(len(record["originals"]))
            shutil.copy2(target, self.state / backup)
            item = {"kind": "file", "backup": backup,
                    "mode": stat.S_IMODE(target.stat().st_mode)}
        elif target.exists():
            raise ValueError(f"Refusing to replace a non-file: {name}")
        else:
            item = {"kind": "absent"}
        record["originals"][name] = item
        self.save(record)

    def save(self, record):
        self.write(STATE + "/receipt.json", (json.dumps(record, indent=2) + "\n").encode(), 0o600)

    def preflight(self, config, dns_path):
        commands = ["nmcli", "wg", "nft", "iptables", "systemctl", "pkexec",
                    "jq", "ping", "flock", "dnscrypt-proxy", "ufw"]
        for command in commands:
            if not shutil.which(command):
                raise ValueError(f"Missing dependency: {command}. See README.md.")
        profile = config["VPN_CONNECTION"]
        if run("nmcli", "--escape", "no", "-g", "connection.type", "connection", "show", profile).stdout.strip() != "wireguard":
            raise ValueError("The selected NetworkManager connection must be WireGuard")
        port = run("nmcli", "--escape", "no", "-g", "wireguard.listen-port", "connection", "show", profile).stdout.strip()
        if port != config["VPN_CLIENT_PORT"]:
            raise ValueError("VPN_CLIENT_PORT must match the profile's fixed wireguard.listen-port")
        iface = run("nmcli", "--escape", "no", "-g", "connection.interface-name", "connection", "show", profile).stdout.strip()
        if iface != config["VPN_INTERFACE"]:
            raise ValueError("VPN_INTERFACE must match the profile's connection.interface-name")
        dns = run("nmcli", "--escape", "no", "-g", "ipv4.dns", "connection", "show", profile).stdout.splitlines()
        if config["VPN_DNS"] not in dns:
            raise ValueError("VPN_DNS must be configured in the WireGuard profile's ipv4.dns")
        routes = run("nmcli", "--escape", "no", "-g", "wireguard.peer-routes", "connection", "show", profile).stdout.strip()
        dns_priority = run("nmcli", "--escape", "no", "-g", "ipv4.dns-priority", "connection", "show", profile).stdout.strip()
        dns_search = run("nmcli", "--escape", "no", "-g", "ipv4.dns-search", "connection", "show", profile).stdout.strip()
        if routes != "yes" or int(dns_priority) >= 0 or "~." not in dns_search.split(","):
            raise ValueError("Enable WireGuard peer routes, negative ipv4.dns-priority, and ipv4.dns-search '~.'")
        peers = run("nmcli", "--escape", "no", "-g", "wireguard.peers", "connection", "show", profile).stdout
        endpoints = re.findall(r"endpoint=([^\s]+)", peers)
        endpoint = config["VPN_ENDPOINT_HOST"] + ":" + config["VPN_ENDPOINT_PORT"]
        if endpoints != [endpoint] or "allowed-ips=0.0.0.0/0" not in peers:
            raise ValueError("Use one IPv4 full-tunnel peer matching VPN_ENDPOINT_HOST and VPN_ENDPOINT_PORT")
        if "Status: active" not in run("ufw", "status").stdout:
            raise ValueError("UFW must already be active. System setup does not change your firewall defaults.")
        dns_config = tomllib.loads(dns_path.read_text())
        if not {"127.0.0.1:53", "[::1]:53"}.issubset(dns_config.get("listen_addresses", [])):
            raise ValueError("DNSCrypt-proxy must listen on both loopback addresses. See --configure-dnscrypt.")

    def install(self, args):
        if not re.fullmatch(r"[a-z_][a-z0-9_-]*[$]?", args.user):
            raise ValueError("Supply a valid local account with --user")
        config_path = Path(args.config) if args.config else self.path(CONFIG)
        if not config_path.is_file():
            raise ValueError("Copy examples/config outside the repository, edit it, and pass --config /path/to/config")
        if self.live and not args.config:
            if config_path.is_symlink() or config_path.stat().st_uid != 0 or config_path.stat().st_mode & 0o022:
                raise ValueError("Existing system configuration must be root-owned and protected from user writes")
        config = read_config(config_path)
        dns_source = REPO / "examples/dnscrypt-proxy.toml"
        dns_path = dns_source if args.configure_dnscrypt else self.path("/etc/dnscrypt-proxy/dnscrypt-proxy.toml")
        if self.live:
            pwd.getpwnam(args.user)
            self.preflight(config, dns_path)
        receipt = self.state / "receipt.json"
        if receipt.exists():
            record = json.loads(receipt.read_text())
        else:
            self.state.mkdir(parents=True, mode=0o700)
            self.state.chmod(0o700)
            enabled = {}
            nm_original = {}
            if self.live:
                for unit in [*UNITS, "dnscrypt-proxy.service"]:
                    enabled[unit] = run("systemctl", "is-enabled", unit, check=False).stdout.strip()
                for key in ("connection.autoconnect", "connection.autoconnect-retries"):
                    nm_original[key] = run("nmcli", "--escape", "no", "-g", key, "connection", "show", config["VPN_CONNECTION"]).stdout.strip().split()[0]
            active = {}
            if self.live:
                active = {unit: run("systemctl", "is-active", "--quiet", unit, check=False).returncode == 0
                          for unit in [*UNITS, "dnscrypt-proxy.service"]}
            record = {"originals": {}, "enabled": enabled, "active": active, "nm_original": nm_original,
                      "vpn_connection": config["VPN_CONNECTION"], "installed": {}}
            # Preserve the earlier installation's DNS snapshots when adopting it.
            profiles = self.path("/var/lib/nulifyer-vpn/profiles")
            record["profile_dns"] = {}
            if self.live and profiles.exists():
                shutil.copytree(profiles, self.state / "original-profiles")
                for profile in profiles.iterdir():
                    if not re.fullmatch(r"[0-9a-f-]{36}", profile.name):
                        continue
                    if run("nmcli", "connection", "show", profile.name, check=False).returncode:
                        continue
                    record["profile_dns"][profile.name] = {
                        key: run("nmcli", "--escape", "no", "-g", key, "connection", "show", profile.name).stdout.strip()
                        for key in DNS_PROPERTIES
                    }
        if record["vpn_connection"] != config["VPN_CONNECTION"]:
            raise ValueError("Uninstall system setup before adopting a different WireGuard profile")
        files = {}
        for directory, destination in [("bin", "/usr/local/bin"), ("libexec", "/usr/local/libexec"),
                                       ("systemd", "/etc/systemd/system")]:
            for source in sorted((REPO / directory).iterdir()):
                files[destination + "/" + source.name] = (source.read_bytes(), 0o644 if directory == "systemd" else 0o755)
        files["/etc/NetworkManager/dispatcher.d/90-nulifyer-vpn"] = ((REPO / "networkmanager/90-nulifyer-vpn").read_bytes(), 0o755)
        policy = (REPO / "polkit/49-nulifyer-vpn.rules.in").read_text().replace("@USER_JSON@", json.dumps(args.user))
        files["/etc/polkit-1/rules.d/49-nulifyer-vpn.rules"] = (policy.encode(), 0o644)
        if args.config or not self.path(CONFIG).exists():
            canonical = "".join(f"{key}={shlex.quote(value)}\n" for key, value in config.items())
            files[CONFIG] = (canonical.encode(), 0o644)
        if args.configure_dnscrypt:
            files["/etc/dnscrypt-proxy/dnscrypt-proxy.toml"] = (dns_source.read_bytes(), 0o644)
        for name in [*files, "/etc/NetworkManager/dispatcher.d/pre-up.d/90-nulifyer-vpn",
                     "/var/lib/nulifyer-vpn/mode", "/var/lib/nulifyer-vpn/endpoint-ip"]:
            self.remember(record, name)
        if self.live:
            run("systemctl", "stop", "nulifyer-vpn-monitor.timer", "nulifyer-vpn-monitor.service", check=False)
            if Path("/usr/local/libexec/nulifyer-vpn-home-reply").exists() and self.path(CONFIG).exists():
                run("/usr/local/libexec/nulifyer-vpn-home-reply", "remove")
        for name, (content, mode) in files.items():
            self.write(name, content, mode)
            if name not in (CONFIG, "/etc/dnscrypt-proxy/dnscrypt-proxy.toml"):
                record["installed"][name] = hashlib.sha256(content).hexdigest()
        link = self.path("/etc/NetworkManager/dispatcher.d/pre-up.d/90-nulifyer-vpn")
        link.parent.mkdir(parents=True, exist_ok=True)
        link.unlink(missing_ok=True)
        link.symlink_to("../90-nulifyer-vpn")
        if not self.path("/var/lib/nulifyer-vpn/mode").exists():
            self.write("/var/lib/nulifyer-vpn/mode", b"auto\n", 0o644)
        if self.live and not self.path("/var/lib/nulifyer-vpn/endpoint-ip").exists():
            addresses = socket.getaddrinfo(config["VPN_ENDPOINT_HOST"], None, socket.AF_INET)
            self.write("/var/lib/nulifyer-vpn/endpoint-ip", (addresses[0][4][0] + "\n").encode(), 0o644)
        record.update(version=json.loads((REPO / "manifest.json").read_text())["version"], user=args.user)
        self.save(record)
        if self.live:
            run("systemctl", "daemon-reload")
            if args.configure_dnscrypt:
                run("systemctl", "restart", "dnscrypt-proxy.service")
            run("systemctl", "enable", "--now", "dnscrypt-proxy.service", *UNITS)
            run("/usr/local/libexec/nulifyer-vpn-home-reply")
            run("systemctl", "start", "nulifyer-vpn-monitor.service")
        self.check()
        print(f"Installed system helpers {record['version']}. Existing VPN keys and mode were preserved.")

    def check(self):
        record = json.loads((self.state / "receipt.json").read_text())
        for name, expected in record["installed"].items():
            target = self.path(name)
            if target.is_symlink() or hashlib.sha256(target.read_bytes()).hexdigest() != expected:
                raise ValueError(f"Installed file differs from its receipt: {name}")
            if self.live and (target.stat().st_uid != 0 or target.stat().st_mode & 0o022):
                raise ValueError(f"Installed file is not protected by root ownership: {name}")
        link = self.path("/etc/NetworkManager/dispatcher.d/pre-up.d/90-nulifyer-vpn")
        if not link.is_symlink() or os.readlink(link) != "../90-nulifyer-vpn":
            raise ValueError("The NetworkManager pre-up dispatcher link is missing or changed")
        read_config(self.path(CONFIG))
        if self.live:
            config = self.path(CONFIG)
            if config.is_symlink() or config.stat().st_uid != 0 or config.stat().st_mode & 0o022:
                raise ValueError("The system configuration must be root-owned and protected from user writes")
        print(f"System helpers {record['version']} match their installation receipt.")

    def uninstall(self):
        record = json.loads((self.state / "receipt.json").read_text())
        if self.live:
            run("systemctl", "stop", "nulifyer-vpn-monitor.timer", "nulifyer-vpn-monitor.service")
            # DNS restoration can reapply a device. Prevent that transition
            # from starting a monitor while its files are being restored.
            self.path("/etc/NetworkManager/dispatcher.d/pre-up.d/90-nulifyer-vpn").unlink(missing_ok=True)
            self.path("/etc/NetworkManager/dispatcher.d/90-nulifyer-vpn").unlink(missing_ok=True)
            run("/usr/local/libexec/nulifyer-vpn-control", "off")
            run("/usr/local/libexec/nulifyer-vpn-configure-dns", "--restore-all")
            run("systemctl", "disable", "--now", *UNITS)
        for name, item in record["originals"].items():
            target = self.path(name)
            if item["kind"] == "absent":
                target.unlink(missing_ok=True)
            elif item["kind"] == "file":
                self.write(name, (self.state / item["backup"]).read_bytes(), item["mode"])
            else:
                target.unlink(missing_ok=True)
                target.symlink_to(item["target"])
        if self.live:
            for key, value in record["nm_original"].items():
                run("nmcli", "connection", "modify", record["vpn_connection"], key, value)
            for profile, properties in record.get("profile_dns", {}).items():
                if run("nmcli", "connection", "show", profile, check=False).returncode:
                    continue
                arguments = [item for pair in properties.items() for item in pair]
                run("nmcli", "connection", "modify", profile, *arguments)
                iface = run("nmcli", "--escape", "no", "-g", "GENERAL.DEVICES", "connection", "show", profile).stdout.strip()
                if iface and iface != "--":
                    run("nmcli", "device", "reapply", iface)
            original_profiles = self.state / "original-profiles"
            if original_profiles.exists():
                shutil.copytree(original_profiles, self.path("/var/lib/nulifyer-vpn/profiles"), dirs_exist_ok=True)
            run("systemctl", "daemon-reload")
            for unit, enabled in record["enabled"].items():
                if enabled == "enabled":
                    run("systemctl", "enable", unit)
                elif enabled in ("disabled", "not-found", ""):
                    run("systemctl", "disable", unit, check=False)
                if record["active"].get(unit):
                    run("systemctl", "restart" if unit == "dnscrypt-proxy.service" else "start", unit)
                else:
                    run("systemctl", "stop", unit, check=False)
            if record["enabled"].get("nulifyer-vpn-monitor.timer") == "enabled":
                run("systemctl", "start", "nulifyer-vpn-monitor.service")
        archive = self.state.with_name("installation-removed-" + str(time.time_ns()))
        self.state.rename(archive)
        print(f"Restored pre-installation files and settings. Local backup retained at {archive}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default="/", help="Stage filesystem operations under another root; do not change host services")
    commands = parser.add_subparsers(dest="command", required=True)
    install = commands.add_parser("install", help="Install or update root-owned system helpers")
    install.add_argument("--user", required=True, help="Local account allowed to operate the fixed VPN control helper")
    install.add_argument("--config", help="Initial configuration; omitted on upgrades to preserve the existing file")
    install.add_argument("--configure-dnscrypt", action="store_true", help="Install the bundled Quad9 DoH configuration after backing up the existing one")
    commands.add_parser("check", help="Check installed helper hashes, permissions, and configuration")
    commands.add_parser("uninstall", help="Restore files and settings saved before system installation")
    args = parser.parse_args()
    os.environ["PATH"] = "/usr/local/sbin:/usr/local/bin:/usr/bin"
    try:
        system = System(args.root)
        if args.command == "install":
            raise ValueError("2.0 installs as the nulifyer-vpn package; see README.md. "
                             "This script only removes a 1.x installation (uninstall).")
        elif args.command == "check":
            system.check()
        else:
            system.uninstall()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"System setup failed: {error}", file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr.strip(), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
