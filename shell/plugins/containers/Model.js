.pragma library

// The Containers plugin's one model, shared by the bar panel and the window so
// both say the same thing: a container's name, icon (stateIcon), status line
// (statusLine), status color (statusRole) and what its run switch does. The
// data comes from `karchy-containers list|summary|images` (see that command's
// header).

function parse(text, fallback) {
  try {
    var value = JSON.parse(text)
    return value === null || value === undefined ? fallback : value
  } catch (e) {
    return fallback
  }
}

// Containers grouped by Compose project, projects by name, then the
// containers that belong to none. `onlyRunning` keeps the panel's view.
function group(containers, onlyRunning) {
  var groups = {}
  var order = []
  ;(containers || []).forEach(function(c) {
    if (onlyRunning && c.state !== "running") return
    var key = c.project || ""
    if (!groups[key]) {
      groups[key] = []
      order.push(key)
    }
    groups[key].push(c)
  })
  order.sort(function(a, b) {
    if (a === "") return 1
    if (b === "") return -1
    return a.localeCompare(b)
  })
  return order.map(function(key) {
    var list = groups[key].slice().sort(function(a, b) {
      var ra = a.state === "running" ? 0 : 1
      var rb = b.state === "running" ? 0 : 1
      return ra !== rb ? ra - rb : a.name.localeCompare(b.name)
    })
    return { project: key, containers: list }
  })
}

// A published port opens on this machine unless it is bound to one address.
function portUrl(port) {
  var ip = port.ip || ""
  var host = ip === "" || ip === "0.0.0.0" || ip === "::" ? "localhost" : (ip.indexOf(":") !== -1 ? "[" + ip + "]" : ip)
  var scheme = port.container === 443 || port.container === 8443 ? "https" : "http"
  return scheme + "://" + host + ":" + port.host
}

function portLabel(port) {
  return port.host + "→" + port.container + (port.proto && port.proto !== "tcp" ? "/" + port.proto : "")
}

function portsText(ports) {
  return (ports || []).map(portLabel).join("  ")
}

function isRunning(c) {
  return c && c.state === "running"
}

// The icon name (default/karchy/icons.json) for a container state.
function stateIcon(state) {
  if (state === "running") return "media.play"
  if (state === "paused") return "media.pause"
  if (state === "created") return "state.created"
  return "media.stop"
}

// Which status color a container's state takes: "success" running, "warning"
// paused or restarting, "" (secondary text) otherwise.
function statusRole(c) {
  if (!c) return ""
  if (c.state === "running") return "success"
  if (c.state === "paused" || c.state === "restarting") return "warning"
  return ""
}

// One line under a container's name: what it's doing, then where it runs and
// what it publishes. `busy` (an action under way) replaces it.
function statusLine(c, busy) {
  if (!c) return ""
  if (busy) return busy
  return [c.status || c.state, shortImage(c.image), portsText(c.ports)]
    .filter(function(s) { return s }).join(" · ")
}

// The run switch: on while it runs; off stops it, on starts it.
function switchAction(c) {
  return isRunning(c) ? "stop" : "start"
}

// Running first, then by Compose project and name.
function sorted(containers) {
  return (containers || []).slice().sort(function(a, b) {
    var ra = isRunning(a) ? 0 : 1
    var rb = isRunning(b) ? 0 : 1
    if (ra !== rb) return ra - rb
    var pa = a.project || "~", pb = b.project || "~"
    if (pa !== pb) return pa.localeCompare(pb)
    return a.name.localeCompare(b.name)
  })
}

function filtered(containers, text) {
  var q = String(text || "").trim().toLowerCase()
  if (q === "") return containers || []
  return (containers || []).filter(function(c) {
    return String(c.name).toLowerCase().indexOf(q) !== -1
      || String(c.project || "").toLowerCase().indexOf(q) !== -1
      || shortImage(c.image).toLowerCase().indexOf(q) !== -1
  })
}

function find(containers, key) {
  for (var i = 0; i < (containers || []).length; i++)
    if (containers[i].id === key || containers[i].name === key) return containers[i]
  return null
}

// "3 minutes ago" from a Unix time in seconds.
function ago(epoch, nowMs) {
  if (!epoch || epoch <= 0) return ""
  var seconds = Math.max(0, Math.round((nowMs || Date.now()) / 1000 - epoch))
  var steps = [[60, "second"], [60, "minute"], [24, "hour"], [7, "day"], [4.35, "week"], [12, "month"], [Infinity, "year"]]
  var value = seconds
  for (var i = 0; i < steps.length; i++) {
    if (value < steps[i][0]) {
      var n = Math.floor(value)
      if (i === 0 && n < 10) return "just now"
      return n + " " + steps[i][1] + (n === 1 ? "" : "s") + " ago"
    }
    value = value / steps[i][0]
  }
  return ""
}

function shortImage(image) {
  var name = String(image || "")
  return name.replace(/^docker\.io\/library\//, "").replace(/^docker\.io\//, "")
}

// The bar icon's tooltip: how many run, then which (at most eight).
function tooltip(running) {
  var n = (running || []).length
  if (n === 0) return ""
  var head = n === 1 ? "1 container running" : n + " containers running"
  var names = running.slice(0, 8).map(function(c) { return c.name })
  if (n > 8) names.push("and " + (n - 8) + " more")
  return head + "\n" + names.join("\n")
}

function runningCount(containers) {
  return (containers || []).filter(isRunning).length
}

// What a row says while its action runs, from the karchy-containers args.
function busyLabel(args) {
  var verb = args[0] === "compose" ? args[1] : args[0]
  var labels = {
    start: "Starting", stop: "Stopping", restart: "Restarting", remove: "Removing",
    "remove-image": "Removing", up: "Starting", down: "Taking down", prune: "Pruning", forget: "Forgetting"
  }
  return (labels[verb] || verb) + "…"
}
