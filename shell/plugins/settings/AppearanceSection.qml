import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Appearance: theme, wallpaper and bar, through the same commands
// the menu uses, and the lock screen clock, saved in shell.json. Fonts and
// the text size are Settings › Fonts.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  // Set by Settings when it loads the section; the bar's style comes from it.
  property var settings: null

  function run(command) {
    actionProc.command = ["bash", "-c", command]
    actionProc.running = true
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

  PageHeader {
    title: "Appearance"
    explanation: "Fonts and the text size are under Fonts; monitor scale is under Displays. In VS Code, pick the color theme \"Karchy\" once and it follows every theme."
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

    SettingsLabel { text: "Lock screen clock" }
    ToggleSwitch {
      readonly property var shell: root.settings ? root.settings.shell : null
      accessibleName: "Show the time and date on the lock screen"
      checked: !(shell && shell.shellConfig && shell.shellConfig.lock && shell.shellConfig.lock.clock === false)
      onToggled: {
        var on = !checked
        if (shell) shell.mutateShellConfig(function(config) {
          if (!config.lock || typeof config.lock !== "object") config.lock = {}
          config.lock.clock = on
        })
      }
    }
  }
}
