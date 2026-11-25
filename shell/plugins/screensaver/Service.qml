import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "ScreensaverModel.js" as Model

// The screensaver (D-184): ttfx's effects on the branding art, drawn by the
// shell itself instead of in a terminal. ttfx runs without a terminal and
// what it writes is drawn cell by cell, once for every screen, by
// ScreensaverView. Two places show it:
// - the overlay, above everything on every screen, which the idle service
//   (through karchy-launch-screensaver) and `karchy-shell screensaver show`
//   put up and the first key, click, scroll or pointer movement ends;
// - the lock screen, which takes over the overlay when the session locks
//   under it, and shows it again a few seconds after it was last used.
// Nothing can come above the overlay or take its keyboard but the shell's own
// password prompt, and the lock takes over from it without the desktop
// showing in between.
Item {
  id: root

  property var shell: null
  property string karchyPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string brandingArt: home + "/.config/karchy/branding/screensaver.txt"
  readonly property string logoArt: (karchyPath || Quickshell.env("KARCHY_PATH")) + "/logo.txt"

  // Who shows it. The overlay is this service's; the lock screen sets
  // lockShown while it draws it.
  property bool overlayShown: false
  property bool lockShown: false
  // The screen is off: nothing to draw, so ttfx stops and the grid is black.
  property bool paused: false
  readonly property bool wanted: (overlayShown || lockShown) && !paused

  // The overlay ended by input on it: somebody is back.
  signal dismissed()
  // Cells that changed in the frame just read (indices into cellState).
  signal frameDrawn(var changed)
  // The whole grid is new or blank: draw every cell.
  signal gridReset()

  readonly property var lockService: shell && shell.services ? shell.serviceFor("karchy.lock") : null

  // ------------------------------------------------------------ the grid

  // The branding art when there is one, else karchy's whole name: never the
  // mark alone, the cells get smaller on a narrow screen instead.
  property string brandingText: ""
  property string logoText: ""
  readonly property bool brandingLoaded: Model.artSize(brandingText).cols > 0
  readonly property string artPath: brandingLoaded ? brandingArt : logoArt
  readonly property var art: Model.artSize(brandingLoaded ? brandingText : logoText)

  FileView {
    path: root.brandingArt
    watchChanges: true
    printErrors: false
    onLoaded: root.brandingText = text()
    onLoadFailed: root.brandingText = ""
    onFileChanged: reload()
  }

  FileView {
    path: root.logoArt
    printErrors: false
    onLoaded: root.logoText = text()
  }

  // A monospace cell per pixel of font size, measured large for precision.
  FontMetrics {
    id: unit
    font.family: Style.font.mono
    font.pixelSize: 100
  }

  readonly property var screenSizes: {
    var out = []
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++)
      if (screens[i] && screens[i].width > 0 && screens[i].height > 0) out.push({ width: screens[i].width, height: screens[i].height })
    return out
  }

  // The terminal screensaver's 18 pt font, 24 px at the standard 96 DPI.
  readonly property var grid: Model.grid(screenSizes, art, { advance: unit.advanceWidth("M") / 100, height: unit.height / 100 }, 24)
  property var cellState: Model.blankState(0, 0)

  function resetGrid() {
    cellState = Model.blankState(grid.cols, grid.rows)
    gridReset()
  }

  // The grid's object is new whenever a screen or the art is looked at again;
  // only a different grid starts afresh.
  readonly property string gridKey: grid.fontPx + "/" + grid.cellW + "x" + grid.cellH + "/" + grid.cols + "x" + grid.rows
  onGridKeyChanged: {
    resetGrid()
    // The canvas is ttfx's size: a new grid needs a new run.
    if (ttfx.running) { root.restartAfterExit = true; ttfx.running = false }
    else begin()
  }

  // ------------------------------------------------------------- effects

  property var effectNames: []
  property var bag: []
  property string lastEffect: ""
  property double startedAt: 0
  property int failures: 0
  property int frameNumber: 0
  property string undrawnFrame: ""
  property bool restartAfterExit: false

  function logEvent(event) {
    console.log("karchy screensaver " + new Date().toISOString() + " " + event)
  }

  function begin() {
    if (!wanted || ttfx.running || againTimer.running) return
    if (grid.cols <= 0 || grid.rows <= 0) return
    if (effectNames.length === 0 && !helpProcess.triedOnce) { helpProcess.running = true; return }
    var next = Model.nextEffect(bag, effectNames, lastEffect, Math.random)
    bag = next.bag
    lastEffect = next.name
    // With no list from ttfx, it picks one itself.
    ttfx.effectArgs = next.name ? [next.name] : ["--random-effect"]
    frameNumber = 0
    undrawnFrame = ""
    startedAt = Date.now()
    ttfx.running = true
  }

  function stop() {
    againTimer.stop()
    restartAfterExit = false
    if (ttfx.running) ttfx.running = false
  }

  onWantedChanged: {
    if (wanted) {
      failures = 0
      begin()
    } else {
      stop()
      resetGrid()
    }
  }

  // ttfx steps at 120 frames a second, as the terminal screensaver ran it,
  // so each effect keeps its speed; every second frame is drawn, which is as
  // often as most screens show one.
  function onFrame(data) {
    frameNumber += 1
    if (frameNumber % 2 === 1) { undrawnFrame = data; return }
    undrawnFrame = ""
    draw(data)
  }

  function draw(data) {
    var changed = Model.applyFrame(cellState, data)
    if (changed.length > 0) frameDrawn(changed)
  }

  function effectEnded(exitCode) {
    if (undrawnFrame) { draw(undrawnFrame); undrawnFrame = "" }
    if (restartAfterExit) { restartAfterExit = false; begin(); return }
    if (!wanted) return
    // An effect that ends at once is ttfx failing (no ttfx, unreadable art):
    // after three the screensaver stays black rather than spin.
    if (exitCode !== 0 || Date.now() - startedAt < 1000) {
      failures += 1
      logEvent("ttfx " + ttfx.effectArgs.join(" ") + " ended with " + exitCode + " (" + failures + ")")
      if (failures >= 3) return
      againTimer.interval = 1000
    } else {
      failures = 0
      againTimer.interval = 50
    }
    againTimer.restart()
  }

  Timer {
    id: againTimer
    repeat: false
    onTriggered: root.begin()
  }

  // The names of ttfx's effects, asked once.
  Process {
    id: helpProcess
    property bool triedOnce: false
    command: ["ttfx", "--help"]
    stdout: StdioCollector { id: helpText; waitForEnd: true }
    onExited: {
      triedOnce = true
      root.effectNames = Model.effectNames(helpText.text)
      root.begin()
    }
  }

  Process {
    id: ttfx
    property var effectArgs: ["--random-effect"]
    command: ["ttfx", "-i", root.artPath, "--frame-rate", "120",
      "--canvas-width", String(root.grid.cols), "--canvas-height", String(root.grid.rows), "--ignore-terminal-dimensions",
      "--anchor-canvas", "c", "--anchor-text", "c", "--no-eol", "--no-restore-cursor"].concat(effectArgs)
    // Every frame ends by moving the cursor back up over the canvas.
    stdout: SplitParser {
      splitMarker: "\x1b[" + root.grid.rows + "A"
      onRead: function(data) { root.onFrame(data) }
    }
    onExited: function(exitCode) { root.effectEnded(exitCode) }
  }

  // ------------------------------------------------------------ showing

  function locked() {
    return !!(lockService && lockService.currentlyLocked && lockService.currentlyLocked())
  }

  // Puts the overlay up. A locked session's lock screen draws its own.
  function show() {
    if (locked()) return "locked"
    if (!overlayShown) logEvent("show")
    paused = false
    overlayShown = true
    return "ok"
  }

  // Takes the overlay down without counting it as somebody coming back.
  function end(reason) {
    if (!overlayShown) return
    logEvent("end: " + (reason || "requested"))
    overlayShown = false
    if (!lockShown) paused = false
  }

  // Input on the overlay.
  function dismiss(reason) {
    if (!overlayShown) return
    logEvent("dismissed: " + reason)
    overlayShown = false
    paused = false
    dismissed()
  }

  // The lock screen draws it (or stops), and the screen turning off.
  function holdForLock(on) {
    lockShown = !!on
    if (lockShown) paused = false
  }

  function pause(on) {
    paused = !!on
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: overlay
      required property var modelData
      screen: modelData
      visible: root.overlayShown
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "black"
      WlrLayershell.namespace: "karchy-screensaver"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

      onVisibleChanged: if (visible) pointerGate.reset()

      ScreensaverView {
        anchors.fill: parent
        saver: root
        focus: true
        Keys.onPressed: function(event) { event.accepted = true; root.dismiss("key") }
      }

      // The overlay appearing under a resting pointer reports where it is;
      // only a pointer that then moves is somebody.
      PointerMoveGate { id: pointerGate }

      MouseArea {
        id: pointerArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.BlankCursor
        onPositionChanged: function(mouse) { if (pointerGate.moved(pointerArea, mouse)) root.dismiss("pointer") }
        onPressed: root.dismiss("click")
        onWheel: function(wheel) { if (wheel.angleDelta.x !== 0 || wheel.angleDelta.y !== 0 || wheel.pixelDelta.x !== 0 || wheel.pixelDelta.y !== 0) root.dismiss("scroll") }
      }
    }
  }

  ShellIpc {
    target: "screensaver"

    function show(): string { return root.show() }
    function hide(): string { root.end("ipc"); return "ok" }
    function status(): string {
      return JSON.stringify({
        overlay: root.overlayShown,
        lock: root.lockShown,
        paused: root.paused,
        running: ttfx.running,
        effect: root.lastEffect,
        effects: root.effectNames.length,
        art: root.artPath,
        grid: root.grid,
        failures: root.failures
      })
    }
  }
}
