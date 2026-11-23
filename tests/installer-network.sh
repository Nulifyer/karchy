#!/bin/bash
# The installer's Wi-Fi list (install/network.sh): what `iw scan dump` says
# becomes the networks a person can pick, strongest first, each name once,
# with the kind of sign-in each needs. No radio and no root: the scan is text.
# Usage: tests/installer-network.sh [repo root]
set -uo pipefail
root=$(realpath "${1:-.}")
pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
# shellcheck source=/dev/null
source "$root/install/network.sh"

scan=$(printf '%b' \
  'BSS 02:00:00:00:01:00(on wlan0)\n\tcapability: ESS Privacy (0x0011)\n\tsignal: -71.00 dBm\n\tSSID: Home Net\n\tRSN:\t * Version: 1\n\t\t * Authentication suites: PSK\n' \
  'BSS 02:00:00:00:01:01(on wlan0) -- associated\n\tcapability: ESS Privacy (0x0011)\n\tsignal: -48.00 dBm\n\tSSID: Home Net\n\tRSN:\t * Version: 1\n\t\t * Authentication suites: PSK SAE\n' \
  'BSS 02:00:00:00:02:00(on wlan0)\n\tcapability: ESS (0x0001)\n\tsignal: -60.00 dBm\n\tSSID: Cafe Guest\n' \
  'BSS 02:00:00:00:03:00(on wlan0)\n\tcapability: ESS Privacy (0x0011)\n\tsignal: -55.00 dBm\n\tSSID: eduroam\n\tRSN:\t * Version: 1\n\t\t * Authentication suites: IEEE 802.1X\n' \
  'BSS 02:00:00:00:04:00(on wlan0)\n\tcapability: ESS Privacy (0x0011)\n\tsignal: -80.00 dBm\n\tSSID: Old Router\n' \
  'BSS 02:00:00:00:05:00(on wlan0)\n\tcapability: ESS Privacy (0x0011)\n\tsignal: -40.00 dBm\n\tSSID: \n\tRSN:\t * Version: 1\n\t\t * Authentication suites: PSK\n' \
  'BSS 02:00:00:00:06:00(on wlan0)\n\tcapability: ESS Privacy (0x0011)\n\tsignal: -41.00 dBm\n\tSSID: \\xf0\\x9f\\x8f\\xa0\n\tRSN:\t * Version: 1\n\t\t * Authentication suites: PSK\n' \
  'BSS 02:00:00:00:07:00(on wlan0)\n\tcapability: ESS Privacy (0x0011)\n\tsignal: -66.00 dBm\n\tSSID: WPA3 Only\n\tRSN:\t * Version: 1\n\t\t * Authentication suites: SAE\n')

got=$(net_wifi_networks - <<<"$scan")
check "strongest first, a name once at its best signal, hidden and unprintable names left out" "$got" \
  $'-48\tpsk\tHome Net\n-55\t8021x\teduroam\n-60\topen\tCafe Guest\n-66\tpsk\tWPA3 Only\n-80\twep\tOld Router'
check "no networks is no lines" "$(net_wifi_networks - <<<"")" ""
check "a name with a space and one word stay whole" "$(net_wifi_networks - <<<"$scan" | cut -f3 | head -n1)" "Home Net"

check "strong" "$(net_signal_word -50)" strong
check "good" "$(net_signal_word -60)" good
check "fair" "$(net_signal_word -70)" fair
check "weak" "$(net_signal_word -85)" weak
check "a password network needs no note" "$(net_kind_note psk)" ""
check "an open network says so" "$(net_kind_note open)" "   open, no password"

# The ISO's start script asks for the network before anything that needs it:
# the keyring unit waits for a clock set from the network, so waiting for it
# first left a laptop without a cable at a blank screen (rc.11).
start=$root/packaging/iso/airootfs/usr/local/bin/karchy-iso-start
check "the start script doesn't wait for the keyring itself" "$(grep -c 'systemctl start pacman-init' "$start")" 0
check "the installer waits for the keyring after the network" \
  "$(awk '/net_wait \|\| die/ { n = NR } /net_keyring_ready \|\| die/ { k = NR } END { print (n && k && n < k) ? "after" : "wrong" }' "$root/install/karchy-install")" after

echo "installer-network: $pass passed, $failures failed"
((failures == 0))
