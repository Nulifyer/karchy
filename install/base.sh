# shellcheck shell=bash
# Base system: repositories, pacstrap and system configuration in the target.
# Sourced by install/karchy-install.

KARCHY_OMARCHY_KEY="40DFB630FF42BCFFB047046CF0134EE680CAC571"
KARCHY_CACHYOS_KEY="882DCFE48E2051D48E2562ABF3B607488DB35A47"
KARCHY_REMOTE_URL=${KARCHY_REMOTE_URL:-https://github.com/Nulifyer/karchy.git}

# Trust the [omarchy] and [cachyos] signing keys in the live environment and
# add the repositories: [cachyos] before Arch's (D-45), [omarchy] after (D-03).
# pacstrap copies this keyring into the target.
base_repos_live() {
  pacman-key --recv-keys "$KARCHY_OMARCHY_KEY" --keyserver hkps://keys.openpgp.org
  pacman-key --lsign-key "$KARCHY_OMARCHY_KEY"
  pacman-key --recv-keys "$KARCHY_CACHYOS_KEY" --keyserver hkps://keyserver.ubuntu.com
  pacman-key --lsign-key "$KARCHY_CACHYOS_KEY"

  # A bootstrap mirror until the cachyos-mirrorlist package is installed.
  if [[ ! -f /etc/pacman.d/cachyos-mirrorlist ]]; then
    # shellcheck disable=SC2016  # pacman expands $arch and $repo
    echo 'Server = https://cdn77.cachyos.org/repo/$arch/$repo' >/etc/pacman.d/cachyos-mirrorlist
  fi
  base_add_repos /etc/pacman.conf
  pacman -Sy
  # The stock ISO has no git; the installer needs it to clone karchy.
  pacman -S --noconfirm --needed git
}

base_packages() {
  local -a packages
  mapfile -t packages < <(grep -vE '^\s*(#|$)' "$KARCHY_SRC/install/packages/base.txt")
  case "$(cpu_vendor)" in
    AuthenticAMD) packages+=(amd-ucode) ;;
    GenuineIntel) packages+=(intel-ucode) ;;
  esac
  if has_nvidia; then
    packages+=(linux-cachyos-nvidia-open linux-cachyos-lts-nvidia-open nvidia-utils)
  fi
  printf '%s\n' "${packages[@]}"
}

base_pacstrap() {
  local -a packages
  mapfile -t packages < <(base_packages)
  pacstrap "$KARCHY_MNT" --noconfirm "${packages[@]}"
}

base_fstab() {
  # Mount subvolumes by path only: a subvolid= pin breaks snapshot rollbacks.
  genfstab -U "$KARCHY_MNT" | sed -E 's/,?subvolid=[0-9]+//' >"$KARCHY_MNT/etc/fstab"
}

base_repos_target() {
  base_add_repos "$KARCHY_MNT/etc/pacman.conf"
}

# Insert [cachyos] just before Arch's [core] and append [omarchy] at the end.
base_add_repos() {
  local conf="$1"
  if ! grep -q '^\[cachyos\]' "$conf"; then
    awk -v block="$KARCHY_SRC/system/pacman/repo-cachyos.conf" '
      /^\[core\]/ && !done { while ((getline line < block) > 0) print line; done = 1 }
      { print }
    ' "$conf" >"$conf.karchy" && mv "$conf.karchy" "$conf"
  fi
  if ! grep -q '^\[omarchy\]' "$conf"; then
    cat "$KARCHY_SRC/system/pacman/repo-omarchy.conf" >>"$conf"
  fi
  grep -q '^\[cachyos\]' "$conf" && grep -q '^\[omarchy\]' "$conf"
}

base_locale() {
  sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' "$KARCHY_MNT/etc/locale.gen"
  in_target locale-gen
  echo "LANG=en_US.UTF-8" >"$KARCHY_MNT/etc/locale.conf"
  echo "KEYMAP=$KARCHY_KEYMAP" >"$KARCHY_MNT/etc/vconsole.conf"
  in_target ln -sf "/usr/share/zoneinfo/$KARCHY_TIMEZONE" /etc/localtime
  in_target hwclock --systohc
  echo "$KARCHY_HOSTNAME" >"$KARCHY_MNT/etc/hostname"
  printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 %s\n' "$KARCHY_HOSTNAME" >"$KARCHY_MNT/etc/hosts"
}

base_user() {
  in_target useradd --create-home --groups wheel --shell /usr/bin/fish "$KARCHY_USER"
  printf '%s:%s\n' "$KARCHY_USER" "$KARCHY_PASSWORD" | in_target chpasswd
  in_target passwd --lock root

  install -m 0440 "$KARCHY_SRC/system/sudoers.d/karchy" "$KARCHY_MNT/etc/sudoers.d/karchy"
  in_target visudo -cf /etc/sudoers.d/karchy
}

base_system_files() {
  install -Dm 0644 "$KARCHY_SRC/system/mkinitcpio.conf.d/karchy.conf" "$KARCHY_MNT/etc/mkinitcpio.conf.d/karchy.conf"
  install -Dm 0644 "$KARCHY_SRC/system/systemd/tmp.mount.d/karchy.conf" "$KARCHY_MNT/etc/systemd/system/tmp.mount.d/karchy.conf"
  install -Dm 0644 "$KARCHY_SRC/system/snapper/root" "$KARCHY_MNT/etc/snapper/config-templates/karchy"

  # Non-secret install answers, for setup steps that run later.
  install -d -m 0755 "$KARCHY_MNT/etc/karchy"
  {
    printf 'KARCHY_USER=%q\n' "$KARCHY_USER"
    printf 'KARCHY_BEES=%q\n' "$KARCHY_BEES"
    printf 'KARCHY_INSTALLED=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$KARCHY_MNT/etc/karchy/install.conf"
}

# Limine with systemd-based unlock (D-12): rd.luks.uuid + sd-encrypt, zswap on (D-10).
base_bootloader() {
  local cmdline
  cmdline="rw rootflags=subvol=/@ rd.luks.uuid=$KARCHY_LUKS_UUID rd.luks.options=discard"
  cmdline+=" root=/dev/mapper/$KARCHY_ROOT_MAPPER zswap.enabled=1 zswap.compressor=zstd"
  cat >"$KARCHY_MNT/etc/default/limine" <<EOF
ESP_PATH="/boot"
KERNEL_CMDLINE[default]="$cmdline"
BOOT_ORDER="*, *lts, *fallback, Snapshots"
EOF
  in_target limine-install --fallback
  in_target limine-update
}

base_snapper() {
  in_target snapper --no-dbus -c root create-config --template karchy /
}

base_services() {
  in_target systemctl enable NetworkManager.service systemd-resolved.service systemd-timesyncd.service \
    fstrim.timer snapper-cleanup.timer limine-snapper-sync.service
}

# Clone the karchy checkout into the user's home ($OMARCHY_PATH, D-06).
base_checkout() {
  local target="/home/$KARCHY_USER/.local/share/karchy"
  install -d "$KARCHY_MNT/home/$KARCHY_USER/.local/share"
  # The source can be a checkout owned by another user (a VM share).
  git -c safe.directory='*' clone --quiet "$KARCHY_SRC" "$KARCHY_MNT$target"
  git -C "$KARCHY_MNT$target" remote set-url origin "$KARCHY_REMOTE_URL"
  in_target chown -R "$KARCHY_USER:$KARCHY_USER" "/home/$KARCHY_USER/.local"
}

base_git_identity() {
  [[ -n $KARCHY_FULL_NAME || -n $KARCHY_EMAIL ]] || return 0
  [[ -n $KARCHY_FULL_NAME ]] && as_user git config --global user.name "$KARCHY_FULL_NAME"
  [[ -n $KARCHY_EMAIL ]] && as_user git config --global user.email "$KARCHY_EMAIL"
  return 0
}

# arch-chroot bind-mounts resolv.conf while it runs, so link it last, from outside.
base_resolved_link() {
  ln -sf /run/systemd/resolve/stub-resolv.conf "$KARCHY_MNT/etc/resolv.conf"
}
