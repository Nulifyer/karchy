pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "AudioControlModel.js" as Model

// The sound devices and their levels, once for the whole shell: which outputs
// and inputs there are, which one is in use, its volume and mute, and the
// apps that are playing. The bar's audio panel and Settings › Sound both show
// and change them through here, so the two can't disagree about which sink a
// volume belongs to or which nodes are devices.
//
// A view calls watch(<its own key>) while it is on screen and unwatch() when
// it leaves. While anything watches, the device rows are kept (sinkRows,
// sourceRows, streamRows), unplugged outputs are looked up, and the input's
// level is measured (inputPeak).
Singleton {
  id: root

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []

  // ---------------------------------------------------------------- watching

  property var watchers: ({})
  readonly property bool watched: Object.keys(watchers).length > 0

  function watch(key) {
    if (watchers[key]) return
    var next = Object.assign({}, watchers)
    next[key] = true
    watchers = next
  }

  function unwatch(key) {
    if (!watchers[key]) return
    var next = Object.assign({}, watchers)
    delete next[key]
    watchers = next
  }

  onWatchedChanged: {
    if (watched) refreshRows()
    else clearRows()
  }

  // ----------------------------------------------------------------- devices

  // Nodes of a platform's audio processing, which are neither devices nor apps,
  // stay out of every list (AudioNodes.platformHides). Most machines have none.
  readonly property var nodeNames: {
    var names = []
    for (var i = 0; i < nodes.length; i++)
      if (nodes[i] && nodes[i].name) names.push(String(nodes[i].name))
    return names
  }

  function platformHides(node) {
    return !!node && AudioNodes.platformHides(node.name, nodeNames)
  }

  readonly property var candidateSinks: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isSink || n.isStream || platformHides(n)) continue
      list.push(n)
    }
    return list
  }

  readonly property var candidateSources: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || n.isSink || n.isStream) continue
      if (!Model.isAudioSource(n) && !Model.isUntypedSource(n, sourceAvailability)) continue
      var name = n.name || ""
      if (name === "quickshell" || platformHides(n)) continue
      list.push(n)
    }
    return list
  }

  // Identify true playback streams without reading node.properties here:
  // PwNode.properties is invalid until the node is bound, and reading it while
  // capture streams are appearing (for example, when Voxtype starts recording)
  // can destabilize Quickshell's Pipewire service. Quickshell versions differ
  // in how `type` is exposed (media.class, enum name, or numeric enum), but
  // playback streams consistently accept audio input from clients and publish
  // `isSink: true`; capture streams publish as stream sources.
  readonly property var candidateStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isStream || !Model.isPlaybackStream(n)) continue
      // A tuning's output is a playback stream too, but it is the processing
      // itself rather than an application, so it does not belong in the list.
      if (String(n.name || "").indexOf("karchy_speaker_tuning") === 0) continue
      if (platformHides(n)) continue
      list.push(n)
    }
    return list
  }

  property var sinkAvailability: ({})
  property bool sinkAvailabilityLoaded: false
  property var sourceAvailability: ({})

  function sinkAvailable(node) {
    if (!node || !node.name || !sinkAvailabilityLoaded) return true
    var name = String(node.name)
    return sinkAvailability[name] !== false
  }

  property var cachedSinks: []
  property var cachedSources: []

  readonly property var rawSinks: {
    var list = []
    for (var i = 0; i < candidateSinks.length; i++)
      if (sinkAvailable(candidateSinks[i])) list.push(candidateSinks[i])
    if (sink && list.indexOf(sink) < 0) list.unshift(sink)
    return list
  }

  readonly property var rawSources: {
    var list = candidateSources.slice()
    if (source && list.indexOf(source) < 0) list.unshift(source)
    return list
  }

  onRawSinksChanged: if (rawSinks.length > 0) cachedSinks = rawSinks
  onRawSourcesChanged: if (rawSources.length > 0) cachedSources = rawSources

  // The outputs and inputs to offer, and the apps playing something.
  readonly property var sinks: rawSinks.length > 0 ? rawSinks : cachedSinks
  readonly property var sources: rawSources.length > 0 ? rawSources : cachedSources
  readonly property var streams: {
    var list = []
    for (var i = 0; i < candidateStreams.length; i++)
      if (candidateStreams[i].audio) list.push(candidateStreams[i])
    return list
  }

  // -------------------------------------------------------------------- rows

  // Feed Repeaters with snapshots of primitives instead of the live PipeWire
  // model. PipeWire can remove nodes while Quickshell is dispatching the
  // removal signal, and a row still holding the PwNode is a QObject Qt
  // dereferences without a null check, which segfaults the shell. Rows carry
  // id and name only; every delegate resolves its own node through nodeFor().
  // The snapshot timer lets the mutation settle first, and with nothing
  // watching the rows stay empty, so no repeater is attached at all.
  property var sinkRows: []
  property var sourceRows: []
  property var streamRows: []

  onSinksChanged: scheduleRowRefresh()
  onSourcesChanged: scheduleRowRefresh()
  onStreamsChanged: scheduleRowRefresh()

  // A row that outlives its node resolves to null, or to a node PipeWire recreated
  // under the same id and name; every binding on it guards for null, and a row
  // that never held the node cannot dangle.
  function nodeFor(row) {
    if (!row) return null
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.id === row.id && String(n.name || "") === row.name) return n
    }
    return null
  }

  function refreshRows() {
    if (!watched) return
    sinkRows = Model.rowSnapshot(sinks)
    sourceRows = Model.rowSnapshot(sources)
    streamRows = Model.rowSnapshot(streams)
  }

  function scheduleRowRefresh() {
    if (watched) rowRefreshTimer.restart()
  }

  function clearRows() {
    rowRefreshTimer.stop()
    sinkRows = []
    sourceRows = []
    streamRows = []
  }

  Timer {
    id: rowRefreshTimer
    interval: 75
    onTriggered: root.refreshRows()
  }

  // ------------------------------------------------------------ the volume sink

  // A DSP sink -- a speaker tuning, or EasyEffects -- can be the selected output
  // without being where loudness lives: changing its volume alters the level going
  // *into* the processing, so the slider would move while the speakers did not,
  // and on a chain with a limiter it would change the tone as well.
  //
  // karchy-audio-output-sink resolves the *current* default output through any
  // such sink to the physical one, which is the same definition the volume keys
  // and the output switcher use. Resolving the default (rather than "whatever a
  // tuning fronts") is what keeps this correct when headphones or HDMI are
  // selected while a tuning still exists.
  property string volumeSinkName: ""

  readonly property var volumeSink: {
    if (volumeSinkName === "" || !sink) return sink
    if (volumeSinkName === String(sink.name)) return sink
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream && String(n.name) === volumeSinkName && n.audio)
        return n
    }
    return sink
  }

  // Re-resolve whenever the selected output changes, and when nodes or links
  // come and go: a tuning being applied or removed underneath us, or a DSP sink
  // rerouted to another output, shows up as exactly that.
  onSinkChanged: resolveVolumeSink()
  onNodesChanged: volumeSinkResolveTimer.restart()

  Connections {
    target: Pipewire.linkGroups
    function onValuesChanged() { volumeSinkResolveTimer.restart() }
  }

  property bool volumeSinkStale: false
  // Bumped by every resolve, so a script read still running from before cannot
  // overwrite a newer answer, the hardware fast path's included.
  property int volumeSinkGeneration: 0
  property int volumeSinkRequest: -1

  function resolveVolumeSink() {
    volumeSinkGeneration++
    // A hardware output is its own volume sink, as karchy-audio-output-sink
    // reports without looking further, so only a DSP sink needs the script.
    if (sink && String(sink.name).indexOf("alsa_output.") === 0) {
      volumeSinkName = String(sink.name)
      return
    }
    if (volumeSinkProc.running) {
      volumeSinkStale = true
      return
    }
    volumeSinkRequest = volumeSinkGeneration
    volumeSinkProc.running = true
  }

  // An idle EasyEffects is resolved through its configured output device, which
  // changes without touching the Pipewire graph.
  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/easyeffects/db/easyeffectsrc"
    watchChanges: true
    printErrors: false
    onFileChanged: volumeSinkResolveTimer.restart()
  }

  Process {
    id: volumeSinkProc
    command: ["karchy-audio-output-sink"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.volumeSinkRequest === root.volumeSinkGeneration) root.volumeSinkName = String(text).trim()
      }
    }
    onExited: {
      if (!root.volumeSinkStale) return
      root.volumeSinkStale = false
      // Deferred: the process still reports running while it signals exit.
      Qt.callLater(root.resolveVolumeSink)
    }
  }

  // Runs whether or not anything watches: the bar shows and scrolls the output
  // volume too, so an unresolved sink there would read and change the virtual
  // tuning sink instead of the speakers. Streams starting and stopping also
  // change the graph, so a burst of changes resolves once.
  Timer {
    id: volumeSinkResolveTimer
    interval: 500
    onTriggered: root.resolveVolumeSink()
  }

  Component.onCompleted: root.resolveVolumeSink()

  // ------------------------------------------------------------------ levels

  readonly property real outputVolume: volumeSink && volumeSink.audio ? volumeSink.audio.volume : 0
  readonly property bool outputMuted: volumeSink && volumeSink.audio ? volumeSink.audio.muted : false
  // A virtual source is untyped in Quickshell (see Model.isUntypedSource), so
  // its volume and mute go through wpctl (UntypedInput), and there is no
  // level meter for it: Quickshell's peak monitor takes typed nodes only.
  readonly property bool inputViaWpctl: UntypedInput.active
  readonly property bool inputLevelKnown: !inputViaWpctl || UntypedInput.known
  readonly property real inputVolume: inputViaWpctl ? UntypedInput.volume : (source && source.audio ? source.audio.volume : 0)
  readonly property bool inputMuted: inputViaWpctl ? UntypedInput.muted : (source && source.audio ? source.audio.muted : false)
  readonly property var inputPeakNode: inputViaWpctl ? null : source
  readonly property bool inputLevelShown: !!inputPeakNode
  // How loud the input is right now, 0 to 1, while something watches.
  readonly property real inputPeak: inputPeakMonitor.peak

  // Only channels that actually exist get a vote. A box with no default source
  // would otherwise report "input unmuted" forever, leaving a mute-everything
  // switch able to mute but never to unmute.
  readonly property bool hasOutput: !!(volumeSink && volumeSink.audio)
  readonly property bool hasInput: !!(source && source.audio) || (inputViaWpctl && UntypedInput.known)
  readonly property bool anyAudible: (hasOutput && !outputMuted) || (hasInput && !inputMuted)

  function setOutputVolume(v) {
    if (!volumeSink || !volumeSink.audio) return outputVolume
    var volume = Math.max(0, Math.min(1, v))
    volumeSink.audio.volume = volume
    return volume
  }

  function setInputVolume(v) {
    if (inputViaWpctl) {
      UntypedInput.setVolume(v)
      return
    }
    if (!source || !source.audio) return
    source.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleOutputMute() {
    if (volumeSink && volumeSink.audio) volumeSink.audio.muted = !volumeSink.audio.muted
  }

  function toggleInputMute() {
    if (inputViaWpctl) {
      if (UntypedInput.known) UntypedInput.setMuted(!UntypedInput.muted)
    }
    else if (source && source.audio) source.audio.muted = !source.audio.muted
  }

  // Both channels at once. It counts as on while anything is still audible,
  // which keeps muting a single channel from flipping a master switch.
  function toggleAllMuted() {
    var mute = anyAudible
    if (hasOutput) volumeSink.audio.muted = mute
    if (hasInput && inputViaWpctl) UntypedInput.setMuted(mute)
    else if (hasInput) source.audio.muted = mute
  }

  // An app's own level may go past 100%, as PipeWire allows a stream.
  function setStreamVolume(node, v) {
    if (node && node.audio) node.audio.volume = Math.max(0, Math.min(1.5, v))
  }

  function toggleStreamMute(node) {
    if (node && node.audio) node.audio.muted = !node.audio.muted
  }

  function setDefaultSink(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSink = node
    if (node.id !== undefined && node.name) {
      Quickshell.execDetached([
        "karchy-audio-output-set-default",
        String(node.id),
        String(node.name)
      ])
    }
  }

  function setDefaultSource(node) {
    if (!node) return
    // Quickshell refuses an untyped node; the command below still selects it.
    if (node.audio) Pipewire.preferredDefaultAudioSource = node
    if (node.id !== undefined && node.name) {
      Quickshell.execDetached([
        "karchy-audio-input-set-default",
        String(node.id),
        String(node.name)
      ])
    }
  }

  // The output icon's name in default/karchy/icons.json.
  function outputIconName(volume) {
    if (!sink || !sink.audio) return "audio.volume.muted"
    if (Model.isHeadphones(sink)) return "audio.headphones"
    if (outputMuted) return "audio.volume.muted"
    var v = volume === undefined ? outputVolume : volume
    if (v >= 0.67) return "audio.volume.high"
    if (v >= 0.34) return "audio.volume.medium"
    if (v > 0) return "audio.volume.low"
    return "audio.volume.muted"
  }

  function nodeLabel(node) {
    return Model.nodeLabel(node, I18n.t)
  }

  PwObjectTracker { objects: root.candidateSinks }
  PwObjectTracker { objects: root.candidateSources }
  PwObjectTracker { objects: root.streams }

  PwNodePeakMonitor {
    id: inputPeakMonitor
    node: root.inputPeakNode
    enabled: root.watched && !!root.inputPeakNode
  }

  Process {
    id: sinkAvailabilityProc
    command: ["karchy-audio-sink-availability"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.sinkAvailability = Model.parseSinkAvailability(text)
        root.sinkAvailabilityLoaded = true
      }
    }
  }

  Process {
    id: sourceAvailabilityProc
    command: ["karchy-audio-sink-availability", "sources"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.sourceAvailability = Model.parseSinkAvailability(text)
    }
  }

  Timer {
    interval: 5000
    running: root.watched
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!sinkAvailabilityProc.running) sinkAvailabilityProc.running = true
      if (!sourceAvailabilityProc.running) sourceAvailabilityProc.running = true
    }
  }
}
