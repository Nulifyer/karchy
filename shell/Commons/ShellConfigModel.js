// How ~/.config/karchy/shell.json and karchy's defaults (karchy/shell.json)
// become the shell's config, and what is written back (D-56).
//
// Loading: the user's file is laid over the defaults. Objects merge key by
// key; an array or a plain value in the user's file replaces the default
// whole. So a file that sets only bar.style keeps following every other
// default, while a file that sets bar.layout.right owns that one list.
//
// Saving: only what differs from the defaults is written. A key that matches
// the default is left out, so it goes on following karchy's defaults. A key
// cannot be removed, only given another value: one the defaults carry and the
// saved config lacks comes back from the defaults.
//
// A full copy of the defaults, as /etc/skel installed and as earlier karchy
// saved on the first Settings change, loads the same way: every key it holds
// wins. It shrinks to its differences on the next save. Values in it that
// differ from today's defaults are kept, because a default that changed since
// the copy was made cannot be told from the user's own choice.
//
// bin/karchy-shell-config does the same in jq for the commands that edit the
// file; keep the two in step.

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function clone(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value))
}

function sameJson(a, b) {
  if (a === b) return true
  if (isPlainObject(a) && isPlainObject(b)) {
    var keys = Object.keys(a)
    if (keys.length !== Object.keys(b).length) return false
    for (var i = 0; i < keys.length; i++) {
      if (!Object.prototype.hasOwnProperty.call(b, keys[i])) return false
      if (!sameJson(a[keys[i]], b[keys[i]])) return false
    }
    return true
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false
    for (var j = 0; j < a.length; j++) {
      if (!sameJson(a[j], b[j])) return false
    }
    return true
  }
  return false
}

// The config the shell runs with: `user` over `defaults`.
function merge(defaults, user) {
  if (!isPlainObject(defaults) || !isPlainObject(user)) return clone(user === undefined ? defaults : user)

  var out = clone(defaults)
  for (var key in user) {
    if (!Object.prototype.hasOwnProperty.call(user, key)) continue
    out[key] = merge(defaults[key], user[key])
  }
  return out
}

// What to save so that merge(defaults, overrides(defaults, config)) gives
// `config` back: the keys of `config` that differ from `defaults`.
function overrides(defaults, config) {
  if (!isPlainObject(defaults) || !isPlainObject(config)) return clone(config)

  var out = {}
  for (var key in config) {
    if (!Object.prototype.hasOwnProperty.call(config, key)) continue
    if (!Object.prototype.hasOwnProperty.call(defaults, key)) out[key] = clone(config[key])
    else if (!sameJson(defaults[key], config[key])) {
      var inner = overrides(defaults[key], config[key])
      // Two objects that differ only by a key the config lacks leave nothing to save.
      var nothing = isPlainObject(defaults[key]) && isPlainObject(config[key]) && Object.keys(inner).length === 0
      if (!nothing) out[key] = inner
    }
  }
  return out
}

// The text of the user's file for `config`. Always carries version 1, which
// marks the file as one the shell may load.
function userFileFor(defaults, config) {
  var out = overrides(defaults, config)
  if (!isPlainObject(out)) out = {}
  var ordered = { version: 1 }
  for (var key in out) {
    if (key !== "version") ordered[key] = out[key]
  }
  return ordered
}

if (typeof module !== "undefined") {
  module.exports = {
    merge: merge,
    overrides: overrides,
    userFileFor: userFileFor,
    sameJson: sameJson
  }
}
