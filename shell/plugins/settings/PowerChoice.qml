import QtQuick
import QtQuick.Layouts
import qs.Ui

// One choice on Settings › Power: a dropdown that always shows the value in
// effect, read back from the system after every change. A value the choices
// don't list (set by hand in a file) is added under the name `nameFor` gives
// it, so the page never shows something that isn't so.
Dropdown {
  id: root

  // The Power page: `values`, `set(setting, value)` and the `loaded` signal.
  property var page: null
  property string setting: ""
  property var choices: []
  property var nameFor: function(value) { return String(value) }

  readonly property string current: page && page.values[setting] !== undefined ? String(page.values[setting]) : ""

  function sync() { if (root.value !== root.current) root.value = root.current }

  showLabel: false
  Layout.fillWidth: true
  Layout.minimumWidth: implicitWidth * 0.6
  enabled: current !== ""

  options: {
    for (var i = 0; i < choices.length; i++)
      if (String(choices[i].value) === current) return choices
    if (current === "") return choices
    // In its place among times and percentages ("0" is Never, kept last);
    // after the rest otherwise.
    var at = choices.length
    if (Number(current) > 0) {
      for (var j = 0; j < choices.length; j++) {
        var other = Number(choices[j].value)
        if (other === 0 || other > Number(current)) { at = j; break }
      }
    }
    return choices.slice(0, at).concat([{ value: current, label: nameFor(current) }], choices.slice(at))
  }

  onCurrentChanged: sync()
  Component.onCompleted: sync()
  onChanged: function(value) { if (page && value !== current) page.set(setting, value) }

  // A change that didn't take (refused, or decided elsewhere) goes back to
  // what is in effect.
  Connections {
    target: root.page
    function onLoaded() { root.sync() }
  }
}
