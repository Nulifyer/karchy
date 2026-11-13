# shellcheck shell=bash
# Shared helpers for the karchy installer. Sourced, not executed.

KARCHY_INSTALL_LOG=${KARCHY_INSTALL_LOG:-/var/log/karchy-install.log}
KARCHY_MNT=${KARCHY_MNT:-/mnt}

# Keep a handle on the console: during a step stderr goes to the log, but
# progress and errors must still reach the screen.
exec {KARCHY_CONSOLE}>&2

log() {
  local line
  line="$(date +%H:%M:%S) $*"
  echo "$line" >>"$KARCHY_INSTALL_LOG"
  echo "$line" >&"$KARCHY_CONSOLE"
}

die() {
  log "ERROR: $*"
  exit 1
}

# Run one named step with its output appended to the log. A failing command
# anywhere in the step trips the ERR trap (errexit and errtrace are on), which
# stops the install and points at the log. Steps run in the current shell so
# the variables they set (devices, UUIDs) carry over to later steps.
KARCHY_STEP=""

on_error() {
  local status=$?
  log "ERROR: step '${KARCHY_STEP:-startup}' failed (exit $status); see $KARCHY_INSTALL_LOG"
  exit "$status"
}

step() {
  KARCHY_STEP="$1"
  shift
  log "==> $KARCHY_STEP"
  "$@" >>"$KARCHY_INSTALL_LOG" 2>&1
  KARCHY_STEP=""
}

in_target() {
  arch-chroot "$KARCHY_MNT" "$@"
}

# Run a command in the target as the new user.
as_user() {
  arch-chroot -u "$KARCHY_USER" "$KARCHY_MNT" env HOME="/home/$KARCHY_USER" "$@"
}

# The partition device for partition N of a disk (sda1, vda1, nvme0n1p1).
partition() {
  local disk="$1" number="$2"
  if [[ $disk =~ [0-9]$ ]]; then
    echo "${disk}p${number}"
  else
    echo "${disk}${number}"
  fi
}

# Total RAM in whole GiB, rounded up.
ram_gib() {
  awk '/^MemTotal:/ { printf "%d\n", ($2 + 1048575) / 1048576 }' /proc/meminfo
}

cpu_vendor() {
  awk -F': ' '/^vendor_id/ { print $2; exit }' /proc/cpuinfo
}

has_nvidia() {
  lspci -nn 2>/dev/null | grep -Eiq '(VGA|3D).*NVIDIA'
}
