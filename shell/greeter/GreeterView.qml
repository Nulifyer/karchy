import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The login screen as one display shows it. It continues the boot splash
// (system/plymouth/karchy, D-122): the same mark in the same place, the same
// password box with its lock and one dot per character, and one line under
// the box that says what is going on. The sizes below are that theme's
// (tools/plymouth-theme), so the two screens line up when one follows the
// other.
//
// Keyboard: typing goes to the password; Enter signs in; Up and Down pick
// another person when there are several (the buttons beside the name point
// the same way); Tab walks to the power buttons and back. While a password is
// being tried the box still takes typing, so a retry begun before "Wrong
// password" shows is not lost. This view only shows state and reports intent;
// shell/greeter.qml talks to greetd.
Item {
  id: root

  // [{ name, label }], and which one signs in.
  property var users: []
  property int userIndex: 0
  // "idle", "checking" (the password is being tried) or "starting".
  property string phase: "idle"
  // Why the last try or power action failed; empty when nothing did.
  property string failure: ""
  // The keyboard layout to name under the box, empty when it is plain US.
  property string keyboardLayout: ""
  property bool canSuspend: true
  property string passwordText: ""

  signal passwordEdited(string password)
  signal submitted(string password)
  signal userStepped(int delta)
  signal powerRequested(string action)

  readonly property bool severalUsers: users.length > 1
  readonly property var user: users.length > 0 ? users[Math.min(userIndex, users.length - 1)] : null
  readonly property bool busy: phase !== "idle"
  // Signed in and on the way to the desktop: nothing more is typed.
  readonly property bool leaving: phase === "starting"
  readonly property bool wrong: failure.length > 0 && !busy

  // The default theme's colours by role (themes/nulifyer; a user's own theme
  // never applies before login, D-121).
  readonly property color fieldColor: Commons.Color.paletteValues["dark_background"] || Qt.darker(Commons.Color.background, 1.2)
  readonly property color softText: Commons.Color.paletteValues["light_foreground"] || Commons.Color.textSecondary
  readonly property color quietText: Commons.Color.textSecondary
  readonly property color boxBorder: wrong ? Commons.Color.status.error : busy ? Commons.Color.muted : Commons.Color.accent

  readonly property int markSize: 96
  readonly property int entryWidth: 320
  readonly property int entryHeight: 48
  readonly property int markToEntry: 56
  readonly property int captionSize: 15

  readonly property string caption: failure.length > 0 && !busy ? failure
    : phase === "checking" ? Commons.I18n.t("greeter.checking")
    : phase === "starting" ? Commons.I18n.t("greeter.starting")
    : Commons.I18n.t("greeter.enterPassword")

  function focusPassword() {
    if (passwordInput.enabled) passwordInput.forceActiveFocus()
  }

  function syncPassword() {
    if (passwordInput.text !== passwordText) passwordInput.text = passwordText
  }

  onPasswordTextChanged: syncPassword()
  // The field is disabled while the desktop starts, which drops its focus.
  onLeavingChanged: if (!leaving) Qt.callLater(focusPassword)
  Component.onCompleted: { syncPassword(); Qt.callLater(focusPassword) }

  // A character typed while a button has the keyboard is still the password:
  // it goes to the field, and so does the keyboard. Otherwise a password
  // typed blind after a stray Tab is lost, and its Enter presses Restart.
  Keys.onPressed: function(event) {
    if (root.leaving || event.text.length !== 1 || event.text < " " || event.text === " " || event.text === "\x7f") return
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    root.focusPassword()
    passwordInput.insert(passwordInput.length, event.text)
    event.accepted = true
  }

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.background

    MouseArea {
      anchors.fill: parent
      onClicked: root.focusPassword()
    }
  }

  // The mark, where the boot splash draws it.
  Image {
    id: mark
    x: Math.round(root.width / 2 - width / 2)
    y: Math.round(root.height * 0.42 - height)
    width: root.markSize
    height: root.markSize
    sourceSize.width: root.markSize * 2
    sourceSize.height: root.markSize * 2
    source: "data:image/svg+xml;utf8," + encodeURIComponent(
      '<svg xmlns="http://www.w3.org/2000/svg" width="' + root.markSize * 2 + '" height="' + root.markSize * 2 + '" viewBox="2 2 20 20">'
      + '<path fill="' + Commons.Color.accent + '" d="M2 2 L8.4 2 L8.4 22 L2 22 Z"/>'
      + '<path fill="' + Commons.Color.foreground + '" d="M15.3 2 L22 2 L17.5 10.8 L10.8 10.8 Z"/>'
      + '<path fill="' + Commons.Color.foreground + '" d="M10.8 13.2 L17.5 13.2 L22 22 L15.3 22 Z"/>'
      + '</svg>')
  }

  // Who signs in, between the mark and the box. One person: the name alone.
  // Several: the arrows step through them, as Up and Down do in the field,
  // and point up and down as the hint under the box says.
  Row {
    id: userRow
    anchors.horizontalCenter: parent.horizontalCenter
    y: mark.y + mark.height + Math.round((root.markToEntry - height) / 2)
    spacing: Style.spacing.md

    Button {
      visible: root.severalUsers
      anchors.verticalCenter: parent.verticalCenter
      iconText: Icons.glyph("ui.chevron.up")
      accessibleName: Commons.I18n.t("greeter.previousUser")
      focusable: true
      enabled: !root.busy
      onClicked: root.userStepped(-1)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.user ? root.user.label : ""
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: root.captionSize
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      width: Math.min(implicitWidth, root.entryWidth)
      Accessible.role: Accessible.StaticText
      Accessible.name: Commons.I18n.t("greeter.signingInAs").arg(text)
    }

    Button {
      visible: root.severalUsers
      anchors.verticalCenter: parent.verticalCenter
      iconText: Icons.glyph("ui.chevron.down")
      accessibleName: Commons.I18n.t("greeter.nextUser")
      focusable: true
      enabled: !root.busy
      onClicked: root.userStepped(1)
    }
  }

  BorderSurface {
    id: entry
    x: Math.round(root.width / 2 - width / 2)
    y: mark.y + mark.height + root.markToEntry
    width: root.entryWidth
    height: root.entryHeight
    radius: 6
    color: root.fieldColor
    borderSpec: Border.flat(root.boxBorder, 2)

    Text {
      id: lockIcon
      x: 16
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: Icons.glyph("system.lock")
      color: root.busy ? Commons.Color.muted : root.softText
      font.family: Icons.family
      font.pixelSize: 16
    }

    PasswordInput {
      id: passwordInput
      anchors.fill: parent
      anchors.leftMargin: 44
      anchors.rightMargin: 16
      focus: true
      // Usable while a password is tried: what is typed then is the next
      // try (shell/greeter.qml keeps an Enter until the answer is in).
      enabled: !root.leaving && root.user !== null
      checking: root.leaving
      textColor: root.busy ? Commons.Color.muted : Commons.Color.foreground
      selectionColor: Util.alpha(Commons.Color.accent, 0.45)
      dotFontSize: 22
      dotLetterSpacing: 1
      Accessible.name: root.user
        ? Commons.I18n.t("greeter.passwordFor").arg(root.user.label)
        : Commons.I18n.t("greeter.enterPassword")
      Accessible.description: root.caption

      onTextChanged: root.passwordEdited(text)
      onAccepted: if (text.length > 0) root.submitted(text)

      Keys.onUpPressed: if (root.severalUsers) root.userStepped(-1)
      Keys.onDownPressed: if (root.severalUsers) root.userStepped(1)
    }
  }

  // What is going on, in one line under the box (two when PAM has more to
  // say, such as how long an account stays locked).
  Text {
    id: captionText
    anchors.horizontalCenter: parent.horizontalCenter
    y: entry.y + entry.height + 12
    width: Math.min(root.width - 32, 560)
    textFormat: Text.PlainText
    text: root.caption
    color: root.wrong ? Commons.Color.status.error : root.softText
    font.family: Style.font.family
    font.pixelSize: root.captionSize
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    maximumLineCount: 3
    elide: Text.ElideRight
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    y: captionText.y + captionText.height + 8
    visible: root.severalUsers && !root.busy && !root.wrong
    textFormat: Text.PlainText
    text: Commons.I18n.t("greeter.switchUserHint")
    color: root.quietText
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  // The layout the password is typed in, when it is not plain US.
  Text {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: 24
    visible: root.keyboardLayout.length > 0
    textFormat: Text.PlainText
    text: Icons.glyph("input.keyboard") + "  " + Commons.I18n.t("greeter.keyboardLayout").arg(root.keyboardLayout)
    color: root.quietText
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  // Power, apart from signing in and quiet until wanted.
  Row {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 16
    spacing: Style.spacing.md

    Button {
      visible: root.canSuspend
      text: Commons.I18n.t("greeter.suspend")
      iconText: Icons.glyph("system.suspend")
      foreground: root.softText
      focusable: true
      enabled: root.phase !== "starting"
      onClicked: root.powerRequested("suspend")
    }

    Button {
      text: Commons.I18n.t("greeter.restart")
      iconText: Icons.glyph("system.reboot")
      foreground: root.softText
      focusable: true
      enabled: root.phase !== "starting"
      onClicked: root.powerRequested("reboot")
    }

    Button {
      text: Commons.I18n.t("greeter.shutDown")
      iconText: Icons.glyph("system.power")
      foreground: root.softText
      focusable: true
      enabled: root.phase !== "starting"
      onClicked: root.powerRequested("poweroff")
    }
  }
}
