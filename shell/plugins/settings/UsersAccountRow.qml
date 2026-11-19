import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One person in Settings › Users. Closed it is one line: the name, the
// account and what it is. Open, what an administrator can change about it,
// in the order people look for it, with Remove last and apart. A change the
// system refuses (the only administrator, your own account) shows its
// control switched off with the reason beside it, in the helper's words
// (karchy-settings-users status).
//
// Your own row opens for everyone: it links to Settings › Security, where
// your password is changed. Other rows open only for an administrator.
ColumnLayout {
  id: root
  spacing: Style.spacing.md

  // The Users page: its state, its one running change and its Settings window.
  property var page: null
  property var user: ({})
  property bool open: false
  signal toggleRequested()

  readonly property bool you: user.you === true
  readonly property bool canOpen: you || (page && page.admin)
  readonly property bool canChange: !!(page && page.admin)
  readonly property string shownName: user.fullName ? user.fullName : user.name
  readonly property string home: user.home || "/home/" + user.name

  // The open parts: a new password, or the question about the home folder.
  property bool resetting: false
  property bool removing: false
  property string homeChoice: "keep-home"
  property string passwordError: ""

  function focusHeader() { header.forceActiveFocus() }

  function summary() {
    var parts = [user.name, user.admin ? "administrator" : "standard"]
    if (user.signedIn && !you) parts.push("signed in")
    return parts.join(", ")
  }

  onOpenChanged: if (!open) closeParts()
  function closeParts() {
    resetting = false
    removing = false
    passwordError = ""
    newPassword.text = ""
    repeatPassword.text = ""
    homeChoice = "keep-home"
    nameField.text = user.fullName || ""
  }

  function saveName() {
    if (!page) return
    page.change("name:" + user.name, ["full-name", user.name, nameField.text.trim()])
  }

  function setPassword() {
    passwordError = ""
    if (newPassword.text === "") { passwordError = "Type a password."; newPassword.forceActiveFocus(); return }
    if (newPassword.text !== repeatPassword.text) { passwordError = "The passwords don't match."; repeatPassword.forceActiveFocus(); return }
    var typed = newPassword.text
    page.change("password:" + user.name, ["reset-password", user.name], typed, function(ok) {
      if (!ok) return
      root.resetting = false
      newPassword.text = ""
      repeatPassword.text = ""
    })
  }

  function remove() {
    var deleting = homeChoice === "delete-home"
    page.settings.ask(
      deleting ? "Remove " + user.name + " and delete everything in " + home + "? This can't be undone."
        : "Remove " + user.name + "? They can no longer sign in. " + home + " stays on the disk.",
      deleting ? "Remove and delete" : "Remove user",
      function() { page.change("remove:" + user.name, ["remove", user.name, root.homeChoice]) })
  }

  // ---- the row itself ----
  BorderSurface {
    id: header
    Layout.fillWidth: true
    implicitHeight: headerRow.implicitHeight + Style.spacing.lg * 2
    radius: Style.radius.control
    activeFocusOnTab: root.canOpen
    readonly property bool hot: root.canOpen && mouse.containsMouse
    color: Style.controlFill(activeFocus, hot, Commons.Color.foreground, Commons.Color.accent)
    borderSpec: Border.controlSpec(activeFocus || hot || root.open ? "hover-cursor" : "normal", Commons.Color.foreground, Commons.Color.accent)
    Keys.onReturnPressed: if (root.canOpen) root.toggleRequested()
    Keys.onEnterPressed: if (root.canOpen) root.toggleRequested()
    Keys.onSpacePressed: if (root.canOpen) root.toggleRequested()
    Accessible.role: root.canOpen ? Accessible.Button : Accessible.StaticText
    Accessible.name: root.shownName + (root.you ? " (you)" : "") + ", " + root.summary()
    Accessible.description: !root.canOpen ? "" : root.open ? "Close" : "Open"

    FocusRing { shown: header.activeFocus }

    RowLayout {
      id: headerRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.spacing.lg

      Text {
        textFormat: Text.PlainText
        text: Icons.glyph("account.user")
        color: Commons.Color.foreground
        font.family: Icons.family
        font.pixelSize: Style.font.iconLarge
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.xxs
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.shownName + (root.you ? " (you)" : "")
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.summary()
          color: Commons.Color.textSecondary
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }

      Text {
        visible: root.canOpen
        textFormat: Text.PlainText
        text: Icons.glyph(root.open ? "ui.chevron.up" : "ui.chevron.down")
        color: Commons.Color.textSecondary
        font.family: Icons.family
        font.pixelSize: Style.font.icon
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      enabled: root.canOpen
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleRequested()
    }
  }

  // ---- open ----
  ColumnLayout {
    visible: root.open && root.canOpen
    Layout.fillWidth: true
    Layout.leftMargin: Style.spacing.xxl
    Layout.bottomMargin: Style.spacing.lg
    spacing: Style.spacing.xxl

    InlineMessage {
      kind: "error"
      text: root.page ? root.page.failedFor(root.user.name) : ""
      dismissible: true
      onDismissed: root.page.failed = ({})
    }

    RowLayout {
      visible: root.canChange
      Layout.fillWidth: true
      spacing: Style.spacing.xxl

      SettingsLabel { text: "Full name" }
      TextField {
        id: nameField
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(300)
        text: root.user.fullName || ""
        placeholderText: "Shown at the login screen"
        // A long name shows its start, not its end.
        Component.onCompleted: cursorPosition = 0
        Accessible.name: "Full name of " + root.user.name
        onAccepted: if (saveNameButton.enabled) root.saveName()
      }
      Button {
        id: saveNameButton
        visible: nameField.text.trim() !== (root.user.fullName || "")
        focusable: true
        bordered: true
        text: "Save"
        accessibleName: "Save the full name of " + root.user.name
        busy: !!root.page && root.page.busy("name:" + root.user.name)
        onClicked: root.saveName()
      }
      Item { Layout.fillWidth: true; implicitHeight: 1 }
    }

    SettingRow {
      visible: root.canChange
      enabled: (root.user.cannotChangeRole || "") === ""
      label: "Administrator"
      info: "Can change system settings, install software and manage accounts."
      note: root.user.cannotChangeRole || ""
      checked: root.user.admin === true
      busy: !!root.page && root.page.busy("role:" + root.user.name)
      onToggled: root.page.change("role:" + root.user.name, ["role", root.user.name, checked ? "standard" : "admin"])
    }

    // Your own password is changed where it asks for the current one.
    RowLayout {
      visible: root.you
      Layout.fillWidth: true
      spacing: Style.spacing.xxl
      SettingsLabel { text: "Password" }
      Button {
        focusable: true
        bordered: true
        text: "Change in Security…"
        accessibleName: "Change your password in Settings, Security"
        onClicked: if (root.page && root.page.settings) root.page.settings.section = "security"
      }
      Item { Layout.fillWidth: true; implicitHeight: 1 }
    }

    RowLayout {
      visible: root.canChange && !root.you && !root.resetting
      Layout.fillWidth: true
      spacing: Style.spacing.xxl
      SettingsLabel { text: "Password" }
      Button {
        focusable: true
        bordered: true
        text: "Reset password…"
        accessibleName: "Reset the password of " + root.user.name
        onClicked: {
          root.removing = false
          root.resetting = true
          Qt.callLater(function() { newPassword.forceActiveFocus() })
        }
      }
      Item { Layout.fillWidth: true; implicitHeight: 1 }
    }

    GridLayout {
      visible: root.resetting
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Style.spacing.xxl
      rowSpacing: Style.spacing.md

      SettingsLabel { text: "New password" }
      TextField {
        id: newPassword
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(300)
        password: true
        Accessible.name: "New password for " + root.user.name
        onTextEdited: root.passwordError = ""
        onAccepted: repeatPassword.forceActiveFocus()
      }
      SettingsLabel { text: "Repeat it" }
      TextField {
        id: repeatPassword
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(300)
        password: true
        Accessible.name: "Repeat the new password"
        onTextEdited: root.passwordError = ""
        onAccepted: root.setPassword()
      }

      Item { implicitWidth: 1; implicitHeight: 1 }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.md
        Text {
          visible: root.passwordError !== ""
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.passwordError
          color: Commons.Color.status.error
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }
        // Without disk encryption the keyring opens with the login password,
        // and only its owner can change that one.
        Text {
          visible: !!root.page && root.page.encrypted === false
          Layout.fillWidth: true
          Layout.maximumWidth: Style.space(460)
          textFormat: Text.PlainText
          text: "Their saved passwords (the keyring) stay locked with the old password."
          color: Commons.Color.status.warning
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }
        RowLayout {
          spacing: Style.spacing.controlGap
          Button {
            focusable: true
            variant: "primary"
            text: "Set password"
            busy: !!root.page && root.page.busy("password:" + root.user.name)
            onClicked: root.setPassword()
          }
          Button {
            focusable: true
            bordered: true
            text: "Cancel"
            onClicked: {
              root.resetting = false
              root.passwordError = ""
              newPassword.text = ""
              repeatPassword.text = ""
            }
          }
        }
      }
    }

    // Apart from the rest. Removing asks what happens to the files first,
    // then once more with Cancel selected.
    ColumnLayout {
      visible: root.canChange
      Layout.fillWidth: true
      Layout.topMargin: Style.spacing.md
      spacing: Style.spacing.md

      RowLayout {
        visible: !root.removing
        Layout.fillWidth: true
        spacing: Style.spacing.xxl
        Button {
          focusable: true
          bordered: true
          variant: "destructive"
          enabled: (root.user.cannotRemove || "") === ""
          text: "Remove user…"
          accessibleName: "Remove " + root.user.name
          onClicked: {
            root.resetting = false
            root.removing = true
          }
        }
        Text {
          visible: (root.user.cannotRemove || "") !== ""
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.user.cannotRemove || ""
          color: Commons.Color.textSecondary
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
        }
      }

      GridLayout {
        visible: root.removing
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Style.spacing.xxl
        rowSpacing: Style.spacing.md

        SettingsLabel { text: "Home folder" }
        ButtonGroup {
          options: [{ value: "keep-home", label: "Keep" }, { value: "delete-home", label: "Delete" }]
          value: root.homeChoice
          onChanged: function(value) { root.homeChoice = value }
        }

        Item { implicitWidth: 1; implicitHeight: 1 }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.md
          Text {
            Layout.fillWidth: true
            Layout.maximumWidth: Style.space(460)
            textFormat: Text.PlainText
            text: root.homeChoice === "delete-home"
              ? "Everything in " + root.home + " is deleted: files, settings and saved passwords. This can't be undone."
              : root.home + " stays on the disk. Only an administrator can open it."
            color: root.homeChoice === "delete-home" ? Commons.Color.status.warning : Commons.Color.textSecondary
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }
          RowLayout {
            spacing: Style.spacing.controlGap
            Button {
              focusable: true
              bordered: true
              variant: "destructive"
              text: "Remove " + root.user.name + (root.homeChoice === "delete-home" ? " and delete files" : "")
              busy: !!root.page && root.page.busy("remove:" + root.user.name)
              onClicked: root.remove()
            }
            Button {
              focusable: true
              bordered: true
              text: "Cancel"
              onClicked: root.removing = false
            }
          }
        }
      }
    }
  }
}
