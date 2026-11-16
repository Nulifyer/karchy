.pragma library

// The VMs plugin's one model, shared by the bar panel and the window so both
// say the same thing: a VM's name, icon (osIcon), status line (statusLine) and
// status color (statusRole), and what its run switch does. Input is the output of
// `karchy-vm list --json`: one object per VM with its settings, its state
// (running | starting | stopping | stopped) and, while it runs, the QEMU
// process's CPU time and resident memory.

function parse(text) {
  try {
    var list = JSON.parse(String(text || "").trim() || "[]")
    return Array.isArray(list) ? list : []
  } catch (e) {
    return null
  }
}

function isRunning(vm) {
  return !!vm && vm.state !== "stopped"
}

// Running VMs first, then by name.
function sorted(vms) {
  return (vms || []).slice().sort(function(a, b) {
    var ra = isRunning(a) ? 0 : 1
    var rb = isRunning(b) ? 0 : 1
    if (ra !== rb) return ra - rb
    return String(a.name).localeCompare(String(b.name))
  })
}

function runningNames(vms) {
  return (vms || []).filter(isRunning).map(function(vm) { return vm.name })
}

function find(vms, name) {
  for (var i = 0; i < (vms || []).length; i++)
    if (vms[i].name === name) return vms[i]
  return null
}

function formatBytes(bytes) {
  var n = Number(bytes) || 0
  if (n >= 1073741824) return (n / 1073741824).toFixed(n >= 10737418240 ? 0 : 1) + " GiB"
  if (n >= 1048576) return Math.round(n / 1048576) + " MiB"
  if (n >= 1024) return Math.round(n / 1024) + " KiB"
  return n + " B"
}

// vm.conf sizes: "4G", "512M" or plain MiB.
function ramBytes(ram) {
  var m = /^(\d+)([MG]?)$/.exec(String(ram || ""))
  if (!m) return 0
  var n = Number(m[1])
  return m[2] === "G" ? n * 1073741824 : n * 1048576
}

function ramLabel(ram) {
  var m = /^(\d+)([MG]?)$/.exec(String(ram || ""))
  if (!m) return String(ram || "")
  return m[2] === "G" ? m[1] + " GiB" : m[1] + " MiB"
}

// CPU use between two polls, as a share of the VM's own CPUs. `prev` maps a
// name to its last { cpu, at }; returns { percent: {name: %}, prev: next map }.
function sampleCpu(vms, prev, nowMs) {
  var percent = {}
  var next = {}
  ;(vms || []).forEach(function(vm) {
    if (!isRunning(vm) || !(vm.pid > 0)) return
    var cpu = Number(vm.cpu_seconds) || 0
    var last = prev ? prev[vm.name] : null
    if (last && last.pid === vm.pid && nowMs > last.at) {
      var used = (cpu - last.cpu) / ((nowMs - last.at) / 1000)
      percent[vm.name] = Math.max(0, Math.min(100, Math.round(used * 100 / Math.max(1, vm.cpus))))
    }
    next[vm.name] = { cpu: cpu, at: nowMs, pid: vm.pid }
  })
  return { percent: percent, prev: next }
}

function stateLabel(state) {
  if (state === "running") return "Running"
  if (state === "starting") return "Starting"
  if (state === "stopping") return "Shutting down"
  return "Stopped"
}

// One line under a VM's name: live use while it runs, its size otherwise.
function statusLine(vm, cpuPercent, pending) {
  if (!vm) return ""
  if (pending) return pending
  if (vm.state === "running") {
    var parts = ["Running"]
    if (cpuPercent !== undefined) parts.push(cpuPercent + "% CPU")
    if (vm.mem_used > 0) parts.push(formatBytes(vm.mem_used) + " of " + ramLabel(vm.ram))
    return parts.join(" · ")
  }
  if (vm.state !== "stopped") return stateLabel(vm.state)
  return "Stopped · " + vm.cpus + (vm.cpus === 1 ? " CPU · " : " CPUs · ") + ramLabel(vm.ram)
}

// Which status color a VM's state takes: "success" running, "warning" on its
// way up or down, "" (secondary text) stopped.
function statusRole(vm) {
  if (!vm || vm.state === "stopped") return ""
  return vm.state === "running" ? "success" : "warning"
}

// The run switch: on while the VM runs or is starting. Turning it off asks the
// guest to shut down (never forces it); turning it on starts the VM.
function switchOn(vm) {
  return !!vm && (vm.state === "running" || vm.state === "starting")
}

function switchAction(vm) {
  return switchOn(vm) ? "stop" : "start"
}

// What the panel shows while an action it asked for is under way.
function pendingLabel(action) {
  if (action === "start") return "Starting…"
  if (action === "stop") return "Shutting down…"
  if (action === "kill") return "Forcing off…"
  return ""
}

// Case-insensitive name filter for the window's sidebar.
function filtered(vms, text) {
  var q = String(text || "").trim().toLowerCase()
  if (q === "") return vms || []
  return (vms || []).filter(function(vm) { return String(vm.name).toLowerCase().indexOf(q) !== -1 })
}

function osLabel(os) {
  return os === "windows" ? "Windows" : "Linux"
}

// The icon name (default/karchy/icons.json) for a guest OS.
function osIcon(os) {
  return os === "windows" ? "brand.windows" : "brand.linux"
}

function baseName(path) {
  var s = String(path || "")
  var i = s.lastIndexOf("/")
  return i >= 0 ? s.slice(i + 1) : s
}

// Names karchy-vm accepts for VMs and snapshots.
function validName(name) {
  return /^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$/.test(String(name || ""))
}

function validSize(size) {
  return /^[1-9][0-9]*[KMGT]?$/.test(String(size || ""))
}

function validRam(ram) {
  return /^[1-9][0-9]*[MG]?$/.test(String(ram || ""))
}

function formatDate(seconds) {
  var d = new Date((Number(seconds) || 0) * 1000)
  function pad(n) { return n < 10 ? "0" + n : String(n) }
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + " " + pad(d.getHours()) + ":" + pad(d.getMinutes())
}
