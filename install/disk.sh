# shellcheck shell=bash
# Disk layout (D-09, D-10): 4 GiB ESP, LUKS2 unless the form's answer was no
# encryption (D-130), btrfs subvolumes, swap file. Sourced by
# install/karchy-install.
#
# KARCHY_ROOT_PART is the system disk's second partition; KARCHY_ROOT_DEV is
# the device the filesystem is on: the opened LUKS volume, or the partition
# itself without encryption.

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
  # Partition 2's type says what it holds: LUKS, or a Linux filesystem.
  local root_type=8309
  install_encrypted || root_type=8300
  sgdisk \
    --new=1:0:+4G --typecode=1:ef00 --change-name=1:EFI \
    --new=2:0:0 --typecode=2:"$root_type" --change-name=2:karchy \
    "$KARCHY_DISK"
  partprobe "$KARCHY_DISK"
  udevadm settle

  KARCHY_ESP=$(partition "$KARCHY_DISK" 1)
  KARCHY_ROOT_PART=$(partition "$KARCHY_DISK" 2)
  [[ -b $KARCHY_ESP && -b $KARCHY_ROOT_PART ]] || return 1
  # New partitions at the old ones' places still hold the old ones' first
  # blocks. A LUKS header left at the start of partition 2 outlives mkfs.btrfs
  # (whose own superblock sits further in), and the partition then reads as
  # an encrypted volume that can't be mounted.
  wipefs --all --force "$KARCHY_ESP" "$KARCHY_ROOT_PART"
  KARCHY_ROOT_DEV=$KARCHY_ROOT_PART
  KARCHY_LUKS_UUID=""
  KARCHY_MAPPERS=()
}

# Make a partition a LUKS2 volume that the install password opens, and open
# it as luks-<its UUID> (the name udisks and systemd use too). Sets
# LUKS_UUID and LUKS_MAPPER. The system disk and the other disks chosen in
# the form (disk_data_encrypt) are made the same way.
luks_format_open() {
  local part="$1" label="$2"
  printf '%s' "$KARCHY_PASSWORD" |
    cryptsetup luksFormat --type luks2 --batch-mode --label "$label" --key-file=- "$part"
  LUKS_UUID=$(cryptsetup luksUUID "$part")
  LUKS_MAPPER="luks-$LUKS_UUID"
  # TRIM passes through, and dm-crypt's extra work queues are off (they only
  # add latency on SSDs; Arch Wiki, dm-crypt/Specialties). --persistent keeps
  # both in the LUKS2 header, so every later unlock uses them.
  printf '%s' "$KARCHY_PASSWORD" |
    cryptsetup open --key-file=- --allow-discards --perf-no_read_workqueue --perf-no_write_workqueue \
      --persistent "$part" "$LUKS_MAPPER"
  KARCHY_MAPPERS+=("$LUKS_MAPPER")
}

disk_encrypt() {
  luks_format_open "$KARCHY_ROOT_PART" karchy
  KARCHY_LUKS_UUID=$LUKS_UUID
  KARCHY_ROOT_DEV="/dev/mapper/$LUKS_MAPPER"
}

# The other internal disks chosen in the form (KARCHY_ENCRYPT_DISKS, D-132):
# each is erased and becomes one LUKS2 volume with a btrfs filesystem, labelled
# data, data2, ... It has two keys. The install password, so the disk can
# always be opened by hand (recovery, another computer). And a random key
# file in /etc/cryptsetup-keys.d on the encrypted system disk (root only),
# which /etc/crypttab names: once the system disk is open, systemd opens
# these with no second prompt. nofail: a boot never waits for a disk that was
# taken out. base_data_disks then gives each its fstab line and scrub timer,
# as for any data disk (D-24).
disk_data_encrypt() {
  local disk part label key uid gid number=0
  uid=$(in_target id -u "$KARCHY_USER")
  gid=$(in_target id -g "$KARCHY_USER")
  install -d -m 0700 "$KARCHY_MNT/etc/cryptsetup-keys.d"
  for disk in $KARCHY_ENCRYPT_DISKS; do
    number=$((number + 1))
    label=data
    ((number == 1)) || label="data$number"
    wipefs --all --force "$disk"
    sgdisk --zap-all "$disk"
    sgdisk --new=1:0:0 --typecode=1:8309 --change-name=1:"$label" "$disk"
    partprobe "$disk"
    udevadm settle
    part=$(partition "$disk" 1)
    [[ -b $part ]] || return 1
    wipefs --all --force "$part"

    luks_format_open "$part" "$label"
    key="/etc/cryptsetup-keys.d/$LUKS_MAPPER.key"
    (umask 077 && head -c 64 /dev/urandom >"$KARCHY_MNT$key")
    chmod 0400 "$KARCHY_MNT$key"
    # The key is 64 random bytes, so it needs no slow key derivation: PBKDF2
    # at its minimum opens the disk at boot in milliseconds, where the
    # password's Argon2 takes seconds and a gigabyte of memory.
    printf '%s' "$KARCHY_PASSWORD" |
      cryptsetup luksAddKey --batch-mode --key-file=- --pbkdf pbkdf2 --pbkdf-force-iterations 1000 \
        "$part" "$KARCHY_MNT$key"
    cryptsetup open --test-passphrase --key-file "$KARCHY_MNT$key" "$part"
    printf '%s UUID=%s %s luks,nofail\n' "$LUKS_MAPPER" "$LUKS_UUID" "$key" >>"$KARCHY_MNT/etc/crypttab"

    mkfs.btrfs --force --label "$label" "/dev/mapper/$LUKS_MAPPER"
    # A new, empty disk for the person installing: theirs to write to.
    local mount
    mount=$(mktemp -d)
    mount "/dev/mapper/$LUKS_MAPPER" "$mount"
    chown "$uid:$gid" "$mount"
    umount "$mount"
    rmdir "$mount"
    udevadm settle
    log "$disk is erased and encrypted; it opens at boot with the system disk"
  done
}

disk_filesystems() {
  mkfs.fat -F 32 -n EFI "$KARCHY_ESP"
  mkfs.btrfs --force --label karchy "$KARCHY_ROOT_DEV"

  mount "$KARCHY_ROOT_DEV" "$KARCHY_MNT"
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
    # The swap file isn't compressed either way (mkswapfile makes it NOCOW, and
    # btrfs shares compression across the filesystem's mounts); noatime alone
    # just keeps this mount plain.
    if [[ $name == "@swap" ]]; then
      options="noatime,subvol=/$name"
    fi
    mkdir -p "$target"
    mount -o "$options" "$KARCHY_ROOT_DEV" "$target"
  done
  # New subvolumes are 0755; these two need their usual modes.
  chmod 0700 "$KARCHY_MNT/root"
  chmod 1777 "$KARCHY_MNT/var/tmp" 2>/dev/null || true
  mkdir -p "$KARCHY_MNT/boot"
  mount -o fmask=0077,dmask=0077 "$KARCHY_ESP" "$KARCHY_MNT/boot"
}

# Swap file sized to RAM so laptop hibernation stays possible (D-10, D-32).
disk_swapfile() {
  btrfs filesystem mkswapfile --size "$(ram_gib)g" --uuid clear "$KARCHY_MNT/swap/swapfile"
  swapon "$KARCHY_MNT/swap/swapfile"
}
