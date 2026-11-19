# Shared by the root helpers in /usr/lib/nulifyer-vpn. Sourced, never run.
# shellcheck shell=bash disable=SC2034 # the variables are for the scripts that source it

[[ -z ${NV_COMMON:-} ]] || return 0
NV_COMMON=1

readonly NV_LIB=/usr/lib/nulifyer-vpn
readonly NV_CONFIG=/etc/nulifyer-vpn/config
readonly NV_RUN=/run/nulifyer-vpn
readonly NV_STATE=/var/lib/nulifyer-vpn
readonly NV_MODE_FILE=$NV_STATE/mode
readonly NV_STATUS=$NV_RUN/status
# A dispatcher event, a command or a timer asks the policy to look again by
# creating this file; nulifyer-vpn-policy.path starts the policy while it
# exists, so no request is lost while the policy is already running.
readonly NV_PENDING=$NV_RUN/pending
readonly NV_PROBE_MARK=20054

export PATH=/usr/bin
umask 022

nv_require_root() {
  (( EUID == 0 )) || { printf 'This command must run as root.\n' >&2; exit 1; }
}

# The configuration is root-owned and written only by the configure helper,
# which quotes every value, so it is safe to source. Defaults first, so an
# older file without the newer keys still works.
nv_load_config() {
  TRUSTED_INTERFACE=''
  TRUSTED_GATEWAY=''
  HOME_LAN=yes
  HANDSHAKE_MAX_AGE=150
  CONNECT_TIMEOUT=30
  # shellcheck source=/dev/null
  source "$NV_CONFIG"
}

nv_write_atomic() {
  local target=$1 value=$2 temp
  temp=$(mktemp "${target}.XXXXXX")
  printf '%s\n' "$value" >"$temp"
  chmod 0644 "$temp"
  mv -f "$temp" "$target"
}

nv_read_mode() {
  local mode
  mode=$(sed -n '1p' "$NV_MODE_FILE" 2>/dev/null || true)
  case $mode in
    on|off|auto) printf '%s\n' "$mode" ;;
    *) printf 'auto\n' ;;
  esac
}

nv_trigger() {
  install -d -m 0755 "$NV_RUN"
  : >"$NV_PENDING"
}

nv_valid_ipv4() {
  [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  local IFS=. octet
  for octet in $1; do (( 10#$octet <= 255 )) || return 1; done
}

nv_vpn_active() {
  [[ $(nmcli --escape no -g GENERAL.STATE connection show "$VPN_CONNECTION" 2>/dev/null || true) == activated ]]
}

# The physical link carrying the internet: the lowest-metric default route in
# the main table that isn't the tunnel.
nv_upstream() {
  ip -4 route show default 2>/dev/null | awk -v vpn="$VPN_INTERFACE" '
    $0 !~ ("dev " vpn "( |$)") { for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }'
}
