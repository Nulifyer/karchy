# shellcheck shell=bash disable=SC2034  # sets KARCHY_* variables used by the other install files
# The installer form: collects every answer up front, then the install runs
# unattended. Sourced by install/karchy-install. Writes KARCHY_* variables.

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
  choice=$(gum choose --header "Install karchy on which disk? It will be erased." "${rows[@]}") || exit 1
  KARCHY_DISK=$(awk '{ print $1 }' <<<"$choice")

  echo "Current contents of $KARCHY_DISK:"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$KARCHY_DISK"
  local typed
  typed=$(gum input --header "Type $KARCHY_DISK to erase it and continue") || exit 1
  [[ $typed == "$KARCHY_DISK" ]] || die "disk not confirmed"
}

form_password() {
  local first second
  while true; do
    first=$(gum input --password --header "Password (unlocks the disk and logs you in)") || exit 1
    second=$(gum input --password --header "Confirm password") || exit 1
    if [[ -z $first ]]; then
      echo "The password can't be empty."
    elif [[ $first != "$second" ]]; then
      echo "The passwords don't match."
    else
      break
    fi
  done
  KARCHY_PASSWORD="$first"
}

form_run() {
  form_require_gum
  gum style --border rounded --padding "0 2" "karchy installer" "Answer a few questions; the rest is automatic."

  form_disk
  KARCHY_KEYMAP=$(localectl list-keymaps | gum filter --value "us" --header "Keyboard layout") || exit 1

  while true; do
    KARCHY_USER=$(gum input --header "Username" --placeholder "lowercase letters, digits, - or _") || exit 1
    [[ $KARCHY_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && break
    echo "Use lowercase letters, digits, - or _, starting with a letter."
  done

  form_password
  KARCHY_FULL_NAME=$(gum input --header "Full name (for git, optional)") || exit 1
  KARCHY_EMAIL=$(gum input --header "Email (for git, optional)") || exit 1

  while true; do
    KARCHY_HOSTNAME=$(gum input --header "Computer name" --value "karchy") || exit 1
    [[ $KARCHY_HOSTNAME =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] && break
    echo "Use letters, digits and -."
  done

  KARCHY_TIMEZONE=$(timedatectl list-timezones | gum filter --header "Timezone") || exit 1

  KARCHY_BEES=no
  if gum confirm --default=false "Enable bees background deduplication? (optional, can use some CPU and RAM)"; then
    KARCHY_BEES=yes
  fi
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
  KARCHY_KEYMAP=${KARCHY_KEYMAP:-us}
  KARCHY_BEES=${KARCHY_BEES:-no}
  KARCHY_FULL_NAME=${KARCHY_FULL_NAME:-}
  KARCHY_EMAIL=${KARCHY_EMAIL:-}
}
