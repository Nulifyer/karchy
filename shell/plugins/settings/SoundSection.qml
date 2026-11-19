import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../../Commons/AudioControlModel.js" as AudioModel

// Settings › Sound: the output and the input in use, their levels, a sound
// card's profile and a device's port, the apps that are playing, and a test
// sound.
//
// The devices, levels and apps are AudioControl's (qs.Commons), which the
// bar's audio panel shows too, so a change in one shows in the other at
// once. Profiles and ports are PulseAudio-side facts PipeWire's interface
// doesn't carry: karchy-settings-sound reads and sets them, and plays the
// test sound. WirePlumber remembers every choice by itself.
//
// karchy plays no alert or notification sounds, so there is no volume for
// them here.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  property var settings: null
  property var target: ({})
  readonly property bool wide: width >= Style.space(560)

  // { output, input, canTest } from `karchy-settings-sound status`; each
  // part is { device, port, ports, card, cardLabel, profile, profiles } or null.
  property var status: ({})
  property string error: ""
  readonly property var outputPart: status.output || null
  readonly property var inputPart: status.input || null
  // One card often carries both directions; its profile is then one choice.
  readonly property bool sharedCard: !!outputPart && !!inputPart && outputPart.card !== "" && outputPart.card === inputPart.card

  readonly property var sink: AudioControl.sink
  readonly property var source: AudioControl.source
  readonly property var mprisPlayers: Mpris.players ? Mpris.players.values : []

  function refresh() {
    if (statusProc.running) statusAgain = true
    else statusProc.running = true
  }
  property bool statusAgain: false

  // A device, as a row of a choice: its name is what the choice carries.
  function deviceOptions(rows) {
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var node = AudioControl.nodeFor(rows[i])
      out.push({ value: rows[i].name, label: node ? AudioControl.nodeLabel(node) : rows[i].name })
    }
    return out
  }

  function rowNamed(rows, name) {
    for (var i = 0; i < rows.length; i++) if (rows[i].name === name) return rows[i]
    return null
  }

  function choices(list) {
    return (list || []).map(function(entry) {
      return { value: entry.name, label: entry.available === false ? entry.label + " (not plugged in)" : entry.label }
    })
  }

  function run(args) {
    root.error = ""
    setProc.command = ["karchy-settings-sound"].concat(args)
    setProc.running = true
  }

  function percent(volume) {
    return Commons.I18n.formatNumber(Math.round(volume * 100)) + "%"
  }

  Component.onCompleted: {
    AudioControl.watch("settings-sound")
    root.refresh()
  }
  Component.onDestruction: AudioControl.unwatch("settings-sound")

  // Another device chosen, plugged in or unplugged, or a profile switched
  // (which replaces the card's devices): read the profiles and ports again.
  Connections {
    target: AudioControl
    function onSinkChanged() { statusSoon.restart() }
    function onSourceChanged() { statusSoon.restart() }
    function onSinkRowsChanged() { statusSoon.restart() }
    function onSourceRowsChanged() { statusSoon.restart() }
  }

  Timer { id: statusSoon; interval: 300; onTriggered: root.refresh() }

  Process {
    id: statusProc
    command: ["karchy-settings-sound", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.status = JSON.parse(text) || ({}) } catch (e) {}
      }
    }
    onExited: {
      if (!root.statusAgain) return
      root.statusAgain = false
      Qt.callLater(root.refresh)
    }
  }

  Process {
    id: setProc
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.error = text.trim() }
    onExited: root.refresh()
  }

  Process {
    id: testProc
    command: ["karchy-settings-sound", "test"]
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.error = text.trim() }
  }

  PageHeader {
    title: "Sound"
    explanation: "The sound panel on the bar changes the same devices and levels. A profile is what a sound card does as a whole: a headset's high-quality playback or its call mode with the microphone, analog or HDMI. What you choose is remembered for each device."
  }

  InlineMessage {
    kind: "error"
    text: root.error !== "" ? "That didn't work." : ""
    details: root.error
    dismissible: true
    onDismissed: root.error = ""
  }

  // ------------------------------------------------------------------ output

  Section {
    title: "Output"

    Text {
      visible: !root.sink
      Layout.fillWidth: true
      textFormat: Text.PlainText
      text: root.inputPart && root.inputPart.profileDropsOther === true
        ? "No output device. The input's profile, " + root.inputPart.profileLabel + ", leaves the card's output off."
        : "No output device."
      wrapMode: Text.Wrap
      color: Commons.Color.textSecondary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    GridLayout {
      visible: !!root.sink
      Layout.fillWidth: true
      columns: root.wide ? 2 : 1
      columnSpacing: Style.spacing.xxl
      rowSpacing: Style.spacing.md

      SettingsLabel { text: "Device" }
      DeviceChoice {
        accessibleName: "Output device"
        rows: AudioControl.sinkRows
        current: root.sink
        onChosen: function(node) { AudioControl.setDefaultSink(node) }
      }

      SettingsLabel { text: "Volume" }
      VolumeControl {
        what: "Output"
        volume: AudioControl.outputVolume
        muted: AudioControl.outputMuted
        enabled: AudioControl.hasOutput
        onVolumeSet: function(v) { AudioControl.setOutputVolume(v) }
        onMuteToggled: AudioControl.toggleOutputMute()
      }

      SettingsLabel { visible: outputProfile.visible; text: "Profile" }
      Dropdown {
        id: outputProfile
        visible: !!root.outputPart && root.outputPart.profiles.length > 0
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(400)
        showLabel: false
        value: root.outputPart ? root.outputPart.profile : ""
        options: root.choices(root.outputPart ? root.outputPart.profiles : [])
        onChanged: function(value) { root.run(["profile", root.outputPart.card, value]) }
      }

      SettingsLabel { visible: outputPort.visible; text: "Port" }
      Dropdown {
        id: outputPort
        visible: !!root.outputPart && root.outputPart.ports.length > 0
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(400)
        showLabel: false
        value: root.outputPart ? root.outputPart.port : ""
        options: root.choices(root.outputPart ? root.outputPart.ports : [])
        onChanged: function(value) { root.run(["port", "output", value]) }
      }

      Item { visible: testButton.visible && root.wide; Layout.preferredWidth: Style.spacing.formLabelWidth }
      Button {
        id: testButton
        visible: root.status.canTest === true
        focusable: true
        bordered: true
        text: "Test sound"
        tooltipText: "Says \"front left\" and \"front right\" from each speaker"
        busy: testProc.running
        enabled: AudioControl.hasOutput && !testProc.running
        onClicked: {
          root.error = ""
          testProc.running = true
        }
      }
    }
  }

  // ------------------------------------------------------------------- input

  Section {
    title: "Input"

    Text {
      visible: !root.source
      Layout.fillWidth: true
      textFormat: Text.PlainText
      // A card on an output-only profile has no input: say which choice did it.
      text: root.outputPart && root.outputPart.profileDropsOther === true
        ? "No input device. The output's profile, " + root.outputPart.profileLabel + ", leaves the card's input off."
        : "No input device."
      wrapMode: Text.Wrap
      color: Commons.Color.textSecondary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    GridLayout {
      visible: !!root.source
      Layout.fillWidth: true
      columns: root.wide ? 2 : 1
      columnSpacing: Style.spacing.xxl
      rowSpacing: Style.spacing.md

      SettingsLabel { text: "Device" }
      DeviceChoice {
        accessibleName: "Input device"
        rows: AudioControl.sourceRows
        current: root.source
        onChosen: function(node) { AudioControl.setDefaultSource(node) }
      }

      SettingsLabel { text: "Volume" }
      VolumeControl {
        what: "Input"
        volume: AudioControl.inputVolume
        muted: AudioControl.inputMuted
        enabled: AudioControl.hasInput && AudioControl.inputLevelKnown
        onVolumeSet: function(v) { AudioControl.setInputVolume(v) }
        onMuteToggled: AudioControl.toggleInputMute()
      }

      // What the microphone hears right now.
      SettingsLabel { visible: level.visible; text: "Level" }
      Item {
        id: level
        visible: AudioControl.inputLevelShown
        Layout.fillWidth: true
        // As wide as the volume slider above it.
        Layout.maximumWidth: Style.space(280)
        implicitHeight: Style.space(8)
        Accessible.role: Accessible.ProgressBar
        Accessible.name: "Input level"

        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: Style.spacing.sm
          anchors.rightMargin: Style.spacing.sm
          color: Style.selectedFillFor(Commons.Color.foreground, Commons.Color.accent)

          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: AudioControl.inputMuted ? 0 : parent.width * Math.max(0, Math.min(1, AudioControl.inputPeak))
            color: Commons.Color.accent
          }
        }
      }

      // The input's own card, when it isn't the output's.
      SettingsLabel { visible: inputProfile.visible; text: "Profile" }
      Dropdown {
        id: inputProfile
        visible: !!root.inputPart && !root.sharedCard && root.inputPart.profiles.length > 0
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(400)
        showLabel: false
        value: root.inputPart ? root.inputPart.profile : ""
        options: root.choices(root.inputPart ? root.inputPart.profiles : [])
        onChanged: function(value) { root.run(["profile", root.inputPart.card, value]) }
      }

      SettingsLabel { visible: inputPort.visible; text: "Port" }
      Dropdown {
        id: inputPort
        visible: !!root.inputPart && root.inputPart.ports.length > 0
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(400)
        showLabel: false
        value: root.inputPart ? root.inputPart.port : ""
        options: root.choices(root.inputPart ? root.inputPart.ports : [])
        onChanged: function(value) { root.run(["port", "input", value]) }
      }
    }
  }

  // -------------------------------------------------------------------- apps

  Section {
    visible: AudioControl.streamRows.length > 0
    title: "Apps"

    Repeater {
      model: AudioControl.streamRows
      delegate: AppVolume {}
    }
  }

  // What to do when sound stops working, as the menu's Reload › Audio does.
  Section {
    Button {
      focusable: true
      bordered: true
      text: "Restart audio…"
      tooltipText: "Starts the sound system again when a device or an app has gone silent"
      onClicked: Quickshell.execDetached(["karchy-launch-floating-terminal-with-presentation", "karchy-restart-audio"])
    }
  }

  // -------------------------------------------------------------- components

  // The device in use: a choice among several, or its name when it is the
  // only one.
  component DeviceChoice: RowLayout {
    id: choice
    property var rows: []
    property var current: null
    property string accessibleName: ""
    signal chosen(var node)

    Layout.fillWidth: true

    Dropdown {
      visible: choice.rows.length > 1
      Layout.fillWidth: true
      Layout.maximumWidth: Style.space(400)
      showLabel: false
      label: choice.accessibleName
      value: choice.current ? String(choice.current.name || "") : ""
      options: root.deviceOptions(choice.rows)
      onChanged: function(value) {
        var node = AudioControl.nodeFor(root.rowNamed(choice.rows, value))
        if (node) choice.chosen(node)
      }
    }
    Text {
      visible: choice.rows.length <= 1
      Layout.fillWidth: true
      // The choice's height, so plugging a second device in moves nothing.
      Layout.preferredHeight: Style.spacing.controlHeight
      verticalAlignment: Text.AlignVCenter
      textFormat: Text.PlainText
      text: choice.current ? AudioControl.nodeLabel(choice.current) : ""
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }

  // A level: the slider, what it reads, and mute.
  component VolumeControl: RowLayout {
    id: control
    property string what: ""
    property real volume: 0
    property bool muted: false
    property real maximum: 1
    signal volumeSet(real value)
    signal muteToggled()

    Layout.fillWidth: true
    spacing: Style.spacing.lg

    PageSlider {
      // Room for what it reads and the button beside it at the window's width.
      Layout.maximumWidth: Style.space(280)
      accessibleName: control.what + " volume, " + (control.muted ? "muted" : root.percent(control.volume))
      enabled: control.enabled
      opacity: control.muted || !control.enabled ? 0.5 : 1
      maximum: control.maximum
      value: control.volume
      onMoved: function(v) { control.volumeSet(v) }
      onReleased: function(v) { control.volumeSet(v) }
      onRightClicked: control.muteToggled()
    }

    Text {
      textFormat: Text.PlainText
      text: control.muted ? "Muted" : root.percent(control.volume)
      color: Commons.Color.textSecondary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.features: { "tnum": 1 }
      Layout.preferredWidth: Style.space(52)
    }

    Button {
      focusable: true
      bordered: true
      enabled: control.enabled
      text: control.muted ? "Unmute" : "Mute"
      // One width for both words, so nothing beside it moves.
      Layout.minimumWidth: Style.space(76)
      accessibleName: (control.muted ? "Unmute " : "Mute ") + control.what.toLowerCase()
      onClicked: control.muteToggled()
    }
  }

  // One app that is playing: its name and its own level, in the form's columns.
  component AppVolume: GridLayout {
    id: app
    required property var modelData
    readonly property var node: AudioControl.nodeFor(modelData)
    readonly property string name: node
      ? AudioModel.streamLabel(node, root.mprisPlayers, AudioControl.streams, Commons.I18n.t) : ""

    Layout.fillWidth: true
    columns: root.wide ? 2 : 1
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    // A long name is cut to the label column, so the sliders stay in line.
    SettingsLabel {
      text: app.name
      Layout.maximumWidth: root.wide ? Style.spacing.formLabelWidth : -1
    }
    VolumeControl {
      what: app.name
      // An app's own level may go past 100%, as in the panel.
      maximum: 1.5
      volume: app.node && app.node.audio ? app.node.audio.volume : 0
      muted: app.node && app.node.audio ? app.node.audio.muted : false
      enabled: !!(app.node && app.node.audio)
      onVolumeSet: function(v) { AudioControl.setStreamVolume(app.node, v) }
      onMuteToggled: AudioControl.toggleStreamMute(app.node)
    }
  }
}
