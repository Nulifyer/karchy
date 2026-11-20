// The sums and the words of Settings › Storage, apart from the page so they
// can be checked on their own (tests/storage-model.js). Everything here works
// on what `karchy-settings-storage status`, `shares` and `bees` print.

// A size in decimal units, as disks are sold and named ("1 TB"): three
// significant digits, without trailing zeros. "1.21 TB", "70.3 GB", "819 GB".
function bytes(value) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return ""
  var units = ["B", "kB", "MB", "GB", "TB", "PB"]
  var unit = 0
  while (n >= 999.5 && unit < units.length - 1) { n /= 1000; unit++ }
  var decimals = unit === 0 || n >= 100 ? 0 : n >= 10 ? 1 : 2
  var text = n.toFixed(decimals)
  if (decimals > 0) text = text.replace(/\.?0+$/, "")
  return text + " " + units[unit]
}

// A whole disk's size the way its box says it: "1 TB", "500 GB", "43 GB".
function diskSize(value) {
  var n = Number(value)
  if (!isFinite(n) || n <= 0) return ""
  var units = ["B", "kB", "MB", "GB", "TB", "PB"]
  var unit = 0
  while (n >= 999.5 && unit < units.length - 1) { n /= 1000; unit++ }
  var text = n < 9.95 ? n.toFixed(1).replace(/\.0$/, "") : String(Math.round(n))
  return text + " " + units[unit]
}

// A mounted volume's space as it is now, from the filesystem itself: `space`
// is the newest reading (`karchy-settings-storage usage`, by UUID), and the
// volume's own figures from `status` stand in until one arrives. null when
// it is not mounted.
//   size      the filesystem's size
//   used      bytes taken on the disk. On btrfs that is its own total of
//             data and metadata as written (compressed, shared data once,
//             a second metadata copy counted), snapshots included; elsewhere
//             what the filesystem reports as used.
//   data, metadata   the two parts on btrfs, else null
//   free      room left for files; on btrfs an estimate, because how much
//             fits depends on how well it compresses and on metadata
//   share     used / size, 0 to 1
function live(volume, space) {
  var v = space && typeof space === "object" ? space : volume
  if (!v) return null
  var size = Number(v.fsSize)
  if (!isFinite(size) || size <= 0) return null
  var d = v.onDisk
  var data = d ? Number(d.data) : NaN, metadata = d ? Number(d.metadata) : NaN
  var parts = isFinite(data) && isFinite(metadata) && data >= 0 && metadata >= 0
  var used = parts ? data + metadata : Number(v.fsUsed)
  if (!isFinite(used) || used < 0) used = 0
  var free = Number(v.fsAvail)
  return {
    size: size, used: used, data: parts ? data : null, metadata: parts ? metadata : null,
    free: isFinite(free) && free >= 0 ? free : null,
    share: Math.min(1, Math.max(0, used / size))
  }
}

// "7.83 GB on disk of 39.6 GB · data 7.21 GB, metadata 620 MB" for btrfs,
// "1.62 GB used of 4.29 GB" elsewhere.
function liveLine(figures) {
  if (!figures) return ""
  if (figures.data === null) return bytes(figures.used) + " used of " + bytes(figures.size)
  return bytes(figures.used) + " on disk of " + bytes(figures.size)
    + " · data " + bytes(figures.data) + ", metadata " + bytes(figures.metadata)
}

// The breakdown of one btrfs filesystem's live data, from the count that
// "Measure now" starts (`measured` on a volume; /usr/lib/karchy/storage-measure
// says how each is counted). null when it was not counted or the count failed.
//   files        what the files hold: every file's data added up ("Your files")
//   stored       what that data takes on the disk ("Stored on disk")
//   sharing      files - uncompressed: saved because files share data
//                (reflink copies and deduplication), never below 0
//   overhead     the other way round, when it is: btrfs keeps a whole extent
//                while any part of it is in use, so partly overwritten files
//                hold more than they show. Only one of the two is above 0,
//                because the count gives their difference, not each.
//   compression  uncompressed - stored
//   snapshots    on the disk only for read-only snapshots, or null when that
//                part of the count failed
function figures(measured) {
  if (!measured || typeof measured !== "object") return null
  var files = Number(measured.referenced)
  var uncompressed = Number(measured.uncompressed)
  var stored = Number(measured.disk)
  if (!isFinite(files) || !isFinite(uncompressed) || !isFinite(stored)) return null
  if (files < 0 || uncompressed < 0 || stored < 0) return null
  var net = files - uncompressed
  var snapshots = measured.snapshots === null || measured.snapshots === undefined ? null : Number(measured.snapshots)
  return {
    files: files,
    stored: stored,
    sharing: Math.max(0, net),
    overhead: Math.max(0, -net),
    compression: Math.max(0, uncompressed - stored),
    snapshots: snapshots !== null && isFinite(snapshots) && snapshots >= 0 ? snapshots : null
  }
}

// How long the three comparison bars are, as shares of the longest thing
// shown: the files (which sharing and compression can make larger than the
// disk) or the disk itself.
function bars(volume) {
  var f = figures(volume && volume.measured)
  var size = Number(volume && volume.fsSize) || 0
  if (!f) return null
  var full = Math.max(f.files, f.stored, size)
  if (full <= 0) return { files: 0, stored: 0, size: 0 }
  return { files: f.files / full, stored: f.stored / full, size: size / full }
}

function fsName(fstype) {
  var names = { vfat: "FAT", exfat: "exFAT", ntfs: "NTFS", ntfs3: "NTFS", swap: "swap space" }
  return names[fstype] || String(fstype || "")
}

// "/ and /home", "/, /home and 6 more": the root first, then /home, then the
// shortest.
function mountsText(mounts) {
  var rank = function(path) { return path === "/" ? 0 : path === "/home" ? 1 : 2 }
  var list = (mounts || []).slice().sort(function(a, b) {
    return rank(a) - rank(b) || a.length - b.length || (a < b ? -1 : a > b ? 1 : 0)
  })
  if (list.length === 0) return ""
  if (list.length === 1) return list[0]
  if (list.length === 2) return list[0] + " and " + list[1]
  return list[0] + ", " + list[1] + " and " + (list.length - 2) + " more"
}

// The mount point a volume is opened at in the file manager: the shortest.
function mainMount(volume) {
  var list = ((volume && volume.mounts) || []).slice().sort(function(a, b) { return a.length - b.length })
  return list.length ? list[0] : ""
}

function volumeName(volume) {
  if (!volume) return ""
  if (volume.role === "system") return "System"
  if (volume.role === "boot") return "Boot"
  if (volume.role === "swap") return "Swap"
  if (volume.label) return String(volume.label)
  var mount = mainMount(volume)
  if (mount) return mount.split("/").pop() || mount
  if (volume.locked) return "Encrypted volume"
  return bytes(volume.size) + " volume"
}

// "btrfs, encrypted · / and /home", "ext4 · not mounted", "locked".
function volumeDetail(volume) {
  if (!volume) return ""
  if (volume.locked) return "encrypted, locked"
  var kind = fsName(volume.fstype) + (volume.encrypted ? ", encrypted" : "")
  if (volume.role === "swap") return kind
  var where = mountsText(volume.mounts)
  return kind + " · " + (where !== "" ? where : "not mounted")
}

function diskTitle(disk) {
  if (!disk) return ""
  if (disk.model) return String(disk.model)
  if (disk.transport === "virtio") return "Virtual disk"
  return "Disk " + disk.name
}

// "NVMe, 1 TB".
function diskKind(disk) {
  var names = { nvme: "NVMe", sata: "SATA", ata: "SATA", usb: "USB", mmc: "Card", virtio: "Virtual", sas: "SAS", scsi: "SCSI" }
  var kind = names[disk && disk.transport] || ""
  var size = diskSize(disk && disk.size)
  return kind !== "" ? kind + ", " + size : size
}

var problems = {
  "failing": "the disk reports that it is failing",
  "critical": "the disk raised a critical warning",
  "media-errors": "data could not be read or written",
  "spare-low": "its spare blocks are nearly used up",
  "reallocated": "damaged blocks were replaced by spares",
  "pending": "blocks are waiting to be replaced",
  "unreadable": "blocks can't be read",
  "worn": "it is near the end of its rated life"
}

// The entry of `karchy-settings-storage health` that is this disk's: the same
// kernel name, and the same serial when both give one (a USB stick can take
// over a name another disk had).
function healthFor(disk, list) {
  var found = null
  ;(list || []).forEach(function(h) {
    if (found || !h || !disk || h.name !== disk.name) return
    if (!h.serial || !disk.serial || h.serial === disk.serial) found = h
  })
  return found
}

// A disk's health from its entry ({health, problems, wear, temperature}; on
// the disk as `health`): `state` is "good", "warning", "asleep", "unknown"
// (no SMART data) or "" (not read yet); `text` is what follows "Health";
// `details` is what makes it a warning, as a sentence.
function health(disk) {
  var h = disk && disk.health
  if (!h) return { state: "", text: "", facts: "", details: "" }
  var facts = []
  if (typeof h.wear === "number") facts.push(Math.round(h.wear) + "% worn")
  if (typeof h.temperature === "number") facts.push(Math.round(h.temperature) + " °C")
  var found = (h.problems || []).map(function(code) { return problems[code] }).filter(function(text) { return !!text })
  var details = found.length ? found.join("; ") : ""
  if (details !== "") details = details.charAt(0).toUpperCase() + details.slice(1) + ". Back up what is on this disk."
  var state = ["good", "warning", "asleep"].indexOf(h.health) !== -1 ? h.health : "unknown"
  return { state: state, text: state === "asleep" ? "" : state, facts: facts.join(", "), details: details }
}

function plural(n, unit) { return n + " " + unit + (n === 1 ? "" : "s") }

// A time left, rounded the way one would say it: "a minute", "25 minutes",
// "3 hours", "2 days".
function roughly(seconds) {
  var s = Number(seconds)
  if (!isFinite(s) || s < 0) return ""
  if (s < 90) return "a minute"
  if (s < 3570) return plural(Math.round(s / 60), "minute")
  if (s < 47.5 * 3600) return plural(Math.round(s / 3600), "hour")
  return plural(Math.round(s / 86400), "day")
}

function two(n) { return (n < 10 ? "0" : "") + n }
function clock(date) { return two(date.getHours()) + ":" + two(date.getMinutes()) }

var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// "today at 04:12", "yesterday at 04:12", "on 12 Nov at 04:12", for a time in
// seconds since 1970 and the time now in milliseconds.
function when(seconds, nowMs) {
  var then = new Date(Number(seconds) * 1000)
  var now = new Date(nowMs)
  var day = function(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() }
  var days = Math.round((day(now) - day(then)) / 86400000)
  if (days <= 0) return "today at " + clock(then)
  if (days === 1) return "yesterday at " + clock(then)
  return "on " + then.getDate() + " " + months[then.getMonth()] + " at " + clock(then)
}

// A scan that covers no more filesystem transactions than this is bees
// keeping up with what is being written (a transaction is at most 30 seconds
// of writing, and bees starts a new scan for each one or two); more is a
// backlog from a time it was not running.
var beesKeepingUp = 60

// The line under "Background deduplication", from `karchy-settings-storage bees`.
function beesLine(bees) {
  if (!bees || !bees.available) return ""
  if (bees.lockedOff) return "Switched off by karchy for now; an update turns it back on"
  if (!bees.on && !bees.active) return "Off"
  // Not running with the switch on: it ended with an error (the page offers
  // its log), karchy-laptop holds it until the charger is back, or it was
  // stopped by hand.
  if (!bees.active) return bees.failed ? "Stopped with an error" : bees.waitsForPower ? "Paused: it runs while plugged in" : "Not running"
  if (bees.state === "starting") return "Running: getting ready"
  if (bees.state === "idle") return "Idle: everything on the disk is checked"
  if (bees.state === "scanning") {
    var left = bees.secondsLeft >= 0 ? ", about " + roughly(bees.secondsLeft) + " left" : ""
    if (bees.firstPass) return "Running: first pass " + Math.round(bees.percent) + "%" + left
    if (bees.backlog >= 0 && bees.backlog <= beesKeepingUp) return "Up to date: it checks new data as it is written"
    return "Running: catching up on new data" + left
  }
  return "Running"
}

// What bees itself counts: the data it has pointed at an existing copy since
// it started. An estimate of its work, not of what is saved now: the count
// starts again with bees and never goes down when those files are deleted
// or rewritten.
function beesTotal(bees, nowMs) {
  if (!bees || !bees.active || !(bees.dedupBytes > 0)) return ""
  return "About " + bytes(bees.dedupBytes) + " shared by it since it started" + (bees.since > 0 ? " " + when(bees.since, nowMs) : "")
}

// "media" and "truenas" from "//truenas/media".
function shareName(share) {
  var parts = String((share && share.source) || "").replace(/^\/+/, "").split("/")
  return { server: parts[0] || "", name: parts.slice(1).join("/") || String((share && share.target) || "") }
}

function shareState(share) {
  var state = share && share.state
  return state === "connected" ? "connected" : state === "unreachable" ? "not reachable" : "connects when opened"
}

// What can be done with a volume, in the order the buttons are shown.
//   open       show it in the file manager
//   mount, unmount, unlock
//   keep       mount it at /mnt from now on (internal data disks)
//   unkeep     stop doing that
//   check      check a btrfs filesystem for errors
//   speedtest  measure read and write speed (needs a folder it may write to)
//   password   change the encryption password (the system disk)
function volumeActions(volume, disk) {
  var out = []
  if (!volume || volume.role === "swap") return out
  if (volume.locked) return ["unlock"]
  var mounted = (volume.mounts || []).length > 0
  var system = volume.role === "system" || volume.role === "boot"
  if (!system) {
    if (mounted) out.push("open", "unmount")
    else out.push("mount")
    if (!(disk && disk.removable)) {
      if (volume.kept) out.push("unkeep")
      // karchy-disk-fstab decides which volumes count as data disks; one the
      // file manager has mounted counts once it is unmounted.
      else if (volume.keepable || (mounted && isDataPartition(volume))) out.push("keep")
    }
  }
  if (volume.role === "boot") return out
  if (mounted && volume.fstype === "btrfs") out.push("check")
  if (volume.role === "system" || volume.writable) out.push("speedtest")
  if (volume.role === "system" && volume.encrypted) out.push("password")
  return out
}

// What karchy-disk-fstab counts as a data partition, less "not mounted".
function isDataPartition(volume) {
  var efi = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b", recovery = "de94bba4-06d1-4d40-a16a-bfd50179d6ac"
  return ["ntfs", "exfat", "vfat", "ext4", "btrfs", "xfs"].indexOf(volume.fstype) !== -1
    && !volume.encrypted && Number(volume.size) >= 1073741824
    && volume.parttype !== efi && volume.parttype !== recovery
}

// ---------------------------------------------------------------- the stack

var layerNames = { luks: "LUKS encryption", lvm: "LVM", raid: "RAID" }

// A partition's type as lsblk names it, in the page's words. The types that
// only say "a filesystem goes here" say nothing the filesystem doesn't.
function partitionKind(kind) {
  var names = { "EFI System": "EFI system partition", "BIOS boot": "BIOS boot partition",
                "Microsoft reserved": "reserved by Windows", "Windows recovery environment": "Windows recovery",
                "Linux filesystem": "", "Microsoft basic data": "", "Linux root (x86-64)": "", "Linux home": "",
                "Linux LVM": "", "Linux RAID": "", "Linux LUKS": "" }
  var text = String(kind || "")
  return names[text] !== undefined ? names[text] : text
}

// What a volume sits on, outermost first: "vda2 › LUKS encryption › btrfs",
// "sda1, EFI system partition › FAT", "the whole disk › ext4". For a locked
// volume the stack ends at the encryption: what is inside isn't known.
function stackText(volume) {
  if (!volume) return ""
  var parts = []
  var p = volume.partition
  if (p && p.name) parts.push(p.name + (partitionKind(p.kind) !== "" ? ", " + partitionKind(p.kind) : ""))
  else parts.push("the whole disk")
  ;(volume.layers || []).forEach(function(layer) { if (layerNames[layer]) parts.push(layerNames[layer]) })
  if (!volume.locked && volume.fstype) parts.push(fsName(volume.fstype))
  return parts.join(" › ")
}

// A partition with nothing the page lists as a volume: "vda3 · reserved by
// Windows · 16 MB".
function otherPartitionText(partition) {
  if (!partition) return ""
  var kind = partitionKind(partition.kind) || (partition.label ? String(partition.label) : "nothing recognized on it")
  return partition.name + " · " + kind + " · " + bytes(partition.size)
}

// What karchy's own layout keeps in a subvolume, by where it is mounted or,
// for one that is never mounted, by its name.
var subvolumePurposes = {
  "/": "the system", "/home": "home folders", "/root": "the administrator's home", "/swap": "the swap file",
  "/var/log": "logs", "/var/cache": "caches", "/var/tmp": "temporary files", "/srv": "files this computer serves"
}

// The rows under a btrfs volume, from `karchy-settings-storage subvolumes`
// (its entry for the filesystem): { name, where, what } for each top-level
// subvolume, the system's first, then /home, then the other mounted ones by
// path, then the ones that are not mounted. `where` is "" when it is not
// mounted, `what` "" when karchy has no word for it.
function subvolumeRows(info) {
  var list = ((info && info.subvolumes) || []).map(function(sub) {
    var mounts = (sub.mounts || []).slice().sort(function(a, b) { return a.length - b.length || (a < b ? -1 : 1) })
    var where = mounts.length ? mounts[0] : ""
    var what = subvolumePurposes[where] || (sub.name === ".beeshome" ? "background deduplication's own data" : "")
    return { name: sub.name === "" ? "(top level)" : String(sub.name), where: where, what: what }
  })
  var rank = function(row) { return row.where === "/" ? 0 : row.where === "/home" ? 1 : row.where !== "" ? 2 : 3 }
  return list.sort(function(a, b) {
    return rank(a) - rank(b) || (a.where < b.where ? -1 : a.where > b.where ? 1 : 0) || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0)
  })
}

// "9 subvolumes · 26 snapshots" for the line that opens the rows; the
// snapshots only when they were counted (root lists them).
function subvolumeSummary(info) {
  var count = ((info && info.subvolumes) || []).length
  if (count === 0) return ""
  var text = plural(count, "subvolume")
  if (info.snapshots !== null && info.snapshots !== undefined) text += " · " + plural(Number(info.snapshots), "snapshot")
  return text
}

// ------------------------------------------------------------ the overview

// A filesystem the file manager can show, on a partition that is not a
// boot or recovery one. Removable drives count whatever their size.
function opensAsPlace(volume, disk) {
  var efi = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b", recovery = "de94bba4-06d1-4d40-a16a-bfd50179d6ac"
  if (!volume || volume.role !== "data") return false
  if (volume.locked || (volume.mounts || []).length > 0) return true
  if (["ntfs", "ntfs3", "exfat", "vfat", "ext2", "ext3", "ext4", "btrfs", "xfs", "f2fs", "udf", "iso9660", "hfsplus"].indexOf(volume.fstype) === -1) return false
  if (volume.parttype === efi || volume.parttype === recovery) return false
  return !!(disk && disk.removable) || Number(volume.size) >= 1073741824
}

// The tiles at the top of the page: every place files are opened from. The
// system first, then the other volumes of the internal disks, the USB
// drives, and the kept network shares. Each is
//   { key, kind: "system" | "disk" | "usb" | "share", name,
//     state: "open" | "mount" | "unlock" | "unreachable",
//     target (the folder it opens at, "" until it is mounted),
//     path (the device), space: { free, size, share } | null, line }
// `line` is what the tile says under the name: the room left, or its state.
// `usage` is the newest reading by UUID, as live() takes it.
function places(disks, shares, usage) {
  var out = []
  var parts = split(disks)
  // `wantSystem` picks the pass: the system's tile leads, wherever its disk
  // is, and the rest follow in the disks' own order.
  var add = function(disk, kind, wantSystem) {
    ;(disk.volumes || []).forEach(function(volume) {
      var system = volume.role === "system"
      if (system !== wantSystem) return
      if (!system && !opensAsPlace(volume, disk)) return
      var figures = live(volume, usage && volume.uuid ? usage[volume.uuid] : null)
      var mounted = (volume.mounts || []).length > 0
      var state = volume.locked ? "unlock" : mounted ? "open" : "mount"
      var space = mounted && figures && figures.free !== null ? { free: figures.free, size: figures.size, share: figures.share } : null
      out.push({
        key: volume.path, kind: system ? "system" : kind, name: volumeName(volume), state: state,
        target: !mounted ? "" : system ? "/" : mainMount(volume), path: volume.path, space: space,
        line: space ? bytes(space.free) + " free of " + bytes(space.size)
          : state === "unlock" ? "Locked · " + bytes(volume.size)
          : state === "mount" ? "Not mounted · " + bytes(volume.size) : bytes(volume.size)
      })
    })
  }
  parts.internal.concat(parts.removable).forEach(function(disk) { add(disk, "disk", true) })
  parts.internal.forEach(function(disk) { add(disk, "disk", false) })
  parts.removable.forEach(function(disk) { add(disk, "usb", false) })
  ;(shares || []).forEach(function(share) {
    var names = shareName(share)
    var connected = share.state === "connected" && Number(share.size) > 0
    var space = connected ? { free: Number(share.avail), size: Number(share.size),
      share: Math.min(1, Math.max(0, 1 - Number(share.avail) / Number(share.size))) } : null
    out.push({
      key: "share:" + share.target, kind: "share", name: names.name,
      state: share.state === "unreachable" ? "unreachable" : "open", target: share.target, path: "", space: space,
      line: space ? bytes(space.free) + " free of " + bytes(space.size)
        : share.state === "unreachable" ? "Not reachable" : share.state === "connected" ? "On " + names.server : "Connects when opened"
    })
  })
  return out
}

// What activating a tile does, as its button says it.
function placeAction(place) {
  if (!place) return ""
  if (place.state === "unlock") return "Unlock " + place.name + "…"
  if (place.state === "mount") return "Mount " + place.name
  if (place.state === "unreachable") return place.name + " can't be reached"
  return "Open " + place.name + " in Files"
}

// Internal disks first, as the system sees them; removable ones apart.
function split(disks) {
  var internal = [], removable = []
  ;(disks || []).forEach(function(disk) { (disk.removable ? removable : internal).push(disk) })
  return { internal: internal, removable: removable }
}

if (typeof module !== "undefined") {
  module.exports = {
    bytes: bytes, diskSize: diskSize, live: live, liveLine: liveLine, figures: figures, bars: bars, fsName: fsName,
    mountsText: mountsText, mainMount: mainMount, volumeName: volumeName, volumeDetail: volumeDetail,
    diskTitle: diskTitle, diskKind: diskKind, healthFor: healthFor, health: health, roughly: roughly, when: when,
    beesLine: beesLine, beesTotal: beesTotal, shareName: shareName, shareState: shareState,
    volumeActions: volumeActions, split: split, stackText: stackText, otherPartitionText: otherPartitionText,
    partitionKind: partitionKind, subvolumeRows: subvolumeRows, subvolumeSummary: subvolumeSummary,
    opensAsPlace: opensAsPlace, places: places, placeAction: placeAction, plural: plural
  }
}
