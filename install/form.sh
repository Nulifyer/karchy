# shellcheck shell=bash disable=SC2034  # sets KARCHY_* variables used by the other install files
# The installer form: collects every answer up front, then the install runs
# unattended. Sourced by install/karchy-install. Writes KARCHY_* variables.

# Esc or Ctrl-C at a question that asks for an answer ends the installer
# before anything changes; at a yes/no question Esc means No (gum can't tell
# them apart), and Ctrl-C ends it. The final "Erase and install" defaults to No.
form_cancel() {
  ui_line
  ui_line "Install cancelled. Nothing was changed; run karchy-install to start again."
  exit 1
}

# What went wrong with an answer, above the question when it is asked again.
form_retry() {
  ui_line "$1" "$UI_RED"
}

# A yes/no question: 0 yes, 1 no. gum exits 130 on Ctrl-C, which cancels.
form_yes_no() {
  local code=0
  gum confirm "$@" || code=$?
  ((code == 130)) && form_cancel
  return "$code"
}

# Pick one line from stdin with gum filter, again until something matches.
# Runs in a subshell, so a cancel returns 1 and the caller cancels.
form_pick() {
  local header="$1" value="$2" list choice
  list=$(cat)
  while true; do
    choice=$(gum filter --header "$header" --value "$value" <<<"$list") || return 1
    [[ -n $choice ]] && { printf '%s' "$choice"; return; }
    form_retry "Pick one from the list (type to narrow it down)."
  done
}

form_require_gum() {
  command -v gum >/dev/null && return
  log "installing gum for the installer form"
  pacman -Sy --noconfirm --needed gum >>"$KARCHY_INSTALL_LOG" 2>&1 || die "could not install gum"
}

form_disk() {
  # Never offer the USB stick the installer booted from.
  local boot_disk="" boot_part
  boot_part=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
  if [[ -n $boot_part ]]; then
    boot_disk=$(lsblk -npo PKNAME "$boot_part" 2>/dev/null | head -n 1)
  fi
  local -a rows
  mapfile -t rows < <(lsblk -dpno NAME,SIZE,MODEL,TYPE |
    awk -v skip="$boot_disk" '$NF == "disk" && $1 != skip { $NF = ""; print }')
  ((${#rows[@]})) || die "no installable disks found"
  local choice
  choice=$(gum choose --header "Install karchy on which disk? It will be erased." "${rows[@]}") || form_cancel
  KARCHY_DISK=$(awk '{ print $1 }' <<<"$choice")

  # What is on it now, so the wrong disk is caught here.
  local line typed
  ui_line "On $KARCHY_DISK now:"
  while IFS= read -r line; do
    ui_line "$line" "$UI_DIM"
  done < <(lsblk -o NAME,SIZE,FSTYPE,LABEL "$KARCHY_DISK")
  ui_line
  while true; do
    typed=$(gum input --header "Type $KARCHY_DISK to choose it. Nothing is erased yet." --placeholder "$KARCHY_DISK") || form_cancel
    [[ $typed == "$KARCHY_DISK" ]] && break
    form_retry "That isn't $KARCHY_DISK. Type it exactly, or press Esc to stop."
  done
  form_screen
}

form_password() {
  local first second
  while true; do
    first=$(gum input --password --header "Password (unlocks the disk and logs you in)") || form_cancel
    second=$(gum input --password --header "Confirm password") || form_cancel
    if [[ -z $first ]]; then
      form_retry "The password can't be empty."
    elif [[ $first != "$second" ]]; then
      form_retry "The passwords don't match."
    else
      break
    fi
  done
  KARCHY_PASSWORD="$first"
}

# The form's screen: the header and the answers given so far. Drawn again
# after each answer, so a question never scrolls the earlier ones away and a
# retry message doesn't outlive its question.
form_screen() {
  ui_header "Install karchy" 14
  [[ $KARCHY_UI == tui ]] || return 0
  ui_line "Esc stops the installer. Nothing is erased until you confirm at the end." "$UI_DIM"
  ui_line
  [[ -z ${KARCHY_KEYMAP:-} ]] || ui_field "Keyboard" "$KARCHY_KEYMAP"
  [[ -z ${KARCHY_DISK:-} ]] || ui_field "Disk" "$KARCHY_DISK"
  [[ -z ${KARCHY_USER:-} ]] || ui_field "User" "$KARCHY_USER"
  [[ -z ${KARCHY_PASSWORD:-} ]] || ui_field "Password" "set"
  [[ -z ${KARCHY_HOSTNAME:-} ]] || ui_field "Computer" "$KARCHY_HOSTNAME"
  [[ -z ${KARCHY_TIMEZONE:-} ]] || ui_field "Timezone" "$KARCHY_TIMEZONE"
  [[ -z ${KARCHY_CHANNEL:-} ]] || ui_field "Updates" "$KARCHY_CHANNEL channel"
  [[ -z ${KARCHY_KEYMAP:-} ]] || ui_line
}

form_run() {
  form_require_gum
  # An unattended config's variables don't belong in a form's first screen.
  unset KARCHY_KEYMAP KARCHY_DISK KARCHY_USER KARCHY_PASSWORD KARCHY_HOSTNAME KARCHY_TIMEZONE KARCHY_CHANNEL
  form_screen

  # The layout first: every answer after it, the disk's name and the password
  # that unlocks the disk at boot, is typed with it.
  KARCHY_KEYMAP=$(localectl list-keymaps | form_pick "Keyboard layout" "us") || form_cancel
  loadkeys "$KARCHY_KEYMAP" 2>/dev/null || true
  form_screen
  form_disk

  while true; do
    KARCHY_USER=$(gum input --header "Username" --placeholder "lowercase letters, digits, - or _") || form_cancel
    if ! [[ $KARCHY_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
      form_retry "Use lowercase letters, digits, - or _, starting with a letter."
    elif form_reserved_user "$KARCHY_USER"; then
      form_retry "$KARCHY_USER is a name the system uses itself. Pick another."
    else
      break
    fi
  done
  form_screen

  form_password
  form_screen
  KARCHY_FULL_NAME=$(gum input --header "Full name (for git, optional)") || form_cancel
  while true; do
    KARCHY_EMAIL=$(gum input --header "Email (for git, optional)" --value "${KARCHY_EMAIL:-}") || form_cancel
    [[ -z $KARCHY_EMAIL || $KARCHY_EMAIL =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] && break
    form_retry "That doesn't look like an email address (name@example.com). Leave it empty to skip."
  done

  # The default shows as a placeholder, which typing replaces; a prefilled
  # value would be added to ("karchykarchy"). Only a name that was typed and
  # refused comes back in the field, to be corrected.
  KARCHY_HOSTNAME=""
  while true; do
    KARCHY_HOSTNAME=$(gum input --header "Computer name (Enter keeps karchy)" --placeholder "karchy" \
      --value "$KARCHY_HOSTNAME") || form_cancel
    KARCHY_HOSTNAME=${KARCHY_HOSTNAME:-karchy}
    [[ $KARCHY_HOSTNAME =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] && break
    form_retry "Use letters, digits and -."
  done
  form_screen

  KARCHY_TIMEZONE=$(timedatectl list-timezones | form_pick "Timezone" "") || form_cancel
  form_screen

  # Only channels with a release: before karchy's first release, stable has
  # none, and installing from it would fail after the disk is erased.
  local -a channels=()
  local channel header="Release channel for karchy's own updates (Settings can change it later)"
  for channel in stable rc nightly; do
    channel_published "$channel" && channels+=("$channel")
  done
  ((${#channels[@]} > 0)) || die "karchy's package repositories at $KARCHY_REPO_SERVER can't be reached; nothing was changed. Check the network and run karchy-install again."
  KARCHY_CHANNEL=$(gum choose --header "$header" --selected "${channels[0]}" "${channels[@]}") || form_cancel
  form_screen

  KARCHY_SECUREBOOT=no
  if firmware_setup_mode; then
    if form_yes_no --default=true "Set up Secure Boot? The firmware is in Setup Mode, so karchy can enroll its own keys (with Microsoft's, for GPU firmware and dual boot)."; then
      KARCHY_SECUREBOOT=yes
    fi
  fi

  KARCHY_BEES=yes
  if ! form_yes_no --default=true "Deduplicate the disk in the background (bees)? Saves space with worktrees, caches and copied VM disks."; then
    KARCHY_BEES=no
  fi
}

# Names the installed system creates for itself (root, service users, groups),
# which useradd would refuse only after the disk is erased. The live system
# has most of them; the rest come from karchy's packages.
form_reserved_user() {
  local name="$1"
  getent passwd "$name" >/dev/null || getent group "$name" >/dev/null && return 0
  case "$name" in
    root | bin | daemon | mail | ftp | http | nobody | dbus | git | avahi | polkitd | greeter | rtkit | \
      colord | geoclue | usbmux | uuidd | tss | alpm | cups | wheel | adm | sys | users | input | video | \
      audio | storage | optical | lp | kvm | render | docker | libvirt | systemd-* | nm-openvpn | flatpak) return 0 ;;
  esac
  return 1
}

# The last question, after the summary: nothing is written before it.
# Whether a release channel has a published repository (its database).
channel_published() {
  curl -fsL --max-time 20 -o /dev/null "$KARCHY_REPO_SERVER/repo-$1/karchy.db"
}

form_confirm() {
  form_yes_no --default=false --affirmative "Erase and install" --negative "Stop" \
    "Erase $KARCHY_DISK and install karchy?" || form_cancel
}

# Load answers from a file instead of asking (unattended installs and tests).
# The file sets the same KARCHY_* variables; it must be readable only by root.
form_load() {
  local file="$1"
  [[ -f $file ]] || die "config file not found: $file"
  # shellcheck source=/dev/null
  source "$file"
  local var
  for var in KARCHY_DISK KARCHY_USER KARCHY_PASSWORD KARCHY_HOSTNAME KARCHY_TIMEZONE; do
    [[ -n ${!var:-} ]] || die "$file does not set $var"
  done
  [[ -b $KARCHY_DISK ]] || die "$file names $KARCHY_DISK as the disk, which is not a disk on this computer (lsblk lists them); nothing was changed."
  KARCHY_KEYMAP=${KARCHY_KEYMAP:-us}
  KARCHY_BEES=${KARCHY_BEES:-yes}
  # dev: a local packaging/build, for VM tests only.
  KARCHY_CHANNEL=${KARCHY_CHANNEL:-stable}
  [[ $KARCHY_CHANNEL =~ ^(stable|rc|nightly|dev)$ ]] || die "KARCHY_CHANNEL must be stable, rc or nightly"
  channel_published "$KARCHY_CHANNEL" ||
    die "The $KARCHY_CHANNEL channel has no release at $KARCHY_REPO_SERVER/repo-$KARCHY_CHANNEL (or it can't be reached); nothing was changed. Set KARCHY_CHANNEL to a channel with a release."
  # auto: set up Secure Boot when the firmware is in Setup Mode.
  KARCHY_SECUREBOOT=${KARCHY_SECUREBOOT:-auto}
  if [[ $KARCHY_SECUREBOOT == "auto" ]]; then
    KARCHY_SECUREBOOT=no
    firmware_setup_mode && KARCHY_SECUREBOOT=yes
  elif [[ $KARCHY_SECUREBOOT == "yes" ]] && ! firmware_setup_mode; then
    die "KARCHY_SECUREBOOT=yes, but the firmware is not in Setup Mode: clear its Secure Boot keys first, or use auto"
  fi
  KARCHY_FULL_NAME=${KARCHY_FULL_NAME:-}
  KARCHY_EMAIL=${KARCHY_EMAIL:-}
}
