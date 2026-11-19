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
  # errtrace runs this in a failing $(...) too, and again in the shell that
  # ran it: report once, from the installer's own shell.
  ((BASH_SUBSHELL == 0)) || exit "$status"
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

# pacman in the target, without snapshots. arch-chroot runs the command in a
# new PID namespace but leaves it the live system's /proc, where ps can't find
# itself: snap-pac's hooks run ps to name each pre snapshot, and it stopped
# with "fatal library error, lookup self" (the snapshots were made, the pre
# ones without a description). A /proc of the namespace's own (unshare
# --mount-proc) mends ps but makes the chroot look like the running system to
# snap-pac, which then asks snapperd over D-Bus and makes no snapshot at all.
# The install's transactions are a half-built system nobody boots back to, so
# they take none (D-129); the first update makes the first pair.
in_target_pacman() {
  SNAP_PAC_SKIP=y in_target pacman "$@"
}

# Run a command that downloads packages (pacman, pacstrap, in_target pacman)
# and get round mirrors that fail. pacman tries the next mirror when one lacks
# a package, but asks for the package's signature only where the package came
# from: a mirror caught in the middle of a sync, holding the package without
# its .sig, fails the whole transaction whatever follows in the list (seen on
# CachyOS's mirrors; bin/karchy-mirrors-demote says more). So when the
# command fails with "failed retrieving file ... from <mirror>", those mirrors
# go to the end of the lists (the live system's, and the target's once it has
# them), the databases are fetched again from the mirror now first, and the
# command runs again. It stops when it succeeds, when a failure names no
# mirror that could still be moved (the fault is something else), or after
# ten tries.
with_mirrors() {
  local out try code moved follow
  out=$(mktemp)
  for ((try = 1; try <= 10; try++)); do
    code=0
    # English messages, whatever the locale: the mirror is read from them.
    # Into a file, which tail copies on as it grows. Not through a pipe to
    # tee: pacman's key handling starts gpg-agent, which keeps the pipe open
    # after pacman has ended, and the wait for tee would never end.
    : >"$out"
    tail -n +1 -f "$out" &
    follow=$!
    LC_ALL=C "$@" >"$out" 2>&1 || code=$?
    sleep 0.3
    kill "$follow" 2>/dev/null || true
    wait "$follow" 2>/dev/null || true
    if ((code == 0)); then
      rm -f "$out"
      return 0
    fi
    moved=0
    "$KARCHY_SRC/bin/karchy-mirrors-demote" --in-place <"$out" && moved=1
    if [[ -f $KARCHY_MNT/etc/pacman.conf ]]; then
      "$KARCHY_SRC/bin/karchy-mirrors-demote" --in-place --root "$KARCHY_MNT" <"$out" && moved=1
    fi
    ((moved)) || break
    echo "Trying again with those mirrors last (try $((try + 1)))"
    pacman -Syy || true
    if [[ -x $KARCHY_MNT/usr/bin/pacman ]] && grep -qs '^\[cachyos\]' "$KARCHY_MNT/etc/pacman.conf"; then
      in_target pacman -Syy || true
    fi
  done
  rm -f "$out"
  return "$code"
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
