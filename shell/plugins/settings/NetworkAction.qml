import Quickshell.Io
import QtQuick

// One command run for Settings › Network: what it printed, and the error to
// show. `polkit` marks commands that ask for a password: pkexec exits 126
// when the prompt is dismissed and 127 when authorization isn't granted,
// and neither is a failure to report; the control just stays as it was.
//
//   NetworkAction { id: act; polkit: true }
//   act.start(["karchy-network-dns", "set", "provider=quad9"], function(ok, out) { … })
// `input` goes to the command's stdin as one line (a password: argv can be
// read by every user).
Item {
  id: root

  property bool polkit: false
  // True from start to the answer, through both stages of an elevated run:
  // a control that is busy for it stays busy without a gap.
  readonly property bool running: proc.running || _between
  property bool _between: false
  // The command's own words when it failed, "" otherwise (karchy's commands
  // write one sentence for people on stderr).
  property string error: ""
  property string output: ""
  // What the caller is doing with it, for a busy look on the right control.
  property string tag: ""

  property var _done: null
  property bool _exited: false
  property int _code: 0
  property int _streams: 0
  property string _input: ""
  // Elevated in two stages (below): the status command still to run.
  property var _then: null

  // karchy's root helpers and the status each prints after a change.
  // Settings runs `pkexec /usr/bin/<helper> set …` itself, so the shell is
  // the caller polkit sees every time and one password covers changes for a
  // few minutes (auth_admin_keep). Through the helper's own non-root path,
  // each change was a new caller and asked again.
  readonly property var _elevated: ({
    "karchy-network-dns": ["status"],
    "karchy-network-country": ["status", "--json"],
    "karchy-trusted-networks": ["status"]
  })

  visible: false

  function start(cmd, done, input) {
    if (running) return false
    _input = input === undefined ? "" : String(input)
    error = ""
    _done = done || null
    _exited = false
    _streams = 0
    _then = null
    if (polkit && cmd.length > 1 && cmd[1] === "set" && _elevated[cmd[0]]) {
      _then = [cmd[0]].concat(_elevated[cmd[0]])
      cmd = ["pkexec", "/usr/bin/" + cmd[0]].concat(cmd.slice(1))
    }
    proc.command = cmd
    proc.running = true
    return true
  }

  // Both streams and the exit, in whatever order they arrive; `force` when a
  // stream's end never came.
  function _finish(force) {
    if (!_exited || (_streams < 2 && !force)) return
    streamsLate.stop()
    var cancelled = polkit && (_code === 126 || _code === 127)
    // The change went through as root: now the status, for the caller.
    if (_then && _code === 0) {
      var next = _then
      _then = null
      _exited = false
      _streams = 0
      _between = true
      // Next turn of the event loop: not from inside the first run's exit.
      Qt.callLater(function() {
        proc.command = next
        proc.running = true
        root._between = false
      })
      return
    }
    output = outText.text
    error = _code === 0 || cancelled ? "" : (errText.text.trim() || "The command stopped with code " + _code + ".")
    var done = _done
    _done = null
    if (typeof done === "function") done(_code === 0, outText.text, cancelled)
  }

  Process {
    id: proc
    stdinEnabled: root._input !== ""
    onStarted: if (root._input !== "") { write(root._input + "\n"); root._input = "" }
    stdout: StdioCollector { id: outText; waitForEnd: true; onStreamFinished: { root._streams++; root._finish(false) } }
    stderr: StdioCollector { id: errText; waitForEnd: true; onStreamFinished: { root._streams++; root._finish(false) } }
    onExited: function(code) {
      root._code = code
      root._exited = true
      root._finish(false)
      if (root._streams < 2) streamsLate.restart()
    }
  }

  Timer { id: streamsLate; interval: 500; onTriggered: root._finish(true) }
}
