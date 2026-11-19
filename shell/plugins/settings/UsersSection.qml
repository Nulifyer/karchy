import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Users: the people who use this computer, and whether it logs
// in by itself (D-139). The page shows what karchy-settings-users status
// says and sends every change through that command, which asks for an
// administrator's password each time (/usr/lib/karchy/users-settings). The
// rules are the helper's: a control the helper would refuse is switched off
// with the helper's reason beside it, and a refused name comes back under
// its field in the helper's words.
//
// Adding the second person on an encrypted computer turns automatic login
// off; the page then asks the first person to change their password, which
// until then is also the disk password, and keeps a note until they have.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  // The Settings window, for its confirm dialog (set by its Loader).
  property var settings: null
  property bool loaded: false
  property string loadError: ""
  property string lastStatus: ""
  property var users: []
  property var autologin: ({})
  property string you: ""
  property bool admin: false
  property bool encrypted: true
  property bool passwordNote: false

  // The row that is open, by account name.
  property string openUser: ""
  // The change that failed: { tag, text }. A row shows its own.
  property var failed: ({})

  // ---- the add form ----
  property bool adding: false
  property string addRole: "standard"
  property string nameError: ""
  property string fullNameError: ""
  property string passwordError: ""
  // Adding now makes it more than one person on a computer that logs in by
  // itself: that stops.
  readonly property bool addEndsAutologin: autologin.on === true && users.length === 1

  function refresh() { if (!statusProc.running) statusProc.running = true }

  // Rows are rebuilt only when something changed, so the keyboard and what
  // is typed stay where they are.
  function load(text) {
    if (text.trim() === "" || text === root.lastStatus) return
    try {
      var status = JSON.parse(text)
      root.lastStatus = text
      root.you = status.you || ""
      root.admin = status.admin === true
      root.encrypted = status.encrypted === true
      root.autologin = status.autologin || {}
      root.passwordNote = status.passwordNote === true
      root.users = status.users || []
      root.loaded = true
      root.loadError = ""
      if (root.openUser !== "") Qt.callLater(root.focusOpenRow)
    } catch (e) {}
  }

  function focusOpenRow() {
    for (var i = 0; i < rows.count; i++) {
      var row = rows.itemAt(i)
      if (row && row.user.name === root.openUser) { row.focusHeader(); return }
    }
    root.openUser = ""
  }

  // The helper's sentence: its last line, without the program's name.
  function sentence(text) {
    var lines = String(text || "").split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l !== "" })
    return lines.length === 0 ? "" : lines[lines.length - 1].replace(/^users-settings: /, "")
  }

  function busy(tag) { return act.running && act.tag === tag }
  function failedFor(name) {
    var tag = String(root.failed.tag || "")
    return tag.indexOf(":") > 0 && tag.slice(tag.indexOf(":") + 1) === name ? String(root.failed.text || "") : ""
  }

  // One change at a time; each asks for an administrator's password. A
  // closed password prompt is not a failure: the page stays as it was.
  function change(tag, args, input, done) {
    if (act.running) return
    root.failed = ({})
    act.tag = tag
    act.start(["karchy-settings-users"].concat(args), function(ok, out, cancelled) {
      if (!ok && !cancelled) root.failed = { tag: tag, text: root.sentence(act.error) }
      root.refresh()
      if (typeof done === "function") done(ok, out, cancelled)
    }, input)
  }

  function inTerminal(command) {
    Quickshell.execDetached(["karchy-launch-floating-terminal-with-presentation", command])
  }

  function startAdding() {
    root.adding = true
    root.openUser = ""
    Qt.callLater(function() { addName.forceActiveFocus() })
  }

  function stopAdding() {
    root.adding = false
    root.nameError = ""
    root.fullNameError = ""
    root.passwordError = ""
    if (root.failed.tag === "add") root.failed = ({})
    addName.text = ""
    addFullName.text = ""
    addPassword.text = ""
    addRepeat.text = ""
    root.addRole = "standard"
  }

  function add() {
    var name = addName.text.trim()
    var full = addFullName.text.trim()
    root.nameError = ""
    root.fullNameError = ""
    root.passwordError = ""
    if (name === "") { root.nameError = "Type a username."; addName.forceActiveFocus(); return }
    if (addPassword.text === "") { root.passwordError = "Type a password."; addPassword.forceActiveFocus(); return }
    if (addPassword.text !== addRepeat.text) { root.passwordError = "The passwords don't match."; addRepeat.forceActiveFocus(); return }
    var endsAutologin = root.addEndsAutologin
    root.change("add", ["add", name, root.addRole].concat(full !== "" ? [full] : []), addPassword.text, function(ok, out, cancelled) {
      if (!ok) {
        if (cancelled) return
        // The helper's reason goes under the field it is about; what was
        // typed stays.
        var why = String(root.failed.text || "")
        if (/full name/i.test(why)) { root.fullNameError = why; root.failed = ({}); addFullName.forceActiveFocus() }
        else if (/lowercase|already has an account|the system uses|already there/.test(why)) { root.nameError = why; root.failed = ({}); addName.forceActiveFocus() }
        return
      }
      root.stopAdding()
      root.openUser = ""
      if (endsAutologin && /^autologin=off$/m.test(String(out || ""))) root.offerPasswordChange(name)
    })
  }

  // The first person's password is the one typed into the installer, which
  // also opens the disk: everyone who starts the computer has to know it.
  function offerPasswordChange(added) {
    if (!root.settings) return
    root.settings.ask(
      added + " was added. The login screen now shows at startup, after the disk password, and each person signs in as themselves.\n\n"
        + "Your password is still the disk password, which everyone who starts this computer has to know. "
        + "Change yours so only you can sign in as you. The disk password itself stays as it is.",
      "Change my password…",
      function() { root.inTerminal("karchy-settings-users password") },
      false, "Not now")
  }

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: ["karchy-settings-users", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
    stderr: StdioCollector { id: statusErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) root.loadError = root.sentence(statusErr.text) || "The accounts couldn't be read."
    }
  }

  NetworkAction { id: act; polkit: true }

  // The terminal a password change ran in has closed: show what it left.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (String(event.name) === "closewindow") root.refresh()
    }
  }

  component FieldError: Text {
    visible: text !== ""
    Layout.fillWidth: true
    textFormat: Text.PlainText
    color: Commons.Color.status.error
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    wrapMode: Text.Wrap
  }

  PageHeader {
    title: "Users"
    explanation: "Each person signs in with their own password and has a home folder nobody else can open. An administrator can change the system and these accounts; every change here asks for an administrator's password."
  }

  InlineMessage {
    kind: "error"
    text: root.loadError
    actionText: "Try again"
    onAction: root.refresh()
  }

  // A change that failed outside a row or the add form.
  InlineMessage {
    kind: "error"
    text: root.failed.tag === "autologin" ? String(root.failed.text || "") : ""
    dismissible: true
    onDismissed: root.failed = ({})
  }

  InlineMessage {
    kind: "warning"
    text: root.passwordNote
      ? "Your password was set at install, where it also became the disk password. Change it now that others use this computer."
      : ""
    actionText: "Change password…"
    onAction: root.inTerminal("karchy-settings-users password")
  }

  InlineMessage {
    kind: "info"
    text: root.loaded && !root.admin ? "Only an administrator can add, change or remove accounts." : ""
  }

  Section {
    title: "Accounts"
    contentSpacing: Style.spacing.md
    // Kept in place while the form is open, so the list doesn't move.
    trailing: Button {
      visible: root.admin
      enabled: !root.adding
      focusable: true
      bordered: true
      iconText: Icons.glyph("ui.add")
      text: "Add user…"
      onClicked: root.startAdding()
    }

    Repeater {
      id: rows
      model: root.users
      delegate: UsersAccountRow {
        required property var modelData
        Layout.fillWidth: true
        page: root
        user: modelData
        open: root.openUser === modelData.name
        onToggleRequested: {
          root.failed = ({})
          root.openUser = root.openUser === modelData.name ? "" : modelData.name
        }
      }
    }
  }

  Section {
    visible: root.adding
    title: "New user"
    contentSpacing: Style.spacing.xxl

    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Style.spacing.xxl
      rowSpacing: Style.spacing.md

      SettingsLabel { text: "Username" }
      TextField {
        id: addName
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(300)
        placeholderText: "lowercase letters, digits, - or _"
        Accessible.name: "Username"
        onTextEdited: root.nameError = ""
        onAccepted: addFullName.forceActiveFocus()
      }
      Item { visible: root.nameError !== ""; implicitWidth: 1; implicitHeight: 1 }
      FieldError { text: root.nameError }

      SettingsLabel { text: "Full name" }
      TextField {
        id: addFullName
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(300)
        placeholderText: "Optional"
        Accessible.name: "Full name"
        onTextEdited: root.fullNameError = ""
        onAccepted: addPassword.forceActiveFocus()
      }
      Item { visible: root.fullNameError !== ""; implicitWidth: 1; implicitHeight: 1 }
      FieldError { text: root.fullNameError }

      SettingsLabel { text: "Password" }
      TextField {
        id: addPassword
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(300)
        password: true
        Accessible.name: "Password"
        onTextEdited: root.passwordError = ""
        onAccepted: addRepeat.forceActiveFocus()
      }

      SettingsLabel { text: "Repeat it" }
      TextField {
        id: addRepeat
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(300)
        password: true
        Accessible.name: "Repeat the password"
        onTextEdited: root.passwordError = ""
        onAccepted: root.add()
      }
      Item { visible: root.passwordError !== ""; implicitWidth: 1; implicitHeight: 1 }
      FieldError { text: root.passwordError }

      SettingsLabel { text: "Role" }
      ButtonGroup {
        options: [{ value: "standard", label: "Standard" }, { value: "admin", label: "Administrator" }]
        value: root.addRole
        onChanged: function(value) { root.addRole = value }
      }
      Item { implicitWidth: 1; implicitHeight: 1 }
      Text {
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(460)
        textFormat: Text.PlainText
        text: root.addRole === "admin"
          ? "Can change system settings, install software and manage accounts."
          : "Uses the computer and their own files; system changes need an administrator's password."
        color: Commons.Color.textSecondary
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
      }
    }

    // What adding changes for the person already here, before they commit.
    Text {
      visible: root.addEndsAutologin
      Layout.fillWidth: true
      Layout.maximumWidth: Style.space(620)
      textFormat: Text.PlainText
      text: "Automatic login turns off: the login screen shows at startup, after the disk password."
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
    }

    InlineMessage {
      kind: "error"
      text: root.failed.tag === "add" ? String(root.failed.text || "") : ""
    }

    RowLayout {
      spacing: Style.spacing.controlGap
      Button {
        focusable: true
        variant: "primary"
        text: "Add user"
        busy: root.busy("add")
        onClicked: root.add()
      }
      Button {
        focusable: true
        bordered: true
        text: "Cancel"
        enabled: !root.busy("add")
        onClicked: root.stopAdding()
      }
    }
  }

  Section {
    title: "Signing in"

    SettingRow {
      label: "Log in automatically"
      // Off can always be chosen; on only where the helper allows it.
      enabled: root.admin && (root.autologin.on === true || (root.autologin.cannotTurnOn || "") === "")
      info: "On: after the disk password the computer starts your desktop without asking for yours. Off: the login screen asks for it too. A change applies the next time the computer starts."
      note: root.autologin.on === true ? "" : (root.autologin.cannotTurnOn || "")
      checked: root.autologin.on === true
      busy: root.busy("autologin")
      onToggled: root.change("autologin", ["autologin", checked ? "off" : "on"])
    }
  }
}
