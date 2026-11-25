import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Every shared control that can be busy, in each state, on one page: what
// docs/architecture.md › Busy describes, to look at after a change to
// Ui/Spinner, Ui/Button, Ui/ToggleSwitch, Ui/Toggle, Ui/SettingRow or
// Ui/EmptyState.
//
//   tools/shell-render ../tools/shell-render.d/BusyGallery.qml gallery:0x0
//
// Each row is one control four times: idle, busy, busy while its caller also
// disabled it (which must look like busy), and disabled. A busy control is
// as wide as the idle one beside it.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string karchyPath: ""
  property bool opened: false

  function open(payload) { root.opened = true }
  function close() { root.opened = false }

  component States: RowLayout {
    id: line
    property string name: ""
    property Component control: null
    Layout.fillWidth: true
    spacing: Style.spacing.xxl

    Text {
      Layout.preferredWidth: Style.space(150)
      textFormat: Text.PlainText
      text: line.name
      color: Commons.Color.textSecondary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    Repeater {
      model: [{ busy: false, enabled: true }, { busy: true, enabled: true }, { busy: true, enabled: false }, { busy: false, enabled: false }]
      Item {
        id: cell
        required property var modelData
        Layout.preferredWidth: Style.space(150)
        implicitHeight: loader.implicitHeight
        Loader {
          id: loader
          sourceComponent: line.control
          onLoaded: {
            item.busy = cell.modelData.busy
            item.enabled = cell.modelData.enabled
            item.objectName = line.name + (cell.modelData.busy ? " busy" : "") + (cell.modelData.enabled ? "" : " disabled")
          }
        }
      }
    }
  }

  FloatingWindow {
    visible: root.opened
    title: "Busy states"
    color: Commons.Color.background
    implicitWidth: Style.space(860)
    implicitHeight: page.implicitHeight + Style.spacing.huge * 2

    ColumnLayout {
      id: page
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.huge
      spacing: Style.spacing.xl

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.xxl
        Repeater {
          model: ["", "Idle", "Busy", "Busy, disabled by its caller", "Disabled"]
          Text {
            required property string modelData
            Layout.preferredWidth: Style.space(150)
            textFormat: Text.PlainText
            text: modelData
            color: Commons.Color.textSecondary
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            wrapMode: Text.Wrap
          }
        }
      }

      States { name: "Button"; control: Component { Button { bordered: true; focusable: true; text: "Test sound" } } }
      States { name: "Primary"; control: Component { Button { variant: "primary"; focusable: true; text: "Save changes" } } }
      States { name: "Destructive"; control: Component { Button { variant: "destructive"; bordered: true; focusable: true; text: "Remove" } } }
      States { name: "With an icon"; control: Component { Button { variant: "primary"; focusable: true; text: "Start"; iconText: Icons.glyph("media.play") } } }
      States { name: "Icon only"; control: Component { Button { bordered: true; focusable: true; iconText: Icons.glyph("ui.refresh"); tooltipText: "Refresh" } } }
      States { name: "Plain"; control: Component { Button { focusable: true; text: "Check now" } } }
      States { name: "Switch, off"; control: Component { ToggleSwitch { flush: true; accessibleName: "Off" } } }
      States { name: "Switch, on"; control: Component { ToggleSwitch { flush: true; checked: true; accessibleName: "On" } } }
      States { name: "Small switch"; control: Component { ToggleSwitch { flush: true; checked: true; trackHeight: 14; accessibleName: "Small" } } }
      States { name: "Setting row"; control: Component { SettingRow { label: "Metered"; labelWidth: 0; checked: true } } }
      States { name: "Panel row"; control: Component { Toggle { width: Style.space(150); flat: true; label: "Night light"; checked: true } } }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.xxl
        Text {
          Layout.preferredWidth: Style.space(150)
          textFormat: Text.PlainText
          text: "Spinner sizes"
          color: Commons.Color.textSecondary
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        Repeater {
          model: [Style.font.iconSmall, Style.font.icon, Style.font.iconLarge, Style.font.iconHero, Style.font.displayLarge]
          Spinner { required property int modelData; size: modelData }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.xxl
        EmptyState { Layout.fillWidth: true; busy: true; title: "Reading containers" }
        EmptyState { Layout.fillWidth: true; centered: true; busy: true; iconName: "update"; title: "Checking for updates" }
      }
    }
  }
}
