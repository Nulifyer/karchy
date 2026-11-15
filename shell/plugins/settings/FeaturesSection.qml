import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Optional features (D-28): things most machines don't need, added
// or removed in one click. The list is $KARCHY_PATH/default/karchy/features.json;
// each feature's command answers status, install and remove. Install and
// remove run in a floating terminal so pacman's progress and the password
// prompt are visible.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  property string karchyPath: Quickshell.env("KARCHY_PATH")
  // The Settings window, for its confirm dialog (set by its Loader).
  property var settings: null
  property var features: []
  property var states: ({})
  // The feature whose install or removal is running in the terminal.
  property string running: ""

  function refresh() {
    featuresFile.reload()
  }

  function run(feature, action) {
    root.running = feature.id
    runProc.command = ["karchy-launch-floating-terminal-with-presentation", feature.command, action]
    runProc.running = true
  }

  function load(text) {
    try { root.features = JSON.parse(text) } catch (e) { root.features = [] }
    statusProc.command = ["bash", "-c", root.features.map(function(f) {
      return "printf '%s\\t%s\\n' " + Util.shellQuote(f.id) + " \"$(" + Util.shellQuote(f.command) + " status)\""
    }).join("; ")]
    statusProc.running = true
  }

  FileView {
    id: featuresFile
    path: root.karchyPath + "/default/karchy/features.json"
    onLoaded: root.load(text())
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = {}
        text.split("\n").forEach(function(line) {
          var parts = line.split("\t")
          if (parts.length === 2) next[parts[0]] = parts[1]
        })
        root.states = next
      }
    }
  }

  // The terminal closes when the command ends; check again then.
  Process {
    id: runProc
    onExited: {
      root.running = ""
      root.refresh()
    }
  }

  PageHeader {
    title: "Optional features"
    explanation: "Things most machines don't need. Adding one installs its packages and sets them up; removing it takes both away again. Both run in a terminal, so you see the progress and the password prompt."
  }

  Repeater {
    model: root.features
    delegate: Card {
      id: card
      required property var modelData
      readonly property string state: root.states[modelData.id] || ""
      readonly property bool installed: state === "installed"
      title: modelData.name
      subtitle: modelData.description
      trailing: Button {
        focusable: true
        visible: card.state !== ""
        text: card.installed ? "Remove" : "Add"
        variant: card.installed ? "destructive" : "neutral"
        bordered: true
        busy: root.running === card.modelData.id
        enabled: root.running === "" || root.running === card.modelData.id
        // Removing uninstalls packages, so it asks first (Cancel focused).
        onClicked: {
          var feature = card.modelData
          if (!card.installed) root.run(feature, "install")
          else if (root.settings) root.settings.ask("Remove " + feature.name + "? Its packages are uninstalled; you can add it again later.",
            "Remove", function() { root.run(feature, "remove") })
        }
      }
    }
  }
}
