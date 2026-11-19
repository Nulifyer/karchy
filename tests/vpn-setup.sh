#!/bin/bash
# karchy-network-vpn setup: the VPN package's configuration from a WireGuard
# profile, and the refusals before anyone is asked for a password.
# Run: tests/vpn-setup.sh [repo root]. nmcli and karchy-vpn are stand-ins.
set -euo pipefail
root=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
uuid=11111111-2222-3333-4444-555555555555

# nmcli -g <field> connection show uuid <uuid>: answers from $work/profile;
# connection modify: records its arguments.
cat >"$work/bin/nmcli" <<'STUB'
#!/bin/bash
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [[ ${args[i]} == -g ]]; then sed -n "s/^${args[i+1]}=//p" "$WORK/profile"; exit 0; fi
done
[[ ${args[0]} == connection && ${args[1]} == modify ]] && printf '%s\n' "${args[*]}" >"$WORK/modified"
exit 0
STUB
cat >"$work/bin/karchy-vpn" <<'STUB'
#!/bin/bash
[[ $1 == setup ]] && cp "$2" "$WORK/config"
STUB
chmod +x "$work/bin/"*
export WORK=$work PATH="$work/bin:$PATH"

profile() { printf '%s\n' "$@" >"$work/profile"; rm -f "$work/config" "$work/modified"; }
run() { "$root/bin/karchy-network-vpn" setup "$@" 2>"$work/err"; }
refused() { # <exit code> <words in the reason> <setup args...>
  local code=$1 words=$2 got=0
  shift 2
  run "$@" || got=$?
  [[ $got == "$code" ]] || { echo "FAIL: expected exit $code, got $got: $(cat "$work/err")"; exit 1; }
  grep -q "$words" "$work/err" || { echo "FAIL: reason lacks '$words': $(cat "$work/err")"; exit 1; }
  [[ ! -e $work/config ]] || { echo "FAIL: a refused setup reached karchy-vpn"; exit 1; }
}
base=(connection.type=wireguard "connection.id=Home VPN" connection.interface-name=wg0 wireguard.listen-port=0)
peer="KEY= allowed-ips=0.0.0.0/0 endpoint=vpn.example.org:51820"

# A provider's file as imported: no listen port, DNS present.
profile "${base[@]}" ipv4.dns=10.0.0.1,10.0.0.2 "wireguard.peers=$peer"
run "$uuid"
for line in "VPN_CONNECTION=Home\\ VPN" VPN_INTERFACE=wg0 VPN_ENDPOINT_HOST=vpn.example.org VPN_ENDPOINT_PORT=51820 \
  VPN_CLIENT_PORT=51820 VPN_DNS=10.0.0.1; do
  grep -qxF "$line" "$work/config" || { echo "FAIL: config lacks $line"; cat "$work/config"; exit 1; }
done
grep -q "wireguard.listen-port 51820 wireguard.peer-routes yes ipv4.dns 10.0.0.1 ipv4.dns-search ~. ipv4.dns-priority -100 connection.autoconnect no" "$work/modified" ||
  { echo "FAIL: the profile wasn't prepared: $(cat "$work/modified")"; exit 1; }

# Its own listen port is kept; a typed DNS server is used when it names none.
profile connection.type=wireguard connection.id=wg1 connection.interface-name=wg1 wireguard.listen-port=40000 "wireguard.peers=$peer"
refused 3 "names no DNS server" "$uuid"
profile connection.type=wireguard connection.id=wg1 connection.interface-name=wg1 wireguard.listen-port=40000 "wireguard.peers=$peer"
run "$uuid" 10.9.9.9
grep -qxF VPN_CLIENT_PORT=40000 "$work/config" && grep -qxF VPN_DNS=10.9.9.9 "$work/config" || { echo "FAIL: port or typed DNS"; exit 1; }

# Refused in plain words, before any password.
profile "${base[@]}" ipv4.dns=10.0.0.1 "wireguard.peers=$peer"
refused 2 "IPv4 address" "$uuid" "not-an-address"
refused 2 "Not a connection UUID" "wg0"
profile connection.type=vpn connection.id=x connection.interface-name=x
refused 2 "WireGuard profile" "$uuid"
profile "${base[@]}" ipv4.dns=10.0.0.1 "wireguard.peers=KEY= allowed-ips=10.0.0.0/8 endpoint=vpn.example.org:51820"
refused 2 "only some traffic" "$uuid"
profile "${base[@]}" ipv4.dns=10.0.0.1 "wireguard.peers=A= allowed-ips=0.0.0.0/0 endpoint=a.example:1, B= allowed-ips=10.0.0.0/8 endpoint=b.example:2"
refused 2 "exactly one server" "$uuid"
profile "${base[@]}" ipv4.dns=10.0.0.1 "wireguard.peers=KEY= allowed-ips=0.0.0.0/0 endpoint=[2001:db8::1]:51820"
refused 2 "server address" "$uuid"
profile "${base[@]}" ipv4.dns=10.0.0.1 "wireguard.peers=KEY= allowed-ips=0.0.0.0/0"
refused 2 "server address" "$uuid"
echo "vpn setup ok"
