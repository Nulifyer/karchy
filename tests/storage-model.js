// Settings › Storage's sums and words. Usage: node tests/storage-model.js "$PWD"
const assert = require("assert")
const M = require(process.argv[2] + "/shell/plugins/settings/StorageModel.js")
const eq = (a, b) => assert.deepStrictEqual(a, b)
const GB = 1e9, MB = 1e6

// Sizes: decimal units, three significant digits, no trailing zeros.
eq(M.bytes(0), "0 B"); eq(M.bytes(999), "999 B"); eq(M.bytes(1000), "1 kB")
eq(M.bytes(1.21e12), "1.21 TB"); eq(M.bytes(819e9), "819 GB"); eq(M.bytes(70.34e9), "70.3 GB")
eq(M.bytes(2.6e9), "2.6 GB"); eq(M.bytes(4e9), "4 GB"); eq(M.bytes(999.6e6), "1 GB"); eq(M.bytes(727e6), "727 MB")
eq(M.bytes(-1), ""); eq(M.bytes("x"), ""); eq(M.bytes(null), "0 B")
eq(M.diskSize(1000204886016), "1 TB"); eq(M.diskSize(42949672960), "43 GB"); eq(M.diskSize(4000787030016), "4 TB")
eq(M.diskSize(500107862016), "500 GB"); eq(M.diskSize(0), "")

// The measured figures. Two files of 10 GB that share everything, stored
// compressed to 4 GB: 20 held, 10 saved by sharing, 6 by compression.
eq(M.figures({ referenced: 20 * GB, uncompressed: 10 * GB, disk: 4 * GB, snapshots: 3 * GB }),
  { files: 20 * GB, stored: 4 * GB, sharing: 10 * GB, overhead: 0, compression: 6 * GB, snapshots: 3 * GB })
// Nothing shared and nothing compressed.
eq(M.figures({ referenced: 5 * GB, uncompressed: 5 * GB, disk: 5 * GB, snapshots: 0 }),
  { files: 5 * GB, stored: 5 * GB, sharing: 0, overhead: 0, compression: 0, snapshots: 0 })
// Partly overwritten extents hold more than the files point at: that is a
// cost, shown apart, and sharing is never negative.
eq(M.figures({ referenced: 4761317261, uncompressed: 5006110605, disk: 5006110605, snapshots: null }),
  { files: 4761317261, stored: 5006110605, sharing: 0, overhead: 244793344, compression: 0, snapshots: null })
// The figures always add up: files = stored + compression + sharing - overhead.
for (const m of [{ referenced: 14138097734, uncompressed: 14007447622, disk: 12220905548, snapshots: 582424066 },
                 { referenced: 100, uncompressed: 300, disk: 200, snapshots: 0 }]) {
  const f = M.figures(m)
  eq(f.files, f.stored + f.compression + f.sharing - f.overhead)
}
// Never a number that was not measured.
eq(M.figures(null), null); eq(M.figures({ uuid: "x", error: "could not be counted" }), null)
eq(M.figures({ referenced: "x", uncompressed: 1, disk: 1 }), null); eq(M.figures({ referenced: -1, uncompressed: 1, disk: 1 }), null)
eq(M.figures({ referenced: 1, uncompressed: 1, disk: 1 }).snapshots, null)
eq(M.figures({ referenced: 1, uncompressed: 1, disk: 1, snapshots: -5 }).snapshots, null)

// The bars share one scale: the longest of the files and the disk.
eq(M.bars({ fsSize: 928 * GB, measured: { referenced: 1210 * GB, uncompressed: 961 * GB, disk: 819 * GB } }),
  { files: 1, stored: 819 / 1210, size: 928 / 1210 })
eq(M.bars({ fsSize: 40 * GB, measured: { referenced: 10 * GB, uncompressed: 10 * GB, disk: 8 * GB } }),
  { files: 0.25, stored: 0.2, size: 1 })
eq(M.bars({ fsSize: 40 * GB, measured: null }), null)
eq(M.bars({ fsSize: 0, measured: { referenced: 0, uncompressed: 0, disk: 0 } }), { files: 0, stored: 0, size: 0 })
// The live figures: the filesystem's own, the newest reading first.
eq(M.live({ fsSize: 4 * GB, fsUsed: 1 * GB, fsAvail: 3 * GB }),
  { size: 4 * GB, used: 1 * GB, data: null, metadata: null, free: 3 * GB, share: 0.25 })
eq(M.live({ fsSize: 0, fsUsed: 5 }), null); eq(M.live({ fsSize: 1, fsUsed: 5, fsAvail: 0 }).share, 1); eq(M.live(null), null)
// btrfs: what is on the disk is its data and metadata, not statfs's figure.
const btrfs = { fsSize: 40 * GB, fsUsed: 8.1 * GB, fsAvail: 31 * GB, onDisk: { data: 7 * GB, metadata: 1 * GB } }
eq(M.live(btrfs), { size: 40 * GB, used: 8 * GB, data: 7 * GB, metadata: 1 * GB, free: 31 * GB, share: 0.2 })
eq(M.liveLine(M.live(btrfs)), "8 GB on disk of 40 GB · data 7 GB, metadata 1 GB")
eq(M.liveLine(M.live({ fsSize: 4.29 * GB, fsUsed: 1.62 * GB, fsAvail: 2.6 * GB })), "1.62 GB used of 4.29 GB"); eq(M.liveLine(null), "")
// A newer reading replaces the volume's own figures, whole.
eq(M.live(btrfs, { fsSize: 40 * GB, fsUsed: 9 * GB, fsAvail: 30 * GB, onDisk: { data: 8 * GB, metadata: 1 * GB } }).used, 9 * GB)
eq(M.live(btrfs, { fsSize: 40 * GB, fsUsed: 9 * GB, fsAvail: 30 * GB, onDisk: null }).used, 9 * GB)
eq(M.live(btrfs, undefined).used, 8 * GB)
// Figures of the wrong kind are not shown as parts.
eq(M.live({ fsSize: 10, fsUsed: 4, fsAvail: "x", onDisk: { data: "x", metadata: 1 } }), { size: 10, used: 4, data: null, metadata: null, free: null, share: 0.4 })

// Names and where things are.
eq(M.mountsText(["/var/tmp", "/var/cache", "/var/log", "/srv", "/swap", "/home", "/root", "/"]), "/, /home and 6 more")
eq(M.mountsText(["/home", "/"]), "/ and /home"); eq(M.mountsText(["/mnt/big"]), "/mnt/big"); eq(M.mountsText([]), "")
eq(M.mainMount({ mounts: ["/home", "/"] }), "/"); eq(M.mainMount({ mounts: [] }), "")
eq(M.volumeName({ role: "system", label: "karchy" }), "System"); eq(M.volumeName({ role: "boot", label: "EFI" }), "Boot")
eq(M.volumeName({ role: "data", label: "BIG", mounts: ["/mnt/big"] }), "BIG")
eq(M.volumeName({ role: "data", label: null, mounts: ["/run/media/me/1234-ABCD"] }), "1234-ABCD")
eq(M.volumeName({ role: "data", label: null, mounts: [], size: 8 * GB }), "8 GB volume")
eq(M.volumeName({ role: "data", locked: true, label: null, mounts: [] }), "Encrypted volume")
eq(M.volumeDetail({ role: "system", fstype: "btrfs", encrypted: true, mounts: ["/home", "/"] }), "btrfs, encrypted · / and /home")
eq(M.volumeDetail({ role: "boot", fstype: "vfat", mounts: ["/boot"] }), "FAT · /boot")
eq(M.volumeDetail({ role: "data", fstype: "ext4", mounts: [] }), "ext4 · not mounted")
eq(M.volumeDetail({ role: "data", locked: true, mounts: [] }), "encrypted, locked")
eq(M.volumeDetail({ role: "swap", fstype: "swap", mounts: [] }), "swap space")
eq(M.diskTitle({ model: "Samsung SSD 970 EVO Plus 1TB", name: "nvme0n1" }), "Samsung SSD 970 EVO Plus 1TB")
eq(M.diskTitle({ model: "", name: "vda", transport: "virtio" }), "Virtual disk"); eq(M.diskTitle({ model: "", name: "sdb" }), "Disk sdb")
eq(M.diskKind({ transport: "nvme", size: 1000204886016 }), "NVMe, 1 TB"); eq(M.diskKind({ transport: "", size: 8 * GB }), "8 GB")

// Health: only what was measured, and in words. The entry is the measurement's.
eq(M.health({ health: null }), { state: "", text: "", facts: "", details: "" })
// A disk's entry among the ones read: by name, and by serial when both have one.
const read = [{ name: "sda", serial: "A1", health: "good" }, { name: "nvme0n1", serial: "", health: "warning" }]
eq(M.healthFor({ name: "sda", serial: "A1" }, read).health, "good"); eq(M.healthFor({ name: "sda", serial: "B2" }, read), null)
eq(M.healthFor({ name: "sda", serial: "" }, read).health, "good"); eq(M.healthFor({ name: "nvme0n1", serial: "S4" }, read).health, "warning")
eq(M.healthFor({ name: "sdb", serial: "A1" }, read), null); eq(M.healthFor({ name: "sda" }, null), null)
eq(M.health({ health: { name: "nvme0n1", serial: "S4EW", health: "good", problems: [], wear: 3, temperature: 41 } }),
  { state: "good", text: "good", facts: "3% worn, 41 °C", details: "" })
eq(M.health({ health: { health: "good", problems: [], wear: null, temperature: null } }).facts, "")
eq(M.health({ health: { health: "warning", problems: ["reallocated", "pending", "made-up"], wear: null, temperature: 38 } }),
  { state: "warning", text: "warning", facts: "38 °C", details: "Damaged blocks were replaced by spares; blocks are waiting to be replaced. Back up what is on this disk." })
eq(M.health({ health: { health: "asleep", problems: [] } }).text, ""); eq(M.health({ health: { health: "weird", problems: [] } }).state, "unknown")
eq(M.health({ health: { health: "unknown", problems: [], wear: null, temperature: null } }).state, "unknown")

// Times.
eq(M.roughly(30), "a minute"); eq(M.roughly(391), "7 minutes"); eq(M.roughly(3 * 3600 + 600), "3 hours")
eq(M.roughly(3600), "1 hour"); eq(M.roughly(3 * 86400), "3 days"); eq(M.roughly(-1), "")
const at = (y, m, d, h, min) => new Date(y, m, d, h, min).getTime()
const now = at(2026, 10, 18, 9, 30)
eq(M.when(at(2026, 10, 18, 4, 12) / 1000, now), "today at 04:12")
eq(M.when(at(2026, 10, 17, 23, 59) / 1000, now), "yesterday at 23:59")
eq(M.when(at(2026, 10, 12, 4, 5) / 1000, now), "on 12 Nov at 04:05")

// Background deduplication's line.
const bees = extra => Object.assign({ available: true, on: true, active: true, lockedOff: false, waitsForPower: false,
  state: "idle", firstPass: false, percent: 100, secondsLeft: -1, dedupBytes: 0, since: 0 }, extra)
eq(M.beesLine(bees({ state: "scanning", firstPass: true, percent: 64, secondsLeft: 3 * 3600 })), "Running: first pass 64%, about 3 hours left")
eq(M.beesLine(bees({ state: "scanning", firstPass: true, percent: 0, secondsLeft: -1 })), "Running: first pass 0%")
eq(M.beesLine(bees({ state: "scanning", firstPass: false, percent: 95, secondsLeft: 391, backlog: 1400 })), "Running: catching up on new data, about 7 minutes left")
eq(M.beesLine(bees({ state: "scanning", firstPass: false, percent: 95, secondsLeft: 1, backlog: -1 })), "Running: catching up on new data, about a minute left")
eq(M.beesLine(bees({ state: "scanning", firstPass: false, percent: 92, secondsLeft: 3, backlog: 1 })), "Up to date: it checks new data as it is written")
eq(M.beesLine(bees({ state: "scanning", firstPass: true, percent: 12, secondsLeft: -1, backlog: 226 })), "Running: first pass 12%")
eq(M.beesLine(bees({})), "Idle: everything on the disk is checked")
eq(M.beesLine(bees({ state: "starting" })), "Running: getting ready"); eq(M.beesLine(bees({ state: "unknown" })), "Running")
eq(M.beesLine(bees({ on: false, active: false, state: "stopped" })), "Off")
eq(M.beesLine(bees({ active: false, waitsForPower: true, state: "stopped" })), "Paused: it runs while plugged in")
eq(M.beesLine(bees({ active: false, state: "stopped" })), "Not running")
eq(M.beesLine(bees({ lockedOff: true, on: false, active: false })), "Switched off by karchy for now; an update turns it back on")
eq(M.beesLine({ available: false }), ""); eq(M.beesLine(null), "")
eq(M.beesTotal(bees({ dedupBytes: 12.3 * GB, since: at(2026, 10, 18, 8, 57) / 1000 }), now), "About 12.3 GB shared by it since it started today at 08:57")
eq(M.beesTotal(bees({ dedupBytes: 0 }), now), ""); eq(M.beesTotal(bees({ active: false, dedupBytes: 5 }), now), "")

// Shares.
eq(M.shareName({ source: "//truenas/tank-share", target: "/mnt/tank-share" }), { server: "truenas", name: "tank-share" })
eq(M.shareName({ source: "", target: "/mnt/x" }), { server: "", name: "/mnt/x" })
eq(M.shareState({ state: "connected" }), "connected"); eq(M.shareState({ state: "unreachable" }), "not reachable")
eq(M.shareState({ state: "idle" }), "connects when opened")

// What each volume offers.
const disk = { removable: false }, usb = { removable: true }
eq(M.volumeActions({ role: "system", fstype: "btrfs", encrypted: true, mounts: ["/"] }, disk), ["check", "speedtest", "password"])
eq(M.volumeActions({ role: "system", fstype: "ext4", encrypted: false, mounts: ["/"] }, disk), ["speedtest"])
eq(M.volumeActions({ role: "boot", fstype: "vfat", mounts: ["/boot"] }, disk), [])
eq(M.volumeActions({ role: "swap", fstype: "swap", mounts: [] }, disk), [])
eq(M.volumeActions({ role: "data", fstype: "ext4", mounts: ["/mnt/big"], kept: "/mnt/big", writable: "/mnt/big" }, disk), ["open", "unmount", "unkeep", "speedtest"])
eq(M.volumeActions({ role: "data", fstype: "ext4", mounts: [], kept: "/mnt/big" }, disk), ["mount", "unkeep"])
eq(M.volumeActions({ role: "data", fstype: "btrfs", mounts: [], kept: "", keepable: true }, disk), ["mount", "keep"])
eq(M.volumeActions({ role: "data", fstype: "btrfs", mounts: ["/run/media/me/x"], kept: "", keepable: false, size: 8 * GB, writable: "" }, disk), ["open", "unmount", "keep", "check"])
eq(M.volumeActions({ role: "data", fstype: "vfat", mounts: ["/run/media/me/x"], size: 0.5 * GB }, disk), ["open", "unmount"])
eq(M.volumeActions({ role: "data", fstype: "vfat", mounts: ["/efi2"], size: 2 * GB, parttype: "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" }, disk), ["open", "unmount"])
eq(M.volumeActions({ role: "data", fstype: "exfat", mounts: ["/run/media/me/STICK"], size: 8 * GB, keepable: false, writable: "/run/media/me/STICK" }, usb), ["open", "unmount", "speedtest"])
eq(M.volumeActions({ role: "data", fstype: "exfat", mounts: [], size: 8 * GB, keepable: true }, usb), ["mount"])
eq(M.volumeActions({ role: "data", locked: true, mounts: [] }, usb), ["unlock"])
eq(M.volumeActions(null, disk), [])

eq(M.split([{ name: "a", removable: false }, { name: "b", removable: true }, { name: "c", removable: false }]),
  { internal: [{ name: "a", removable: false }, { name: "c", removable: false }], removable: [{ name: "b", removable: true }] })
eq(M.split(null), { internal: [], removable: [] })

// The stack a volume sits on, outermost first.
eq(M.stackText({ fstype: "btrfs", partition: { name: "vda2", kind: "" }, layers: ["luks"] }), "vda2 › LUKS encryption › btrfs")
eq(M.stackText({ fstype: "vfat", partition: { name: "nvme0n1p1", kind: "EFI System" }, layers: [] }), "nvme0n1p1, EFI system partition › FAT")
eq(M.stackText({ fstype: "ext4", partition: null, layers: [] }), "the whole disk › ext4")
eq(M.stackText({ fstype: "xfs", partition: { name: "sdb1", kind: "Linux LVM" }, layers: ["lvm"] }), "sdb1 › LVM › xfs")
// A type that only says a filesystem goes there adds nothing.
eq(M.stackText({ fstype: "ext4", partition: { name: "vdb2", kind: "Linux filesystem" }, layers: [] }), "vdb2 › ext4")
eq(M.stackText({ fstype: "exfat", partition: { name: "vdb4", kind: "Microsoft basic data" }, layers: [] }), "vdb4 › exFAT")
// A locked volume: what is inside isn't known.
eq(M.stackText({ fstype: null, locked: true, partition: { name: "sdc1", kind: "" }, layers: ["luks"] }), "sdc1 › LUKS encryption")
eq(M.otherPartitionText({ name: "sda3", kind: "Microsoft reserved", size: 16 * MB }), "sda3 · reserved by Windows · 16 MB")
eq(M.otherPartitionText({ name: "sdb2", kind: "", label: "", size: 2 * GB }), "sdb2 · nothing recognized on it · 2 GB")

// A btrfs filesystem's subvolumes: the system's first, then /home, the other
// mounted ones by path, then the ones that are not mounted.
const subs = { subvolumes: [{ name: "@swap", mounts: ["/swap"] }, { name: ".beeshome", mounts: [] }, { name: "@log", mounts: ["/var/log"] },
  { name: "@home", mounts: ["/home"] }, { name: "@", mounts: ["/"] }, { name: "@data", mounts: ["/mnt/data"] }], snapshots: 26, nested: 3 }
eq(M.subvolumeRows(subs).map(r => r.name), ["@", "@home", "@data", "@swap", "@log", ".beeshome"])
eq(M.subvolumeRows(subs)[0], { name: "@", where: "/", what: "the system" })
eq(M.subvolumeRows(subs)[2], { name: "@data", where: "/mnt/data", what: "" })
eq(M.subvolumeRows(subs)[5], { name: ".beeshome", where: "", what: "background deduplication's own data" })
eq(M.subvolumeSummary(subs), "6 subvolumes · 26 snapshots")
// Without root's list the snapshots are not counted, and no number stands in.
eq(M.subvolumeSummary({ subvolumes: [{ name: "@", mounts: ["/"] }], snapshots: null, nested: null }), "1 subvolume")
eq(M.subvolumeSummary(null), ""); eq(M.subvolumeRows(null), [])
// A filesystem mounted whole has its top level as the one row.
eq(M.subvolumeRows({ subvolumes: [{ name: "", mounts: ["/mnt/photos"] }] }), [{ name: "(top level)", where: "/mnt/photos", what: "" }])

// The overview's tiles: the system, data volumes, USB drives, kept shares;
// never the boot partition, swap, or a recovery partition.
const efiType = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
const overviewDisks = [
  { name: "sdb", removable: false, volumes: [
    { path: "/dev/sdb1", role: "data", label: "Photos", fstype: "ext4", size: 500 * GB, uuid: "p", mounts: ["/mnt/photos"], fsSize: 500 * GB, fsUsed: 100 * GB, fsAvail: 380 * GB },
    { path: "/dev/sdb2", role: "data", label: "", fstype: "ntfs", size: 200 * GB, uuid: "w", mounts: [] },
    { path: "/dev/sdb3", role: "data", fstype: null, locked: true, encrypted: true, size: 100 * GB, mounts: [] },
    { path: "/dev/sdb4", role: "data", fstype: "ntfs", size: 600 * MB, mounts: [] },
    { path: "/dev/sdb5", role: "data", fstype: "vfat", size: 2 * GB, parttype: efiType, mounts: [] }] },
  { name: "nvme0n1", removable: false, volumes: [
    { path: "/dev/mapper/luks-1", role: "system", fstype: "btrfs", encrypted: true, size: 40 * GB, uuid: "s", mounts: ["/home", "/"], fsSize: 40 * GB, fsAvail: 27 * GB, onDisk: { data: 10 * GB, metadata: 1 * GB } },
    { path: "/dev/nvme0n1p1", role: "boot", fstype: "vfat", size: 4 * GB, mounts: ["/boot"], fsSize: 4 * GB, fsUsed: 1 * GB, fsAvail: 3 * GB },
    { path: "/dev/nvme0n1p3", role: "swap", fstype: "swap", size: 8 * GB, mounts: [] }] },
  { name: "sdc", removable: true, volumes: [
    { path: "/dev/sdc1", role: "data", label: "STICK", fstype: "vfat", size: 500 * MB, uuid: "u", mounts: [] }] }
]
const overviewShares = [
  { source: "//nas/media", target: "/mnt/media", state: "connected", size: 8000 * GB, avail: 2000 * GB },
  { source: "//nas/backup", target: "/mnt/backup", state: "idle" },
  { source: "//old/files", target: "/mnt/files", state: "unreachable" }]
const tiles = M.places(overviewDisks, overviewShares, {})
eq(tiles.map(t => t.name + ":" + t.kind + ":" + t.state), ["System:system:open", "Photos:disk:open", "200 GB volume:disk:mount",
  "Encrypted volume:disk:unlock", "STICK:usb:mount", "media:share:open", "backup:share:open", "files:share:unreachable"])
eq(tiles[0].target, "/"); eq(tiles[0].line, "27 GB free of 40 GB"); eq(tiles[0].space.share, 11 / 40)
eq(tiles[1].target, "/mnt/photos"); eq(tiles[1].line, "380 GB free of 500 GB")
eq(tiles[2].line, "Not mounted · 200 GB"); eq(tiles[2].space, null); eq(tiles[2].target, "")
eq(tiles[3].line, "Locked · 100 GB")
eq(tiles[5].line, "2 TB free of 8 TB"); eq(tiles[5].space.share, 0.75)
eq(tiles[6].line, "Connects when opened"); eq(tiles[7].line, "Not reachable")
// The newest reading replaces the figures status came with.
eq(M.places(overviewDisks, [], { p: { fsSize: 500 * GB, fsUsed: 300 * GB, fsAvail: 180 * GB } })[1].line, "180 GB free of 500 GB")
eq(M.placeAction(tiles[0]), "Open System in Files"); eq(M.placeAction(tiles[2]), "Mount 200 GB volume")
eq(M.placeAction(tiles[3]), "Unlock Encrypted volume…"); eq(M.placeAction(tiles[7]), "files can't be reached")
eq(M.places([], [], {}), []); eq(M.places(null, null, null), [])

console.log("storage model ok")
