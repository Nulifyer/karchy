import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Fonts (D-120, D-149): the interface font of the shell and of
// GTK and Qt apps, the monospace font of terminals, code editors and code in
// the shell, and the text size, through the
// commands the menu and a terminal use (karchy font, karchy font app, karchy
// display text size). A font from the Quick install list that isn't
// installed is installed first, by the same root helper Quick install uses
// (D-109), and then set.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  // The Settings window (set by its Loader), which a config file link closes.
  property var settings: null
  // Labels beside their controls where the page has room, above them where
  // it is narrow (the window is a tile).
  readonly property bool wide: width >= Style.spacing.formWide
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]

  // `karchy-font-list --json`.
  property var fonts: []
  property string family: ""
  // `karchy-font-app-list --json`.
  property var appFonts: []
  property string appFamily: ""
  property string appDefault: "Noto Sans"

  // An install in progress, and how the last one ended.
  property string installingId: ""
  property string installingName: ""
  property string installingFamily: ""
  property string installError: ""
  property string installLog: ""
  // The font whose install failed, for Try again.
  property var failed: null

  function refresh() {
    fontListProc.running = true
    appListProc.running = true
  }

  Component.onCompleted: refresh()

  // Setting the monospace font restarts the shell, and this window with it:
  // the command runs on its own and opens Settings here again when it is done.
  function setFont(family) {
    Quickshell.execDetached(["bash", "-c", "karchy-font-set \"$1\" && karchy-settings fonts", "karchy-font-set", family])
  }

  function installFont(id, name, family) {
    if (root.installingId !== "") return
    root.installError = ""
    root.failed = null
    installProc.succeeded = false
    root.installingId = id
    root.installingName = name
    root.installingFamily = family
    installProc.command = ["karchy-quick-install", "apply", "install", id]
    installProc.running = true
  }

  function installLine(line) {
    var m = String(line).match(/^(\S+)(?: (\S+))?(?: (.*))?$/)
    if (!m) return
    if (m[1] === "log") { root.installLog = m[2] || ""; return }
    if (m[2] !== root.installingId) return
    if (m[1] === "failed") root.installError = m[3] || "The install stopped."
    else if (m[1] === "done") installProc.succeeded = true
  }

  Process {
    id: fontListProc
    command: ["karchy-font-list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          root.fonts = data.fonts || []
          root.family = data.current || ""
        } catch (e) {
          root.fonts = []
        }
      }
    }
  }

  Process {
    id: appListProc
    command: ["karchy-font-app-list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          root.appFonts = data.fonts || []
          root.appFamily = data.current || ""
          root.appDefault = data["default"] || "Noto Sans"
        } catch (e) {
          root.appFonts = []
        }
      }
    }
  }

  Process {
    id: appSetProc
    onRunningChanged: if (!running) appListProc.running = true
  }

  Process { id: sizeSetProc }

  Process {
    id: installProc
    property bool succeeded: false
    stdout: SplitParser { onRead: function(line) { root.installLine(line) } }
    onExited: {
      var font = { id: root.installingId, name: root.installingName, family: root.installingFamily }
      root.installingId = ""
      if (succeeded) {
        root.setFont(font.family)
      } else {
        root.failed = font
        root.installError = font.name + " wasn't installed: " + (root.installError !== "" ? root.installError : "the install stopped.")
        fontListProc.running = true
      }
    }
  }

  // The default terminal's own config, where a font or size line wins.
  property string terminalConfig: ""
  Process {
    running: true
    command: ["karchy-default-terminal"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.terminalConfig = ({
        foot: ".config/foot/foot.ini",
        kitty: ".config/kitty/kitty.conf",
        alacritty: ".config/alacritty/alacritty.toml",
        ghostty: ".config/ghostty/config"
      })[text.trim()] || ""
    }
  }

  // The interface font changed outside this page (`karchy font app set`):
  // show the one in use.
  Connections {
    target: Style
    function onFontFamilyChanged() { appListProc.running = true }
  }

  PageHeader {
    title: "Fonts"
    explanation: "The interface font is for text that is read: the shell's own, and Files, Disks and other GTK and Qt apps. The monospace font is for terminals, code editors and what reads as code, such as key names and addresses. Websites use the fonts they ask for and Brave's own font settings. The boot menu and the disk-password screen always use JetBrains Mono. A font or size line of your own in a terminal's config wins over these."
    ConfigFileLink {
      closes: root.settings
      file: root.terminalConfig
      label: root.terminalConfig === ".config/ghostty/config" ? "ghostty config" : root.terminalConfig.split("/").pop()
    }
  }

  // Both fonts in use, at the size in use. The monospace line carries the
  // icons a prompt or a status line draws in it: a font whose icons come out
  // missing, clipped or too small shows it here.
  Rectangle {
    Layout.fillWidth: true
    implicitHeight: specimen.implicitHeight + Style.spacing.xxl * 2
    color: Style.normalFill
    radius: Style.radius.control

    Column {
      id: specimen
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.spacing.xxxl
      spacing: Style.spacing.md

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: root.appFamily === "monospace" ? root.family : root.appFamily
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.heading + Style.space(2)
        elide: Text.ElideRight
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: "The quick brown fox jumps over the lazy dog  0123456789"
        color: Commons.Color.textSecondary
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        topPadding: Style.spacing.md
        text: root.family
        color: Commons.Color.foreground
        font.family: Style.font.mono
        font.pixelSize: Style.font.subtitle
        elide: Text.ElideRight
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: "0O 1lI  {} [] ()  -> => != <=   "
          + ["ui.check", "notify.bell", "disk", "net.network", "system.power"].map(function(name) { return Icons.glyph(name) }).join("  ")
        color: Commons.Color.textSecondary
        font.family: Style.font.mono
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }
  }

  GridLayout {
    Layout.fillWidth: true
    columns: root.wide ? 2 : 1
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    SettingsLabel { text: "Interface font" }
    SearchableDropdown {
        Layout.fillWidth: true
        showLabel: false
        value: root.appFamily
        // karchy's default first, then the choice that follows the font below.
        options: [{ value: root.appDefault, label: root.appDefault }, { value: "monospace", label: "Same as monospace" }]
          .concat(root.appFonts.filter(function(f) { return f !== root.appDefault })
            .map(function(f) { return { value: f, label: f } }))
        onChanged: function(value) {
          appSetProc.command = ["karchy-font-app-set", value]
          appSetProc.running = true
        }
    }

    SettingsLabel { text: "Monospace font"; Layout.alignment: Qt.AlignTop }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.sm

      FontPicker {
        objectName: "fontPicker"
        Layout.fillWidth: true
        fonts: root.fonts
        family: root.family
        busy: root.installingId !== ""
        busyLabel: root.installingId !== "" ? "Installing " + root.installingName + "…" : ""
        onChosen: function(family) { root.setFont(family) }
        onInstall: function(id, name, family) { root.installFont(id, name, family) }
      }
      Text {
        visible: root.installingId !== ""
        textFormat: Text.PlainText
        text: "Still using " + root.family + " until it finishes."
        color: Commons.Color.textSecondary
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    SettingsLabel { text: "Text size" }
    // A dropdown, not a row of buttons: seven sizes overflow the page at
    // larger scales.
    Dropdown {
        Layout.fillWidth: true
        showLabel: false
        options: root.textSizeStops.map(function(px) { return { value: String(px), label: px + " px" } })
        value: {
          var best = root.textSizeStops[0]
          for (var i = 0; i < root.textSizeStops.length; i++)
            if (Math.abs(root.textSizeStops[i] - Style.font.baseSize) < Math.abs(best - Style.font.baseSize)) best = root.textSizeStops[i]
          return String(best)
        }
        onChanged: function(value) {
          sizeSetProc.command = ["karchy-display-text-size", String(Number(value))]
          sizeSetProc.running = true
        }
    }
  }

  InlineMessage {
    kind: "error"
    text: root.installError
    actionText: "Try again"
    onAction: if (root.failed) root.installFont(root.failed.id, root.failed.name, root.failed.family)
    dismissible: true
    onDismissed: root.installError = ""
  }
}
