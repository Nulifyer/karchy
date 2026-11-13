# shellcheck shell=bash
# Disk layout (D-09, D-10): 4 GiB ESP, LUKS2, btrfs subvolumes, swap file.
# Sourced by install/karchy-install.

KARCHY_SUBVOLUMES=(
  "@:/"
  "@home:/home"
  "@root:/root"
  "@srv:/srv"
  "@cache:/var/cache"
  "@log:/var/log"
  "@tmp:/var/tmp"
  "@swap:/swap"
)
KARCHY_BTRFS_OPTIONS="noatime,compress=zstd:1"

disk_partition() {
  # Undo anything a previous attempt left behind on the target.
  swapoff -a 2>/dev/null || true
  umount -R "$KARCHY_MNT" 2>/dev/null || true
  local mapper
  for mapper in /dev/mapper/luks-*; do
    [[ -e $mapper ]] && cryptsetup close "${mapper##*/}" 2>/dev/null || true
  done

  wipefs --all --force "$KARCHY_DISK"
  sgdisk --zap-all "$KARCHY_DISK"
  sgdisk \
    --new=1:0:+4G --typecode=1:ef00 --change-name=1:EFI \
    --new=2:0:0 --typecode=2:8309 --change-name=2:karchy \
    "$KARCHY_DISK"
  partprobe "$KARCHY_DISK"
  udevadm settle

  KARCHY_ESP=$(partition "$KARCHY_DISK" 1)
  KARCHY_LUKS=$(partition "$KARCHY_DISK" 2)
  [[ -b $KARCHY_ESP && -b $KARCHY_LUKS ]] || return 1
}

disk_encrypt() {
  printf '%s' "$KARCHY_PASSWORD" |
    cryptsetup luksFormat --type luks2 --batch-mode --label karchy --key-file=- "$KARCHY_LUKS"
  KARCHY_LUKS_UUID=$(cryptsetup luksUUID "$KARCHY_LUKS")
  KARCHY_ROOT_MAPPER="luks-$KARCHY_LUKS_UUID"
  printf '%s' "$KARCHY_PASSWORD" |
    cryptsetup open --key-file=- --allow-discards "$KARCHY_LUKS" "$KARCHY_ROOT_MAPPER"
}

disk_filesystems() {
  mkfs.fat -F 32 -n EFI "$KARCHY_ESP"
  mkfs.btrfs --force --label karchy "/dev/mapper/$KARCHY_ROOT_MAPPER"

  mount "/dev/mapper/$KARCHY_ROOT_MAPPER" "$KARCHY_MNT"
  local entry
  for entry in "${KARCHY_SUBVOLUMES[@]}"; do
    btrfs subvolume create "$KARCHY_MNT/${entry%%:*}"
  done
  umount "$KARCHY_MNT"
}

disk_mount() {
  local entry name target options
  for entry in "${KARCHY_SUBVOLUMES[@]}"; do
    name=${entry%%:*}
    target="$KARCHY_MNT${entry#*:}"
    options="$KARCHY_BTRFS_OPTIONS,subvol=/$name"
    if [[ $name == "@swap" ]]; then
      options="noatime,subvol=/$name"
    fi
    mkdir -p "$target"
    mount -o "$options" "/dev/mapper/$KARCHY_ROOT_MAPPER" "$target"
  done
  mkdir -p "$KARCHY_MNT/boot"
  mount -o fmask=0077,dmask=0077 "$KARCHY_ESP" "$KARCHY_MNT/boot"
}

# Swap file sized to RAM so laptop hibernation stays possible (D-10, D-32).
disk_swapfile() {
  btrfs filesystem mkswapfile --size "$(ram_gib)g" --uuid clear "$KARCHY_MNT/swap/swapfile"
  swapon "$KARCHY_MNT/swap/swapfile"
}
