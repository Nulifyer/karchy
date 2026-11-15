# shellcheck shell=bash
# Base system: repositories, pacstrap and system configuration in the target.
# Sourced by install/karchy-install.

KARCHY_OMARCHY_KEY="40DFB630FF42BCFFB047046CF0134EE680CAC571"
KARCHY_CACHYOS_KEY="882DCFE48E2051D48E2562ABF3B607488DB35A47"
# karchy's own packages (D-51): one repository per release channel (D-61),
# at $KARCHY_REPO_SERVER/repo-<channel>. A VM test points this at a local
# build: tools/vm repo serves packaging/build's out/ folder to the guest.
KARCHY_REPO_SERVER=${KARCHY_REPO_SERVER:-https://github.com/Nulifyer/karchy/releases/download}
KARCHY_REPO_SIGLEVEL=${KARCHY_REPO_SIGLEVEL:-Required}

# Trust the [omarchy] and [cachyos] signing keys in the live environment and
# add the repositories: [cachyos] before Arch's (D-45), [omarchy] and [karchy]
# after (D-03, D-51).
# pacstrap copies this keyring into the target.
base_repos_live() {
  pacman-key --recv-keys "$KARCHY_OMARCHY_KEY" --keyserver hkps://keys.openpgp.org
  pacman-key --lsign-key "$KARCHY_OMARCHY_KEY"
  pacman-key --recv-keys "$KARCHY_CACHYOS_KEY" --keyserver hkps://keyserver.ubuntu.com
  pacman-key --lsign-key "$KARCHY_CACHYOS_KEY"
  # karchy's own signing key comes with the installer (D-61), no keyserver.
  local keyring="$KARCHY_SRC/packaging/keyring" fpr
  if [[ -f $keyring/karchy.gpg ]]; then
    pacman-key --add "$keyring/karchy.gpg"
    while IFS=: read -r fpr _; do
      [[ -n $fpr ]] && pacman-key --lsign-key "$fpr"
    done <"$keyring/karchy-trusted"
  fi

  # A bootstrap mirror until the cachyos-mirrorlist package is installed.
  if [[ ! -f /etc/pacman.d/cachyos-mirrorlist ]]; then
    # shellcheck disable=SC2016  # pacman expands $arch and $repo
    echo 'Server = https://cdn77.cachyos.org/repo/$arch/$repo' >/etc/pacman.d/cachyos-mirrorlist
  fi
  base_add_repos /etc/pacman.conf
  pacman -Sy
  # karchy-disk-fstab (data disks) reads lsblk's JSON with jq.
  pacman -S --noconfirm --needed jq
}

base_packages() {
  local -a packages
  mapfile -t packages < <(grep -vE '^\s*(#|$)' "$KARCHY_SRC/install/packages/base.txt")
  case "$(cpu_vendor)" in
    AuthenticAMD) packages+=(amd-ucode) ;;
    GenuineIntel) packages+=(intel-ucode) ;;
  esac
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

# Insert [cachyos] just before Arch's [core]; append [omarchy] and [karchy].
# Also tune pacman's options: 10 parallel downloads (Arch ships 5), color,
# the detailed package table and the candy progress bar.
base_add_repos() {
  local conf="$1"
  sed -i -E \
    -e 's/^#?Color$/Color\nILoveCandy/' \
    -e 's/^#?VerbosePkgLists$/VerbosePkgLists/' \
    -e 's/^#?ParallelDownloads *=.*/ParallelDownloads = 10/' "$conf"
  # Applied once: a second run would add a second ILoveCandy.
  awk '!(/^ILoveCandy$/ && seen++)' "$conf" >"$conf.karchy" && mv "$conf.karchy" "$conf"
  if ! grep -q '^\[cachyos\]' "$conf"; then
    awk -v block="$KARCHY_SRC/system/pacman/repo-cachyos.conf" '
      /^\[core\]/ && !done { while ((getline line < block) > 0) print line; done = 1 }
      { print }
    ' "$conf" >"$conf.karchy" && mv "$conf.karchy" "$conf"
  fi
  if ! grep -q '^\[omarchy\]' "$conf"; then
    cat "$KARCHY_SRC/system/pacman/repo-omarchy.conf" >>"$conf"
  fi
  # The channel's server lives in its own file, which karchy-channel rewrites.
  local server_file
  server_file="$(dirname "$conf")/pacman.d/karchy-server"
  printf '# karchy release channel (D-61). Change it with: karchy channel set <stable|rc|nightly>\n# channel=%s\nServer = %s/repo-%s\n' \
    "$KARCHY_CHANNEL" "$KARCHY_REPO_SERVER" "$KARCHY_CHANNEL" >"$server_file"
  if ! grep -q '^\[karchy\]' "$conf"; then
    printf '\n# karchy (D-51): karchy'"'"'s own packages, built from Nulifyer/karchy.\n[karchy]\nSigLevel = %s\nInclude = /etc/pacman.d/karchy-server\n' \
      "$KARCHY_REPO_SIGLEVEL" >>"$conf"
  fi
  grep -q '^\[cachyos\]' "$conf" && grep -q '^\[omarchy\]' "$conf" && grep -q '^\[karchy\]' "$conf"
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
  # The sudo policy comes from karchy-settings, pacstrapped with the base.
  in_target visudo -cf /etc/sudoers.d/karchy
  # The login keyring's key (D-57), before any snapshot is taken.
  in_target /usr/lib/karchy/keyring-key "$(in_target id -u "$KARCHY_USER")"
}

# Internal data disks already in the machine get mounts at /mnt/<label> (D-24),
# by the same rules the login check uses for disks added later.
base_data_disks() {
  local uid gid device mount line
  uid=$(in_target id -u "$KARCHY_USER")
  gid=$(in_target id -g "$KARCHY_USER")
  while IFS=$'\t' read -r device _ _ _ mount; do
    line=$(KARCHY_FSTAB="$KARCHY_MNT/etc/fstab" "$KARCHY_SRC/bin/karchy-disk-fstab" line "$device" "$uid" "$gid")
    mkdir -p "$KARCHY_MNT$mount"
    echo "$line" >>"$KARCHY_MNT/etc/fstab"
    log "data disk $device mounts at $mount"
  done < <(KARCHY_FSTAB="$KARCHY_MNT/etc/fstab" "$KARCHY_SRC/bin/karchy-disk-fstab" list)
}

# Non-secret install answers, for setup steps that run later. System files
# (mkinitcpio, /tmp, the snapper template) come from karchy-settings.
base_install_conf() {
  install -d -m 0755 "$KARCHY_MNT/etc/karchy"
  {
    printf 'KARCHY_USER=%q\n' "$KARCHY_USER"
    printf 'KARCHY_BEES=%q\n' "$KARCHY_BEES"
    printf 'KARCHY_SECUREBOOT=%q\n' "$KARCHY_SECUREBOOT"
    printf 'KARCHY_CHANNEL=%q\n' "$KARCHY_CHANNEL"
    printf 'KARCHY_INSTALLED=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$KARCHY_MNT/etc/karchy/install.conf"
}

# Limine with systemd-based unlock (D-12): rd.luks.uuid + sd-encrypt, zswap on (D-10).
base_bootloader() {
  local cmdline resume_uuid resume_offset
  # Hibernation resumes from the swap file: the btrfs filesystem's UUID and the
  # file's offset inside it, read by the systemd initramfs (D-32).
  resume_uuid=$(findmnt -no UUID "$KARCHY_MNT")
  resume_offset=$(btrfs inspect-internal map-swapfile -r "$KARCHY_MNT/swap/swapfile")
  cmdline="rw rootflags=subvol=/@ rd.luks.uuid=$KARCHY_LUKS_UUID rd.luks.options=discard"
  cmdline+=" root=/dev/mapper/$KARCHY_ROOT_MAPPER zswap.enabled=1 zswap.compressor=zstd"
  cmdline+=" resume=UUID=$resume_uuid resume_offset=$resume_offset"
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
    fstrim.timer snapper-cleanup.timer limine-snapper-sync.service btrfs-scrub@-.timer
}

# Secure Boot (D-31), chosen in the form when the firmware is in Setup Mode.
# The installer's last step, and enrolling is its last action: until the keys
# are enrolled the firmware stays in Setup Mode, so a failure anywhere before
# leaves a machine that still boots (and boots the install ISO to retry).
# karchy-secureboot (karchy) does the enrolling.
# sbctl's keys are enrolled with Microsoft's (GPU option ROMs, dual boot).
# Kernels are not signed: Limine checks each file's BLAKE2 hash from
# limine.conf, and the config's own hash is enrolled into the signed Limine
# binary. limine's hooks re-enroll and re-sign after every kernel, initramfs
# or snapshot change; karchy-settings' 95-karchy-limine-fallback hook keeps the
# firmware's fallback copy identical to the enrolled, signed binary.
base_secureboot() {
  [[ $KARCHY_SECUREBOOT == "yes" ]] || return 0
  in_target pacman -S --needed --noconfirm sbctl
  in_target sbctl create-keys
  printf 'ENABLE_VERIFICATION=yes\nENABLE_ENROLL_LIMINE_CONFIG=yes\n' >>"$KARCHY_MNT/etc/default/limine"
  # Signs with the new keys; karchy's hook fails it unless both binaries carry
  # limine.conf's hash and are signed.
  in_target limine-update
  local efi
  for efi in /boot/EFI/limine/limine_x64.efi /boot/EFI/BOOT/BOOTX64.EFI; do
    in_target sbctl verify "$efi" | grep -q 'is signed' || die "$efi is not signed"
  done
  in_target karchy-secureboot enroll
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
