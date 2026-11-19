import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Instance, not a singleton — see BarWidgetRegistry for rationale.
//
// Every plugin is karchy's own: the first-party ones in shell/plugins, and
// the add-ons that karchy's add-on packages (built from addons/) install
// under /usr/share/karchy/plugins. All of them are trusted alike (D-111).
QtObject {
  id: registry

  // Add-on packages install their shell UI here, one folder per plugin id.
  // Root-owned: the shell loads no plugin from the home folder.
  property string pluginsDir: "/usr/share/karchy/plugins"

  // Set by shell.qml at startup: the plugins that ship in the shell itself.
  property string firstPartyDir: ""

  // Wired by shell.qml so the registry can read the canonical shell.json
  // without owning file IO itself. shellConfigProvider returns the current
  // effective shell config; shellConfigMutator takes a function that receives
  // a deep-cloned config it can mutate in place and persists the result.
  property var shellConfigProvider: null
  property var shellConfigMutator: null

  // { pluginId: manifest } — each manifest has __sourceDir stamped in.
  property var installedPlugins: ({})
  property int registryRevision: 0
  property bool scanning: false
  property string lastEnableError: ""

  signal pluginsChanged()
  signal scanFinished()
  signal pluginLoadFailed(string id, string error)
  signal addonChanged(string id)

  // ---------------------------------------------------------------- helpers

  function validateManifest(manifest, sourcePath) {
    if (!Util.isPlainObject(manifest)) {
      console.warn("PluginRegistry: manifest is not an object at " + sourcePath)
      return null
    }
    if (manifest.schemaVersion !== 1) {
      console.warn("PluginRegistry: unsupported schemaVersion at " + sourcePath)
      return null
    }
    var required = ["id", "name", "version", "kinds", "entryPoints"]
    for (var i = 0; i < required.length; i++) {
      if (manifest[required[i]] === undefined) {
        console.warn("PluginRegistry: missing required field '" + required[i] + "' at " + sourcePath)
        return null
      }
    }
    if (!Array.isArray(manifest.kinds) || manifest.kinds.length === 0) {
      console.warn("PluginRegistry: kinds must be a non-empty array at " + sourcePath)
      return null
    }
    if (!Util.isPlainObject(manifest.entryPoints)) {
      console.warn("PluginRegistry: entryPoints must be an object at " + sourcePath)
      return null
    }
    if (manifest.barWidget !== undefined && Util.isPlainObject(manifest.barWidget)
        && manifest.barWidget.defaultSection !== undefined) {
      var defaultSection = String(manifest.barWidget.defaultSection)
      if (Util.barSections.indexOf(defaultSection) === -1) {
        console.warn("PluginRegistry: invalid barWidget.defaultSection at " + sourcePath)
        return null
      }
    }
    return manifest
  }

  function entryPointUrl(manifest, kind) {
    if (!Util.isPlainObject(manifest)) return ""
    var ep = manifest.entryPoints ? manifest.entryPoints[kind] : null
    var dir = manifest.__sourceDir || ""
    if (!ep || !dir) return ""
    return Util.fileUrl(dir.replace(/\/$/, "") + "/" + String(ep))
  }

  function hasKind(manifest, kind) {
    return !!manifest && Array.isArray(manifest.kinds) && manifest.kinds.indexOf(kind) !== -1
  }

  // Every installed plugin is on unless shell.json lists it in
  // disabledPlugins[]. A bar widget that is on can be loaded; whether it sits
  // in the bar is inBar(). The bar itself (karchy.bar) cannot be switched off.
  function isEnabled(id) {
    var key = Util.canonicalWidgetId(String(id))
    var manifest = installedPlugins[key]
    if (!manifest) return false
    if (hasKind(manifest, "bar")) return true
    return !isDisabled(shellConfigProvider ? shellConfigProvider() : null, key)
  }

  function isDisabled(config, id) {
    return Util.isPlainObject(config) && Array.isArray(config.disabledPlugins)
      && config.disabledPlugins.indexOf(Util.canonicalWidgetId(String(id))) !== -1
  }

  // A bar widget is on when it sits in the bar. That is a different question
  // from isEnabled(), which decides whether the widget's component is loaded
  // at all — a widget stays loadable so it can be put back, and so a plugin
  // that is both a widget and a menu (karchy.menu) cannot be locked out of
  // the shell by taking its button off the bar.
  function inBar(id) {
    var config = shellConfigProvider ? shellConfigProvider() : null
    return findBarLocation(config, id, "").found
  }

  // A manifest's "center" means beside the clock, so it lands in centerEnd, as
  // a widget that names no section does; in the box it would push the clock
  // off center.
  function defaultBarWidgetSection(manifest) {
    var metadata = manifest && Util.isPlainObject(manifest.barWidget) ? manifest.barWidget : null
    var section = metadata ? String(metadata.defaultSection || "") : ""
    return Util.barSections.indexOf(section) !== -1 && section !== "center" ? section : "centerEnd"
  }

  function barEntryId(entry) {
    return Util.canonicalWidgetId(String(Util.isPlainObject(entry) ? entry.id : entry || ""))
  }

  function findBarLocation(config, id, section) {
    if (!Util.isPlainObject(config) || !Util.isPlainObject(config.bar)
        || !Util.isPlainObject(config.bar.layout)) return { found: false }
    var key = Util.canonicalWidgetId(String(id))
    var sections = Util.barSections
    for (var s = 0; s < sections.length; s++) {
      if (section && sections[s] !== section) continue
      var entries = config.bar.layout[sections[s]]
      if (!Array.isArray(entries)) continue
      for (var i = 0; i < entries.length; i++) {
        if (barEntryId(entries[i]) === key)
          return { found: true, kind: "bar", section: sections[s], index: i }
      }
    }
    return { found: false }
  }

  // The tray section is drawn inside the tray, so the tray cannot go there.
  function barTarget(config, placement, fallbackSection, id) {
    var target = placement || {}
    var section = Util.barSections.indexOf(String(target.section || "")) !== -1
      ? String(target.section) : fallbackSection
    var tray = id === "karchy.tray"
    var trayError = { error: "the tray cannot go in its own drawer" }
    if (tray && section === "tray") return trayError
    var relativeId = String(target.before || target.after || "")
    if (relativeId) {
      var relative = findBarLocation(config, relativeId, section && target.section ? section : "")
      if (!relative.found) return { error: "could not find target widget " + relativeId }
      if (tray && relative.section === "tray") return trayError
      return {
        section: relative.section,
        index: relative.index + (target.after ? 1 : 0)
      }
    }

    if (!Array.isArray(config.bar.layout[section])) config.bar.layout[section] = []
    if (target.index !== undefined && target.index !== null) {
      var requested = Math.max(0, Math.floor(Number(target.index)))
      return { section: section, index: Math.min(requested, config.bar.layout[section].length) }
    }

    // A section without an anchor (the tray's drawer, for one) takes a widget
    // put there at its end.
    var anchors = { left: "karchy.workspaces", centerEnd: "karchy.media", right: "karchy.tray" }
    if (!anchors[section]) return { section: section, index: config.bar.layout[section].length }
    var anchor = findBarLocation(config, anchors[section], section)
    return {
      section: section,
      index: anchor.found ? anchor.index + 1 : config.bar.layout[section].length
    }
  }

  function moveBarEntry(config, id, placement) {
    var key = Util.canonicalWidgetId(String(id))
    var source
    if (placement.fromIndex !== undefined && placement.fromIndex !== null) {
      var fromSection = String(placement.fromSection || "")
      if (!fromSection) return "from-index requires from-section"
      var entries = config.bar.layout[fromSection]
      var fromIndex = Math.floor(Number(placement.fromIndex))
      if (!Array.isArray(entries) || fromIndex < 0 || fromIndex >= entries.length)
        return "no widget at " + fromSection + "[" + fromIndex + "]"
      if (barEntryId(entries[fromIndex]) !== key)
        return "widget at " + fromSection + "[" + fromIndex + "] is not " + key
      source = { found: true, section: fromSection, index: fromIndex }
    } else {
      source = findBarLocation(config, key, String(placement.fromSection || ""))
      if (!source.found) return "could not find widget " + key
    }

    var entry = config.bar.layout[source.section][source.index]
    config.bar.layout[source.section].splice(source.index, 1)
    var target = barTarget(config, placement, source.section, key)
    if (target.error) {
      config.bar.layout[source.section].splice(source.index, 0, entry)
      return target.error
    }
    config.bar.layout[target.section].splice(target.index, 0, entry)
    return ""
  }

  function moveBarWidget(id, placement) {
    var error = ""
    shellConfigMutator(function(config) {
      ensureConfigShape(config)
      error = moveBarEntry(config, id, placement || {})
    })
    if (error) return error
    registryRevision++
    pluginsChanged()
    return ""
  }

  // put is the unattended verb: where enable errors, it falls back, and it
  // leaves a widget that is already on the bar where its owner put it.
  function putBarWidget(id, placement) {
    if (inBar(id)) return ""
    var config = shellConfigProvider ? shellConfigProvider() : null
    // The manifest scan is a subprocess and IPC answers before it returns, so
    // an id it has not reached yet is not one that does not exist.
    if (scanning && !installedPlugins[Util.canonicalWidgetId(String(id))]) return "not ready"
    var target = Util.isPlainObject(placement) ? Util.cloneJson(placement) : {}
    var relativeId = String(target.before || target.after || "")
    if (relativeId) {
      if (!findBarLocation(config, relativeId, String(target.section || "")).found) {
        delete target.before
        delete target.after
      }
    }
    if (setEnabled(id, true, target)) return ""
    return lastEnableError || "unknown"
  }

  function setBarWidget(id, key, value, selector) {
    var error = ""
    shellConfigMutator(function(config) {
      ensureConfigShape(config)
      var location
      var requested = selector || {}
      var section = String(requested.fromSection || requested.section || "")
      var index = requested.fromIndex !== undefined && requested.fromIndex !== null
        ? requested.fromIndex : requested.index
      if (index !== undefined && index !== null) {
        if (!section) {
          error = "index requires section"
          return
        }
        var entries = config.bar.layout[section]
        var numericIndex = Math.floor(Number(index))
        if (!Array.isArray(entries) || numericIndex < 0 || numericIndex >= entries.length) {
          error = "no widget at " + section + "[" + numericIndex + "]"
          return
        }
        location = { found: true, section: section, index: numericIndex }
      } else {
        location = findBarLocation(config, id, section)
      }
      if (!location.found) {
        error = "could not find widget " + id
        return
      }
      if (barEntryId(config.bar.layout[location.section][location.index]) !== String(id)) {
        error = "widget at " + location.section + "[" + location.index + "] is not " + id
        return
      }
      var entry = config.bar.layout[location.section][location.index]
      if (!Util.isPlainObject(entry)) {
        error = "widget entry must be an object"
        return
      }
      entry[String(key)] = value
    })
    if (error) return error
    registryRevision++
    pluginsChanged()
    return ""
  }

  function ensureConfigShape(config) {
    if (!Util.isPlainObject(config.bar)) config.bar = { layout: {} }
    if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = {}
    var sections = Util.barSections
    for (var i = 0; i < sections.length; i++) {
      if (!Array.isArray(config.bar.layout[sections[i]])) config.bar.layout[sections[i]] = []
    }
  }

  // Built-ins and add-ons are loaded by default, so shell.json records only
  // the deviation: a bar widget's place in bar.layout, a plugin switched off
  // in disabledPlugins[].
  function removeDisabled(config, id) {
    if (!Array.isArray(config.disabledPlugins)) return
    config.disabledPlugins = config.disabledPlugins.filter(function(entry) { return entry !== id })
    if (config.disabledPlugins.length === 0) delete config.disabledPlugins
  }

  // A bar widget switched off keeps its place and options in
  // bar.removedWidgets, so switching it on again puts it back there rather
  // than at its section's default spot.
  function rememberRemovedWidget(config, id, location) {
    if (!Util.isPlainObject(config.bar.removedWidgets)) config.bar.removedWidgets = {}
    config.bar.removedWidgets[id] = {
      section: location.section,
      index: location.index,
      entry: Util.cloneJson(config.bar.layout[location.section][location.index])
    }
  }

  function restoreRemovedWidget(config, id) {
    var removed = Util.isPlainObject(config.bar.removedWidgets) ? config.bar.removedWidgets[id] : null
    if (!removed || Util.barSections.indexOf(String(removed.section)) === -1) return false
    var list = config.bar.layout[removed.section]
    var index = Math.min(Math.max(0, Math.floor(Number(removed.index) || 0)), list.length)
    var entry = Util.isPlainObject(removed.entry) || typeof removed.entry === "string" ? removed.entry : { id: id }
    list.splice(index, 0, entry)
    delete config.bar.removedWidgets[id]
    if (Object.keys(config.bar.removedWidgets).length === 0) delete config.bar.removedWidgets
    return true
  }

  function addDisabled(config, id) {
    if (isDisabled(config, id)) return
    if (!Array.isArray(config.disabledPlugins)) config.disabledPlugins = []
    config.disabledPlugins.push(id)
  }

  // Enabling a bar widget puts it in the bar (where it was when it was taken
  // off, unless a placement says otherwise); disabling takes it off. Any
  // other plugin is switched with disabledPlugins[].
  function setEnabled(id, value, placement) {
    var key = Util.canonicalWidgetId(String(id))
    lastEnableError = ""
    if (!shellConfigMutator) {
      console.warn("PluginRegistry.setEnabled called before shellConfigMutator wired")
      return false
    }
    var manifest = installedPlugins[key]
    if (!manifest) {
      console.warn("PluginRegistry.setEnabled: unknown plugin " + key)
      return false
    }
    if (hasKind(manifest, "bar")) {
      if (value) return true
      lastEnableError = "the bar cannot be switched off"
      return false
    }
    var isBarWidget = hasKind(manifest, "bar-widget")
    var hasPlacement = !!placement && Object.keys(placement).length > 0
    shellConfigMutator(function(config) {
      ensureConfigShape(config)

      // A placement that cannot be honoured is refused before anything
      // changes: a missing neighbour, or the tray asked into its own drawer.
      if (value && isBarWidget && hasPlacement) {
        var requested = barTarget(config, placement, defaultBarWidgetSection(manifest), key)
        if (requested.error) {
          lastEnableError = requested.error
          return
        }
      }

      var location = findBarLocation(config, key, "")
      if (value) {
        removeDisabled(config, key)
        if (!isBarWidget) return
        if (location.found) {
          if (hasPlacement) moveBarEntry(config, key, placement)
        } else if (hasPlacement || !restoreRemovedWidget(config, key)) {
          var target = barTarget(config, placement || {}, defaultBarWidgetSection(manifest), key)
          config.bar.layout[target.section].splice(target.index, 0, { id: key })
        }
        return
      }

      if (location.found) {
        rememberRemovedWidget(config, key, location)
        config.bar.layout[location.section].splice(location.index, 1)
      }
      // Taking a widget off the bar is the whole story for a widget. Anything
      // else loads by default, so switching it off has to be stated.
      if (!isBarWidget) addDisabled(config, key)
    })
    if (lastEnableError) return false
    registryRevision++
    pluginsChanged()
    return true
  }

  // ---------------------------------------------------------------- scanning

  // Output format produced by the rescan script:
  //   ===<absolute-source-dir>===
  //   ... raw manifest.json content ...
  //   === EOM ===
  // (repeating for every manifest found)
  function parseScanOutput(text) {
    var lines = String(text || "").split("\n")
    var merged = {}
    var currentSource = null
    var currentJson = []

    function flush() {
      if (!currentSource) return
      var raw = currentJson.join("\n").trim()
      try {
        var manifest = JSON.parse(raw)
        manifest.__sourceDir = currentSource
        var validated = validateManifest(manifest, currentSource + "/manifest.json")
        // The shell's own plugins are scanned first, so an add-on can never
        // stand in for one of them.
        if (validated && merged[validated.id])
          console.warn("PluginRegistry: duplicate plugin id " + validated.id + " at " + currentSource + ", ignored")
        else if (validated)
          merged[validated.id] = validated
      } catch (e) {
        console.warn("PluginRegistry: bad manifest at " + currentSource + ": " + e)
      }
      currentSource = null
      currentJson = []
    }

    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var startMatch = line.match(/^===(.+)===$/)
      if (startMatch && line !== "=== EOM ===") {
        flush()
        currentSource = startMatch[1].replace(/\/$/, "")
        currentJson = []
        continue
      }
      if (line === "=== EOM ===") {
        flush()
        continue
      }
      if (currentSource) currentJson.push(line)
    }
    flush()

    installedPlugins = merged
    registryRevision++
    scanning = false
    pluginsChanged()
    scanFinished()
  }

  property Process scanProcess: Process {
    onExited: function(exitCode) {
      var output = scanStdout.text || ""
      registry.parseScanOutput(output)
    }
    stdout: StdioCollector {
      id: scanStdout
      waitForEnd: true
    }
  }

  // Quickshell does not take its Process children with it when it stops, so
  // every shell restart leaves this watcher running, reparented to init
  // (63 of them on one long-lived machine). Before starting our own, stop
  // any plugin watcher whose parent is no longer a shell; a live shell's
  // watcher — parented to it — is left alone. The [i] keeps this script's
  // own command line from matching its search.
  property Process watcherReaper: Process {
    onExited: {
      addonWatcher.running = true
      registry.rescan()
    }
  }

  function reapOrphanedPluginWatchers() {
    watcherReaper.command = ["bash", "-c",
      "for p in $(pgrep -f '[i]notifywait -m -r -q -e close_write,create,delete,move' || true); do "
        + "tr '\\0' '\\n' < \"/proc/$p/cmdline\" 2>/dev/null | grep -Fxq \"$1\" || continue; "
        + "parent=$(ps -o ppid= -p \"$p\" 2>/dev/null | tr -d ' '); "
        + "[[ $parent =~ ^[0-9]+$ ]] || continue; "
        + "case \"$(ps -o comm= -p \"$parent\" 2>/dev/null)\" in quickshell|qs) ;; *) kill \"$p\" 2>/dev/null || true ;; esac; "
        + "done; true",
      "watcher-reaper", registry.pluginsDir]
    watcherReaper.running = true
  }

  // A graceful stop takes the watcher with it; the reaper above covers the
  // stops that never run this (a killed or crashed shell).
  Component.onDestruction: {
    addonWatcherRestart.stop()
    addonWatcher.running = false
  }

  // Installing, upgrading or removing an add-on package changes this folder,
  // and the shell reloads its plugins to match.
  property Process addonWatcher: Process {
    command: [
      "inotifywait",
      "-m",
      "-r",
      "-q",
      "-e",
      "close_write,create,delete,move",
      "--format",
      "%w%f",
      registry.pluginsDir
    ]
    stdout: SplitParser {
      onRead: function(path) {
        var pluginId = registry.addonIdForPath(path)
        if (pluginId) registry.addonChanged(pluginId)
      }
    }
    onExited: addonWatcherRestart.restart()
  }

  property Timer addonWatcherRestart: Timer {
    interval: 1000
    onTriggered: addonWatcher.running = true
  }

  function rescan() {
    if (scanning) return
    scanning = true
    // $0 = the shell's own plugins, $1 = add-ons. The shell's own come first
    // (parseScanOutput keeps the first of a duplicate id). They may be grouped
    // one level deeper, e.g. panels/audio or services/battery, and bar widgets
    // can carry sibling manifests such as widgets/Clock.manifest.json so
    // several widgets live in one directory. Add-ons sit at the top level of
    // /usr/share/karchy/plugins.
    var script = ""
      + "emit_manifest() { local manifest=\"$1\"; local sub; "
      + "  if [[ ${manifest##*/} == \"manifest.json\" ]]; then sub=\"${manifest%/manifest.json}\"; else sub=\"${manifest%/*}\"; fi; "
      + "  printf '===%s===\\n' \"$sub\"; "
      + "  printf '%s\\n' \"$(<\"$manifest\")\"; "
      + "  printf '\\n=== EOM ===\\n'; "
      + "}; "
      + "[[ -d \"$0\" ]] && while IFS= read -r manifest; do emit_manifest \"$manifest\"; done < <(find \"$0\" -mindepth 2 -maxdepth 3 -type f \\( -name manifest.json -o -name '*.manifest.json' \\) | sort); "
      + "for sub in \"$1\"/*/; do [[ -f \"$sub/manifest.json\" ]] && emit_manifest \"$sub/manifest.json\"; done; true"
    scanProcess.command = ["bash", "-c", script, registry.firstPartyDir, registry.pluginsDir]
    scanProcess.running = true
  }

  function addonIdForPath(filePath) {
    var base = pluginsDir.replace(/\/$/, "") + "/"
    var path = String(filePath || "").trim()
    if (path.indexOf(base) !== 0) return ""

    var relative = path.slice(base.length)
    // Hidden entries are not plugins.
    if (relative.indexOf(".") === 0) return ""

    var slash = relative.indexOf("/")
    return slash === -1 ? relative : relative.slice(0, slash)
  }

  Component.onCompleted: reapOrphanedPluginWatchers()
}
