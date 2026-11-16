import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Appearance: theme, wallpaper, terminal font and text size, through
// the same commands the menu and the display panel use.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  property var fonts: []
  property string currentFont: ""
  // Set by Settings when it loads the section; the bar's style comes from it.
  property var settings: null

  function run(command) {
    actionProc.command = ["bash", "-c", command]
    actionProc.running = true
  }

  Component.onCompleted: {
    fontListProc.running = true
    fontCurrentProc.running = true
  }

  Process { id: actionProc }

  // The theme in use, named as the theme picker names it ("tokyo-night" is
  // Tokyo Night), and followed while the window is open.
  property string themeName: ""
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/karchy/current/theme.name"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.themeName = text().trim()
      .replace(/(^|-)([a-z])/g, function(m, dash, letter) { return dash + letter.toUpperCase() })
      .replace(/-/g, " ")
  }

  Process {
    id: fontListProc
    command: ["karchy-font-list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.fonts = text.split("\n").filter(function(f) { return f.trim() !== "" })
    }
  }

  Process {
    id: fontCurrentProc
    command: ["karchy-font-current"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.currentFont = text.trim() }
  }

  Process {
    id: fontSetProc
    onRunningChanged: if (!running) fontCurrentProc.running = true
  }

  PageHeader {
    title: "Appearance"
    explanation: "The monospace font is used by the terminal, the shell and code. Text size scales the shell and GTK apps together; monitor scale is under Displays. In VS Code, pick the color theme \"Karchy\" once; it follows every theme from then on."
  }

  GridLayout {
    columns: 2
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.lg

    SettingsLabel { text: "Theme" }
    Button {
      focusable: true
      text: root.themeName !== "" ? root.themeName + "…" : "Choose theme…"
      bordered: true
      onClicked: root.run("karchy-shell shell summon karchy.image-picker '{\"source\":\"themes\"}'")
    }

    SettingsLabel { text: "Background" }
    Button {
      focusable: true
      text: "Choose background…"
      bordered: true
      onClicked: root.run("background=$(karchy-theme-bg-switcher); [[ -n $background ]] && karchy-theme-bg-set \"$background\"")
    }

    SettingsLabel { text: "Monospace font" }
    SearchableDropdown {
      value: root.currentFont
      options: root.fonts
      onChanged: function(value) {
        fontSetProc.command = ["karchy-font-set", value]
        fontSetProc.running = true
      }
    }

    SettingsLabel { text: "Text size" }
    // A dropdown, not a row of buttons: seven sizes overflow the page at
    // larger scales.
    Dropdown {
      showLabel: false
      options: root.textSizeStops.map(function(px) { return { value: String(px), label: px + " px" } })
      value: {
        var best = root.textSizeStops[0]
        for (var i = 0; i < root.textSizeStops.length; i++)
          if (Math.abs(root.textSizeStops[i] - Style.font.baseSize) < Math.abs(best - Style.font.baseSize)) best = root.textSizeStops[i]
        return String(best)
      }
      onChanged: function(value) { root.run("karchy-display-text-size " + Number(value)) }
    }

    SettingsLabel { text: "Bar" }
    Row {
      spacing: Style.spacing.md

      ButtonGroup {
        anchors.verticalCenter: parent.verticalCenter
        options: [
          { value: "auto", label: "Auto" },
          { value: "floating", label: "Floating" },
          { value: "docked", label: "Docked" }
        ]
        value: root.settings && root.settings.shell && root.settings.shell.bar && root.settings.shell.bar.barStyle
          ? root.settings.shell.bar.barStyle : "auto"
        onChanged: function(value) { root.run("karchy-bar style " + value) }
      }

      InfoTip {
        anchors.verticalCenter: parent.verticalCenter
        subject: "Bar"
        text: "Auto docks the bar while a window is maximized."
      }
    }
  }
}
