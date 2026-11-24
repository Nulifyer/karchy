import Quickshell
import Quickshell.Io
import QtQuick
import "ClipboardHistory.js" as ClipboardHistory

// The clipboard history (D-167): what was copied, for the picker
// (Clipboard.qml, Super+Ctrl+V) to paste from, as Win+V does on Windows. It only records; the clipboard itself is kept
// alive after an app closes by karchy-clipboard-persist.service.
//
// Every copy becomes an entry: text, an image, or a file manager's list of
// files (capture.sh decides, and leaves password managers' copies out). An
// entry is a file plus a line in a list:
//   $XDG_RUNTIME_DIR/karchy/clipboard/   this session's entries: memory,
//       this user only, gone at logout or power-off, as on Windows
//   ~/.local/state/karchy/clipboard/     the pinned entries, which stay
// Pinning moves an entry's file from the first to the second, unpinning
// back. The limits (ClipboardHistory.defaultLimits) bound the first; nothing
// that is not pinned is written to disk.
//
// One `wl-paste --watch` tells it about copies; nothing polls.
//
// `clipboard.history: false` in shell.json turns the recording off: the watcher stops and what is not pinned is
// forgotten. Copy and paste go on as before.
Item {
  id: root
  visible: false

  property var shell: null
  property string karchyPath: Quickshell.env("KARCHY_PATH")

  readonly property string sessionDir: Quickshell.env("XDG_RUNTIME_DIR") + "/karchy/clipboard"
  readonly property string pinnedDir: Quickshell.env("HOME") + "/.local/state/karchy/clipboard"
  readonly property string captureScript: karchyPath + "/shell/plugins/clipboard/capture.sh"
  readonly property var folders: [sessionDir, pinnedDir]
  readonly property var limits: ClipboardHistory.defaultLimits

  readonly property var settings: shell && shell.shellConfig && shell.shellConfig.clipboard ? shell.shellConfig.clipboard : ({})
  readonly property bool recording: settings.history !== false
  onRecordingChanged: applyRecording()

  // Newest first. Replaced, never changed in place, so bindings follow.
  property var history: []
  readonly property int count: history.length
  readonly property int unpinnedCount: ClipboardHistory.unpinnedCount(history)

  // The folders exist and both lists were read; copies are recorded from then.
  property bool storeReady: false
  property bool sessionLoaded: false
  property bool pinnedLoaded: false
  property var sessionRead: []
  property var pinnedRead: []
  property bool ready: false
  // Entry id -> true while its file is on the move (pin, unpin).
  property var moving: ({})
  property string savedSession: ""
  property string savedPinned: ""

  function entryFor(id) {
    for (var i = 0; i < history.length; i++) {
      if (history[i].id === id) return history[i]
    }
    return null
  }

  function deleteFiles(paths) {
    var owned = ClipboardHistory.ownedPaths(paths, root.folders)
    if (owned.length > 0) Quickshell.execDetached(["rm", "-f", "--"].concat(owned))
  }

  function save() {
    var session = JSON.stringify(ClipboardHistory.storedEntries(root.history, false)) + "\n"
    var pinned = JSON.stringify(ClipboardHistory.storedEntries(root.history, true)) + "\n"
    if (session !== root.savedSession) {
      root.savedSession = session
      sessionFile.setText(session)
    }
    // The pinned list is on disk; it is written only when it changes.
    if (pinned !== root.savedPinned) {
      root.savedPinned = pinned
      pinnedFile.setText(pinned)
    }
  }

  function apply(result) {
    root.history = result.history
    root.deleteFiles(result.dropped)
    root.save()
  }

  function addJson(line) {
    if (!root.ready || !root.recording) return
    var entry = ClipboardHistory.parseEntryJson(line)
    if (!entry) return
    entry.time = Date.now()
    root.apply(ClipboardHistory.addEntry(root.history, entry, root.limits))
  }

  // Removing what is on the clipboard takes it off the clipboard too, so
  // what was just removed can't be pasted. The newest entry is the one on it.
  function emptyClipboard() {
    Quickshell.execDetached(["wl-copy", "--clear"])
  }

  function remove(id) {
    if (root.moving[id]) return
    if (root.history.length > 0 && root.history[0].id === id) root.emptyClipboard()
    root.apply(ClipboardHistory.removeEntry(root.history, id))
  }

  // Clear all, as on Windows: the pinned entries stay.
  function clear() {
    if (root.history.length > 0 && !root.history[0].pinned) root.emptyClipboard()
    root.apply(ClipboardHistory.clearUnpinned(root.history))
  }

  function setRecording(on) {
    if (!root.shell) return
    root.shell.mutateShellConfig(function(config) {
      if (!config.clipboard || typeof config.clipboard !== "object") config.clipboard = {}
      config.clipboard.history = on === true
    })
  }

  // The watcher records what is on the clipboard when it starts, and then
  // every copy. Started by the switch it leaves the first out: that copy was
  // made while the history was off.
  function watch(skipCurrent) {
    if (watchProc.running) return
    watchProc.command = ["bash", "-c",
      "if [[ $1 == skip ]]; then : >\"$2/.skip-next\"; else rm -f -- \"$2/.skip-next\"; fi\n" +
      "exec setpriv --pdeathsig TERM wl-paste --watch \"$3\"\n",
      "karchy-clipboard-watch", skipCurrent ? "skip" : "all", root.sessionDir, root.captureScript]
    watchProc.running = true
  }

  function applyRecording() {
    if (!root.ready) return
    if (root.recording) {
      root.watch(true)
    } else {
      watchProc.running = false
      root.apply(ClipboardHistory.clearUnpinned(root.history))
    }
  }

  function setMoving(id, on) {
    var next = Object.assign({}, root.moving)
    if (on) next[id] = true
    else delete next[id]
    root.moving = next
  }

  function togglePin(id) {
    var entry = root.entryFor(id)
    if (!entry || root.moving[id]) return

    var pin = !entry.pinned
    var target = ClipboardHistory.movedPath(entry, pin ? root.pinnedDir : root.sessionDir)
    if (!ClipboardHistory.ownsPath(entry.path, root.folders)) return

    root.setMoving(id, true)
    var move = moveComponent.createObject(root, {
      entryId: id, pin: pin, target: target,
      command: ["mv", "-f", "--", entry.path, target]
    })
    move.running = true
  }

  // Puts the entry back on the clipboard and pastes it into the focused
  // window, or only puts it back. Either way the watcher sees a copy and the
  // entry moves to the top.
  function paste(id, copyOnly) {
    var entry = root.entryFor(id)
    if (!entry) return
    var command = [root.karchyPath + "/bin/karchy-clipboard-paste-file"]
    if (copyOnly) command.push("--copy-only")
    Quickshell.execDetached(command.concat([entry.mime, entry.path]))
  }

  function open(id) {
    var entry = root.entryFor(id)
    if (entry) Quickshell.execDetached([root.karchyPath + "/bin/karchy-clipboard-open", entry.type, entry.path])
  }

  function start() {
    if (root.ready || !root.sessionLoaded || !root.pinnedLoaded) return

    var result = ClipboardHistory.enforce(ClipboardHistory.merge(root.sessionRead, root.pinnedRead), root.limits)
    root.history = result.history
    root.deleteFiles(result.dropped)
    root.savedSession = ""
    root.savedPinned = JSON.stringify(ClipboardHistory.storedEntries(root.history, true)) + "\n"
    root.ready = true
    root.save()

    // Files no entry names are leftovers (a crash between a copy and its
    // line): what is not in the history is not kept.
    var known = []
    for (var i = 0; i < root.history.length; i++) known.push(root.history[i].path)
    sweepProc.command = ["bash", "-c",
      "declare -A known\n" +
      "for path in \"${@:3}\"; do known[$path]=1; done\n" +
      "for file in \"$1\"/* \"$1\"/.incoming.* \"$2\"/*; do\n" +
      "  [[ -f $file && $file != *.json && -z ${known[$file]:-} ]] && rm -f -- \"$file\"\n" +
      "done\n" +
      "exit 0\n",
      "karchy-clipboard-sweep", root.sessionDir, root.pinnedDir].concat(known)
    sweepProc.running = true
  }

  Component.onCompleted: prepareProc.running = true

  // Once at startup: the two private folders, and no watcher left behind by
  // an earlier shell. The pdeathsig on the watcher makes the kernel end it
  // whenever this shell exits, however it exits.
  Process {
    id: prepareProc
    command: ["bash", "-c",
      "umask 077\n" +
      "pkill -f 'wl-paste .*--watch .*/shell/plugins/clipboard/capture\\.sh' 2>/dev/null\n" +
      "for dir in \"$1\" \"$2\"; do\n" +
      "  mkdir -p -- \"$dir\" && chmod 700 -- \"$dir\" || exit 1\n" +
      "done\n",
      "karchy-clipboard-prepare", root.sessionDir, root.pinnedDir]
    onExited: function(code) { root.storeReady = code === 0 }
  }

  FileView {
    id: sessionFile
    path: root.storeReady ? root.sessionDir + "/history.json" : ""
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.sessionRead = ClipboardHistory.parseEntries(text())
      root.sessionLoaded = true
      root.start()
    }
    onLoadFailed: {
      root.sessionLoaded = true
      root.start()
    }
  }

  FileView {
    id: pinnedFile
    path: root.storeReady ? root.pinnedDir + "/pinned.json" : ""
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root.pinnedRead = ClipboardHistory.parseEntries(text())
      root.pinnedLoaded = true
      root.start()
    }
    onLoadFailed: {
      root.pinnedLoaded = true
      root.start()
    }
  }

  // The sweep first, so it never meets a file a capture is still writing;
  // then the watcher.
  Process {
    id: sweepProc
    onExited: {
      if (root.recording) root.watch(false)
      else root.applyRecording()
    }
  }

  Process {
    id: watchProc
    onExited: watchRestartTimer.restart()
    stdout: SplitParser {
      onRead: function(line) { root.addJson(line) }
    }
  }

  // A watcher that dies takes the history with it, silently: copying still
  // works and the old entries are still there, so nothing would be recorded
  // until the next shell start. Bring it back instead.
  Timer {
    id: watchRestartTimer
    interval: 1000
    repeat: false
    onTriggered: if (root.ready && root.recording) root.watch(false)
  }

  Component {
    id: moveComponent
    Process {
      property string entryId: ""
      property bool pin: false
      property string target: ""
      onExited: function(code) {
        root.setMoving(entryId, false)
        if (code === 0) root.apply(ClipboardHistory.setPinned(root.history, entryId, pin, target, root.limits))
        destroy()
      }
    }
  }
}
