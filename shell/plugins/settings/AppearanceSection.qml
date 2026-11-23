import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Appearance: theme, wallpaper, bar and the workspace layout,
// through the same commands the menu and a terminal use, and the lock screen
// clock, saved in shell.json. Fonts and the text size are Settings › Fonts.
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

  // The layout of workspaces without one of their own: dwindle (tiling),
  // scrolling or floating, read and saved by its own command.
  property string workspaceLayout: ""
  function refresh() { if (!layoutProc.running) layoutProc.running = true }
  Component.onCompleted: refresh()
  Process {
    id: layoutProc
    command: ["karchy-hyprland-workspace-layout-default"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.workspaceLayout = text.trim() }
  }
  Process {
    id: layoutSetProc
    onExited: root.refresh()
  }

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
    explanation: "Fonts and the text size are under Fonts; monitor scale is under Displays. In VS Code, pick the color theme \"Karchy\" once and it follows every theme. Gaps, borders and animations of your own go in looknfeel.lua; bar and shell options are in shell.json."
    ConfigFileLink { closes: root.settings; file: ".config/hypr/looknfeel.lua" }
    ConfigFileLink { closes: root.settings; file: ".config/karchy/shell.json" }
  }

  GridLayout {
    columns: 2
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

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

    SettingsLabel { text: "Workspace layout" }
    Row {
      spacing: Style.spacing.md

      ButtonGroup {
        anchors.verticalCenter: parent.verticalCenter
        // Scrolling is offered only while it is the layout in use (set from a
        // terminal), so the choice shown is never missing.
        options: [
          { value: "dwindle", label: "Tiling" },
          { value: "floating", label: "Floating" }
        ].concat(root.workspaceLayout === "scrolling" ? [{ value: "scrolling", label: "Scrolling" }] : [])
        value: root.workspaceLayout
        onChanged: function(value) {
          if (value === root.workspaceLayout || layoutSetProc.running) return
          layoutSetProc.command = ["karchy-hyprland-workspace-layout-default", value]
          layoutSetProc.running = true
        }
      }

      // The change itself says this in a notification.
      InfoTip {
        anchors.verticalCenter: parent.verticalCenter
        subject: "Workspace layout"
        text: "For new and empty workspaces. One with windows keeps its layout."
      }
    }

    SettingsLabel { text: "Lock screen clock" }
    ToggleSwitch {
      flush: true
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
