//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd
import qs.Commons
import qs.Commons as Commons
import "greeter"

// karchy's login screen: greetd's greeter (D-130). It runs as the `greeter`
// user in a bare Hyprland (system/greetd/greeter starts both), shows
// greeter/GreeterView.qml on every display, hands the password to greetd,
// and starts the session greetd then allows (/usr/lib/karchy/session).
//
// It shares the desktop shell's tokens and controls (qs.Commons, qs.Ui) but
// none of its plugins, and always wears the default theme: KARCHY_THEME_DIR
// points Commons.Color at it (system/greetd/greeter).
//
// When this screen can't come up, greetd still has a login: the launcher
// falls back to the text greeter. It tells by the two marks made here:
// `ready` once a display shows the screen, and a clean exit after a session
// was started.
//
// KARCHY_GREETER_PREVIEW=1 runs it without greetd, as a window, to look at:
// "karchy-test" is the right password, the power buttons do nothing.
ShellRoot {
  id: root

  readonly property bool preview: Quickshell.env("KARCHY_GREETER_PREVIEW") === "1"
  readonly property string sessionCommand: Quickshell.env("KARCHY_GREETER_SESSION") || "/usr/lib/karchy/session"
  // The launcher's folder for the `ready` mark; none in a preview.
  readonly property string runDir: Quickshell.env("KARCHY_GREETER_RUN") || ""
  // Where the last person to sign in is remembered (tmpfiles.d makes it).
  readonly property string lastUserPath: (Quickshell.env("KARCHY_GREETER_STATE") || "/var/lib/karchy-greeter") + "/last-user"

  property var users: []
  property int userIndex: 0
  property string phase: "idle"
  property string failure: ""
  property string passwordText: ""
  // The try under way: its password, whether greetd has had it, and what PAM
  // said along the way (the reason shown when the try fails).
  property string pendingPassword: ""
  property bool answered: false
  property var pamNotes: []
  property bool canSuspend: true
  property bool readyMarked: false

  readonly property var user: users.length > 0 ? users[Math.min(userIndex, users.length - 1)] : null

  // The layout Hyprland was given (system/greetd/hyprland.lua reads the same
  // file); named on the screen unless it is plain US.
  readonly property string keyboardLayout: {
    var layout = "", variant = ""
    var lines = String(vconsoleFile.text() || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*(XKBLAYOUT|XKBVARIANT)\s*=\s*"?([^"#]*?)"?\s*$/)
      if (!m) continue
      if (m[1] === "XKBLAYOUT") layout = m[2]
      else variant = m[2]
    }
    if (layout === "" || (layout === "us" && variant === "")) return ""
    return variant !== "" ? layout + " (" + variant + ")" : layout
  }

  function fail(message) {
    pendingPassword = ""
    answered = false
    pamNotes = []
    failure = message
    phase = "idle"
  }

  function submit(password) {
    if (phase !== "idle" || !user || password.length === 0) return
    failure = ""
    passwordText = ""
    pendingPassword = password
    answered = false
    pamNotes = []
    phase = "checking"
    if (preview) {
      previewTimer.restart()
      return
    }
    Greetd.createSession(user.name)
  }

  function stepUser(delta) {
    if (phase !== "idle" || users.length < 2) return
    userIndex = (userIndex + delta + users.length) % users.length
    failure = ""
    passwordText = ""
  }

  function power(action) {
    if (phase === "starting" || powerProc.running) return
    failure = ""
    if (preview) return
    powerProc.action = action
    powerProc.command = ["systemctl", action, "--no-wall"]
    powerProc.running = true
  }

  // People who can sign in: regular accounts with a login shell, in the
  // order of /etc/passwd, each with the name to show.
  function loadUsers(raw, last) {
    var found = []
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var f = lines[i].split(":")
      if (f.length < 7) continue
      var uid = Number(f[2])
      if (!(uid >= 1000 && uid < 60000)) continue
      if (/(nologin|false)$/.test(f[6])) continue
      var full = f[4].split(",")[0].trim()
      found.push({ name: f[0], label: full !== "" ? full : f[0] })
    }
    users = found
    var wanted = String(last || "").trim()
    for (var j = 0; j < found.length; j++)
      if (found[j].name === wanted) userIndex = j
  }

  Component.onCompleted: loadUsers(passwdFile.text(), lastUserFile.text())

  FileView {
    id: passwdFile
    path: "/etc/passwd"
    blockLoading: true
    printErrors: false
  }

  FileView {
    id: lastUserFile
    path: root.lastUserPath
    blockLoading: true
    printErrors: false
  }

  FileView {
    id: vconsoleFile
    path: "/etc/vconsole.conf"
    blockLoading: true
    printErrors: false
  }

  Connections {
    target: Greetd
    enabled: !root.preview

    function onAuthMessage(message, error, responseRequired, echoResponse) {
      if (!responseRequired) {
        // Something PAM wants said, such as "The account is locked due to 10
        // failed logins." It is the reason if this try fails.
        var note = String(message || "").trim()
        if (note !== "") root.pamNotes = root.pamNotes.concat([note])
        return
      }
      if (root.answered) {
        // A second question (a new password for an expired one, a code):
        // this screen has one box, so it can't answer.
        Greetd.cancelSession()
        root.fail(Commons.I18n.t("greeter.needsMore"))
        return
      }
      root.answered = true
      Greetd.respond(root.pendingPassword)
      root.pendingPassword = ""
    }

    function onAuthFailure(message) {
      root.fail(root.pamNotes.length > 0 ? root.pamNotes.join(" ") : Commons.I18n.t("greeter.wrongPassword"))
    }

    function onReadyToLaunch() {
      root.phase = "starting"
      root.pendingPassword = ""
      if (root.user) lastUserFile.setText(root.user.name + "\n")
      // greetd starts the session once this greeter is gone: quit after.
      Greetd.launch([root.sessionCommand], [], true)
    }

    function onError(error) {
      // After a refused password greetd also answers the session's
      // cancellation with an error ("unable to send message…"): the try is
      // over by then and its reason is on the screen. Only an error during
      // a try is news.
      if (root.phase === "idle") {
        console.warn("greetd:", error)
        return
      }
      root.fail(Commons.I18n.t("greeter.loginError").arg(error))
    }
  }

  // The preview's stand-in for greetd.
  Timer {
    id: previewTimer
    interval: 900
    onTriggered: {
      if (root.pendingPassword === "karchy-test") root.phase = "starting"
      else if (root.pendingPassword === "locked") root.fail("The account is locked due to 10 failed logins. (2 minutes left to unlock)")
      else root.fail(Commons.I18n.t("greeter.wrongPassword"))
    }
  }

  Process {
    id: powerProc
    property string action: ""
    stderr: StdioCollector { id: powerErrors }
    onExited: function(exitCode) {
      if (exitCode === 0) return
      var why = String(powerErrors.text || "").trim().split("\n").pop()
      root.failure = Commons.I18n.t("greeter.powerFailed." + powerProc.action) + (why !== "" ? " " + why : "")
    }
  }

  // Sleep is offered unless karchy turned it off on this machine.
  Process {
    command: ["karchy-sleep-disabled"]
    running: !root.preview
    onExited: function(exitCode) { root.canSuspend = exitCode !== 0 }
  }

  // Tells the launcher the screen is up (it falls back to the text greeter
  // when this never comes).
  Process {
    id: readyProc
    command: ["touch", root.runDir + "/ready"]
  }

  function markReady() {
    if (readyMarked) return
    readyMarked = true
    if (runDir !== "") readyProc.running = true
  }

  Component {
    id: view

    GreeterView {
      users: root.users
      userIndex: root.userIndex
      phase: root.phase
      failure: root.failure
      keyboardLayout: root.keyboardLayout
      canSuspend: root.canSuspend
      passwordText: root.passwordText

      onPasswordEdited: function(password) {
        root.passwordText = password
        if (password.length > 0 && root.failure !== "") root.failure = ""
      }
      onSubmitted: function(password) { root.submit(password) }
      onUserStepped: function(delta) { root.stepUser(delta) }
      onPowerRequested: function(action) { root.power(action) }
    }
  }

  // One window for a look at the screen without greetd.
  Loader {
    active: root.preview
    sourceComponent: FloatingWindow {
      implicitWidth: 1280
      implicitHeight: 800
      color: Commons.Color.background
      Loader { anchors.fill: parent; sourceComponent: view }
    }
  }

  // The real thing: every display, with the keyboard.
  Variants {
    model: root.preview ? [] : Quickshell.screens

    PanelWindow {
      required property var modelData

      screen: modelData
      color: Commons.Color.background
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "karchy-greeter"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      anchors { top: true; bottom: true; left: true; right: true }

      // Twice the size from 1400 pixels of height, the boot splash's own
      // rule (Plymouth gives a theme no scale, and the greeter's Hyprland
      // runs every display at scale 1), so the two screens stay the same
      // size and in the same place on a high-resolution panel.
      Loader {
        readonly property int factor: parent.height >= 1400 ? 2 : 1
        width: parent.width / factor
        height: parent.height / factor
        scale: factor
        transformOrigin: Item.TopLeft
        sourceComponent: view
        onLoaded: root.markReady()
      }
    }
  }
}
