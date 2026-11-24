import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.Commons

// tools/shell-render's Quickshell config: loads one shell window as
// shell.qml does, sizes it, plays the steps of each shot and saves a picture
// and a text listing. Driven by environment variables the tool sets:
//   RENDER_PLUGIN   file:// URL of the window's QML
//   RENDER_PAYLOAD  the summon payload (JSON)
//   RENDER_SHOTS    "name:WxH[:steps]" joined by newlines
//   RENDER_OUT      folder for <name>.png and <name>.txt
//   RENDER_WAIT     milliseconds to let the window load its data
ShellRoot {
  id: shell

  // What a window asks of the shell it runs in.
  property string karchyPath: Quickshell.env("KARCHY_PATH")
  function hide(id) {}
  function summon(id, payload) { console.log("RENDER summon", id, payload); return true }
  function serviceFor(id) { return null }

  property var shots: (Quickshell.env("RENDER_SHOTS") || "").split("\n").filter(function(s) { return s !== "" })
  property int at: -1
  property var steps: []
  property var wrapper: null
  property var failed: false

  readonly property var shot: {
    if (at < 0 || at >= shots.length) return null
    var parts = shots[at].split(":")
    var size = (parts[1] || "0x0").split("x")
    return { name: parts[0], width: Number(size[0]), height: Number(size[1]), steps: parts.slice(2).join(":") }
  }

  TestEvent { id: events }

  Loader {
    id: loader
    source: Quickshell.env("RENDER_PLUGIN")
    asynchronous: true
    onLoaded: {
      if ("karchyPath" in item) item.karchyPath = shell.karchyPath
      if ("shell" in item) item.shell = shell
      if ("manifest" in item) item.manifest = { id: "render" }
      item.open(Quickshell.env("RENDER_PAYLOAD") || "{}")
      settle.interval = Number(Quickshell.env("RENDER_WAIT") || 2500)
      settle.start()
    }
    onStatusChanged: if (status === Loader.Error) { console.log("RENDER error: the window didn't load"); Qt.exit(1) }
  }

  // The plugin's FloatingWindow is among the loaded item's resources.
  function findWindow() {
    var all = loader.item.resources
    for (var i = 0; i < all.length; i++)
      if (all[i] && all[i].title !== undefined && all[i].implicitWidth !== undefined && all[i].contentItem !== undefined) return all[i]
    return null
  }

  // A window's own content item has no QML context, so grabToImage fails on
  // it. Its children move into an item of ours that has one. A popup's
  // overlay is made the first time a popup opens, as a child of the real
  // window's content item (one above Quickshell's), so this runs again
  // before every picture and takes what it finds on both.
  function adopt() {
    var holders = [shell.wrapper.parent, shell.wrapper.Window.contentItem]
    for (var h = 0; h < holders.length; h++) {
      var holder = holders[h]
      if (!holder) continue
      var kids = []
      for (var i = 0; i < holder.children.length; i++) {
        var kid = holder.children[i]
        var holdsWrapper = false
        for (var p = shell.wrapper; p; p = p.parent) if (p === kid) holdsWrapper = true
        if (!holdsWrapper) kids.push(kid)
      }
      for (var j = 0; j < kids.length; j++) kids[j].parent = shell.wrapper
    }
  }

  readonly property var keyNames: ({
    Tab: Qt.Key_Tab, Down: Qt.Key_Down, Up: Qt.Key_Up, Left: Qt.Key_Left, Right: Qt.Key_Right,
    Return: Qt.Key_Return, Enter: Qt.Key_Return, Escape: Qt.Key_Escape, Space: Qt.Key_Space, End: Qt.Key_End,
    Home: Qt.Key_Home, PageDown: Qt.Key_PageDown, PageUp: Qt.Key_PageUp, Backspace: Qt.Key_Backspace,
    Delete: Qt.Key_Delete, F5: Qt.Key_F5
  })

  // One step: a key, a chord, text, a click or a pause. False for a step
  // that isn't known.
  function play(step) {
    var window = shell.wrapper.Window.window
    if (step.indexOf("text=") === 0) {
      var text = step.slice(5)
      for (var i = 0; i < text.length; i++) events.keyClickChar(text[i], Qt.NoModifier, 0)
    } else if (step.indexOf("click=") === 0 || step.indexOf("right=") === 0) {
      var at = step.slice(step.indexOf("=") + 1).split(",")
      events.mouseClick(shell.wrapper, Number(at[0]), Number(at[1]),
        step.charAt(0) === "r" ? Qt.RightButton : Qt.LeftButton, Qt.NoModifier, 0)
    } else if (step.indexOf("move=") === 0) {
      var to = step.slice(5).split(",")
      events.mouseMove(shell.wrapper, Number(to[0]), Number(to[1]), 0, Qt.NoButton)
    } else if (step.indexOf("wait=") === 0) {
      return Number(step.slice(5))
    } else if (step === "Backtab" || step === "Shift+Tab") {
      events.keyClick(Qt.Key_Backtab, Qt.ShiftModifier, 0)
    } else if (step.indexOf("Ctrl+") === 0) {
      var name = step.slice(5)
      if (shell.keyNames[name] !== undefined) events.keyClick(shell.keyNames[name], Qt.ControlModifier, 0)
      else events.keyClickChar(name, Qt.ControlModifier, 0)
    } else if (shell.keyNames[step] !== undefined) {
      events.keyClick(shell.keyNames[step], Qt.NoModifier, 0)
    } else if (step.length === 1) {
      events.keyClickChar(step, Qt.NoModifier, 0)
    } else {
      console.log("RENDER error: unknown step", step)
      shell.failed = true
    }
    return 0
  }

  function shown(item) {
    for (var p = item; p; p = p.parent) if (!p.visible || p.opacity === 0) return false
    return true
  }

  // Every visible piece of text with where it is, and whether it was cut
  // short (an elided label) or sticks out of the window.
  function collect(item, out) {
    if (!item || !item.visible || item.opacity === 0) return
    var isText = typeof item.text === "string" && item.font !== undefined && item.contentWidth !== undefined
    if (item.width > 0 && item.height > 0) {
      var p = item.mapToItem(shell.wrapper, 0, 0)
      var over = p.x + item.width - shell.wrapper.width
      var outside = (over > 1 || p.x < -1) && (isText || item.children.length === 0)
      if (isText && item.text !== "") {
        out.push({
          x: Math.round(p.x), y: Math.round(p.y), w: Math.round(item.width), text: item.text,
          icon: item.font.family === Icons.family, elided: item.truncated === true,
          off: p.y + item.height < 0 || p.y > shell.wrapper.height,
          cut: outside ? (over > 1 ? "+" + Math.round(over) : String(Math.round(p.x))) : ""
        })
      } else if (outside) {
        out.push({ x: Math.round(p.x), y: Math.round(p.y), w: Math.round(item.width), text: String(item), icon: false,
          elided: false, off: false, cut: over > 1 ? "+" + Math.round(over) : String(Math.round(p.x)) })
        return
      }
    }
    var kids = item.children
    for (var i = 0; i < kids.length; i++) collect(kids[i], out)
  }

  // The item the keyboard is on: its type and its words, or the words of
  // the nearest thing around it that has some (a list's row has none of its
  // own).
  function describe(item) {
    if (!item) return "none"
    function words(i) {
      var name = i.Accessible && i.Accessible.name ? i.Accessible.name : ""
      return String(name || i.text || i.label || i.placeholderText || i.tooltipText || "")
    }
    function type(i) { return String(i).replace(/_QML.*$/, "").replace(/\(0x.*$/, "").replace(/^QQuick/, "") }
    var own = words(item)
    if (own !== "") return type(item) + " \"" + own + "\""
    for (var p = item.parent; p; p = p.parent)
      if (words(p) !== "") return type(item) + " in " + type(p) + " \"" + words(p) + "\""
    return type(item)
  }

  function next() {
    shell.at++
    if (shell.at >= shell.shots.length) { Qt.exit(shell.failed ? 1 : 0); return }
    var window = shell.wrapper.Window.window
    if (shell.shot.width > 0) { window.width = shell.shot.width; window.height = shell.shot.height }
    shell.steps = shell.shot.steps.split(" ").filter(function(s) { return s !== "" })
    stepTimer.interval = 400
    stepTimer.start()
  }

  Timer {
    id: settle
    onTriggered: {
      var window = shell.findWindow()
      if (!window) { console.log("RENDER error: the plugin has no window"); Qt.exit(1); return }
      shell.wrapper = Qt.createQmlObject(
        'import QtQuick; import qs.Commons as Commons; Rectangle { anchors.fill: parent; color: Commons.Color.background }',
        window.contentItem)
      shell.adopt()
      shell.next()
    }
  }

  // The steps one at a time, so that what a key starts (a popup opening, the
  // keyboard moving with Qt.callLater) has happened before the next one.
  Timer {
    id: stepTimer
    onTriggered: {
      if (shell.steps.length === 0) { grab.start(); return }
      var step = shell.steps[0]
      shell.steps = shell.steps.slice(1)
      var pause = shell.play(step)
      stepTimer.interval = Math.max(120, pause)
      stepTimer.start()
    }
  }

  Timer {
    id: grab
    interval: 500
    onTriggered: {
      var name = shell.shot.name
      var item = shell.wrapper
      // A step closed the window (Escape does, in most of them): there is
      // nothing to draw, and grabToImage would never answer.
      if (!item.Window.window || !item.Window.window.visible) {
        console.log("RENDER error: the window was closed before shot", name)
        Qt.exit(1)
        return
      }
      shell.adopt()
      var texts = []
      shell.collect(item, texts)
      texts.sort(function(a, b) { return a.y - b.y || a.x - b.x })
      var lines = [], cut = [], elided = []
      for (var i = 0; i < texts.length; i++) {
        var t = texts[i]
        if (t.cut !== "") cut.push(t.cut + " '" + t.text.slice(0, 40) + "'")
        if (t.elided && !t.off) elided.push("'" + t.text.slice(0, 60) + "'")
        if (!t.icon && !t.off) lines.push(t.y + "\t" + t.x + "\t" + t.w + "\t" + (t.elided ? "elided" : "") + "\t" + t.text.replace(/\n/g, " / "))
      }
      console.log("RENDER shot", name, item.width + "x" + item.height, "focus:", shell.describe(item.Window.activeFocusItem))
      if (cut.length > 0) console.log("RENDER cut", name, cut.slice(0, 12).join(" | "))
      if (elided.length > 0) console.log("RENDER elided", name, elided.slice(0, 12).join(" | "))
      listing.path = Quickshell.env("RENDER_OUT") + "/" + name + ".txt"
      listing.setText("# y\tx\twidth\t\ttext (" + item.width + "x" + item.height + ", focus: "
        + shell.describe(item.Window.activeFocusItem) + ")\n" + lines.join("\n") + "\n")
      item.grabToImage(function(result) {
        result.saveToFile(Quickshell.env("RENDER_OUT") + "/" + name + ".png")
        shell.next()
      })
    }
  }

  FileView { id: listing; preload: false; atomicWrites: false; printErrors: true }
}
