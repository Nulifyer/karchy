# shellcheck shell=bash
# Shared helpers for the karchy installer. Sourced, not executed.

KARCHY_INSTALL_LOG=${KARCHY_INSTALL_LOG:-/var/log/karchy-install.log}
KARCHY_MNT=${KARCHY_MNT:-/mnt}

# Keep a handle on the console: during a step stderr goes to the log, but
# progress and errors must still reach the screen.
exec {KARCHY_CONSOLE}>&2

# One line for the log file, with the time. On the screen it appears as it is
# in plain mode; the drawn screens (install/ui.sh) keep it for the end, where
# the finish screen lists what the steps had to say.
KARCHY_NOTES=()

log() {
  local line
  line="$(date +%H:%M:%S) $*"
  echo "$line" >>"$KARCHY_INSTALL_LOG"
  if [[ ${KARCHY_UI:-plain} == tui ]]; then
    KARCHY_NOTES+=("$*")
  else
    echo "$line" >&"$KARCHY_CONSOLE"
  fi
}

# Stop with a message. During a step the ERR trap does not fire for an
# `exit`, so this reports the failure itself.
die() {
  echo "$(date +%H:%M:%S) ERROR: $*" >>"$KARCHY_INSTALL_LOG"
  if [[ ${KARCHY_UI:-plain} == tui ]]; then
    ui_error "$*" "$KARCHY_STEP"
  else
    echo "$(date +%H:%M:%S) ERROR: $*" >&"$KARCHY_CONSOLE"
  fi
  exit 1
}

# Steps are listed first (step) and then run in order (steps_run), each with
# its output appended to the log. A failing command anywhere in a step trips
# the ERR trap (errexit and errtrace are on), which stops the install and
# points at the log. Steps run in the current shell so the variables they set
# (devices, UUIDs) carry over to later steps.
KARCHY_STEP=""
KARCHY_STEP_COMMANDS=()

on_error() {
  local status=$?
  echo "$(date +%H:%M:%S) ERROR: step '${KARCHY_STEP:-startup}' failed (exit $status)" >>"$KARCHY_INSTALL_LOG"
  if [[ ${KARCHY_UI:-plain} == tui ]]; then
    if [[ -n $KARCHY_STEP ]]; then
      ui_error "\"$KARCHY_STEP\" failed (exit $status)" "$KARCHY_STEP"
    else
      ui_error "The installer stopped (exit $status)" "startup"
    fi
  else
    {
      echo "$(date +%H:%M:%S) ERROR: step '${KARCHY_STEP:-startup}' failed (exit $status); see $KARCHY_INSTALL_LOG"
      echo "$(date +%H:%M:%S) To try again, fix what the log shows, reboot the install media and run karchy-install again. It starts over and erases the disk again."
    } >&"$KARCHY_CONSOLE"
  fi
  exit "$status"
}

step() {
  UI_STEP_NAMES+=("$1")
  shift
  KARCHY_STEP_COMMANDS+=("$*")
}

steps_run() {
  local i total=${#UI_STEP_NAMES[@]}
  local -a command
  ui_steps_begin
  for ((i = 0; i < total; i++)); do
    KARCHY_STEP="${UI_STEP_NAMES[i]}"
    echo "$(date +%H:%M:%S) ==> [$((i + 1))/$total] $KARCHY_STEP" >>"$KARCHY_INSTALL_LOG"
    [[ $KARCHY_UI == tui ]] || echo "$(date +%H:%M:%S) ==> [$((i + 1))/$total] $KARCHY_STEP" >&"$KARCHY_CONSOLE"
    ui_step_start "$i"
    read -ra command <<<"${KARCHY_STEP_COMMANDS[i]}"
    "${command[@]}" >>"$KARCHY_INSTALL_LOG" 2>&1
    ui_step_done "$i"
    KARCHY_STEP=""
  done
  ui_steps_end
}

in_target() {
  arch-chroot "$KARCHY_MNT" "$@"
}

# Run a command in the target as the new user. The live system's root session
# must not leak in: its XDG_RUNTIME_DIR (/run/user/0) isn't the user's to
# write, so karchy-theme-set's lock there failed with "Permission denied", and
# its session bus isn't the user's either. Without them, commands fall back to
# /tmp and to working without a session, as they do in the chroot anyway.
as_user() {
  arch-chroot -u "$KARCHY_USER" "$KARCHY_MNT" \
    env -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS HOME="/home/$KARCHY_USER" "$@"
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

# The console font for this machine's screen: karchy's monospace font in a
# cell that keeps text readable at the screen's height in pixels (a Framework
# 13 at 2256x1504 gets 16x32: 141 columns by 47 lines). KARCHY_CONSOLE_FONT
# in an unattended config overrides it.
console_font() {
  local height=0
  if [[ -n ${KARCHY_CONSOLE_FONT:-} ]]; then
    echo "$KARCHY_CONSOLE_FONT"
    return
  fi
  IFS=, read -r _ height </sys/class/graphics/fb0/virtual_size 2>/dev/null || true
  [[ $height =~ ^[0-9]+$ ]] || height=0
  if ((height >= 1400)); then
    echo karchy-16x32
  elif ((height >= 1000)); then
    echo karchy-12x24
  else
    echo karchy-10x20
  fi
}

# Total RAM in whole GiB, rounded up.
ram_gib() {
  awk '/^MemTotal:/ { printf "%d\n", ($2 + 1048575) / 1048576 }' /proc/meminfo
}

cpu_vendor() {
  awk -F': ' '/^vendor_id/ { print $2; exit }' /proc/cpuinfo
}

# The firmware has no platform key yet, so new Secure Boot keys can be
# enrolled from the OS (D-31).
firmware_setup_mode() {
  local var=/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c
  [[ -r $var && $(od -An -t u1 -j4 -N1 "$var" | tr -d ' ') == "1" ]]
}

# The driver this machine's NVIDIA GPUs need: open (Turing or newer), 580xx
# (Maxwell, Pascal, Volta) or unsupported (Kepler and older); nothing without
# an NVIDIA GPU. karchy-hw-nvidia-generation holds the device ID ranges.
nvidia_generation() {
  "$KARCHY_SRC/bin/karchy-hw-nvidia-generation" || true
}
