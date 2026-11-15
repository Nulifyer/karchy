import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The "Virtual machines" window (D-63): every VM, creating one, its settings
// while it is off, snapshots, forcing off and deleting it. A normal
// application window, like Settings. Everything goes through karchy-vm; this
// window only reads `karchy-vm list --json` (every two seconds while it is
// open) and runs karchy-vm commands.
//
// Layout (docs/architecture.md, "Panels and windows"): a sidebar of VMs drawn
// with the bar panel's VmRow (same names, icons, status lines and run
// switch), then the selected VM's page: a PageHeader with its one primary
// action, Cards for what it is doing, its settings and its snapshots, and the
// actions that can't be undone apart at the bottom, each confirmed with
// Cancel focused.
//
// Keyboard: Tab walks the filter, the VM list, "New VM", then the page;
// j/k or Up/Down move through the list; Ctrl+F filters; Escape closes.
//
// Open it with: karchy vm manage [name]
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  property var vms: []
  property bool loaded: false
  property bool installed: true
  // A VM's name, or "" for the new-VM page.
  property string selected: ""
  property var cpuPercent: ({})
  property var cpuPrev: ({})
  property var snapshots: []
  property string error: ""
  property string notice: ""
  property string busy: ""
  // The sidebar's name filter (Ctrl+F).
  property string filter: ""
  // What to do with the next ISO the file chooser returns: "create", "set" or "boot".
  property string isoTarget: ""
  property string createIso: ""

  readonly property var rows: Model.sorted(vms)
  readonly property var listRows: Model.filtered(rows, filter)
  readonly property var current: Model.find(vms, selected)
  readonly property bool currentRunning: Model.isRunning(current)
  readonly property string home: Quickshell.env("HOME")

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    if (payload && payload.vm) root.selected = String(payload.vm)
    root.filter = ""
    root.opened = true
    root.error = ""
    root.notice = ""
    installedProc.running = true
    root.refresh()
  }

  // shell.hide calls back into close(); only the first call does anything.
  function close() {
    if (!root.opened) return
    root.opened = false
    if (root.shell && root.manifest) root.shell.hide(root.manifest.id)
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // Until QEMU is there, look for it too: it may be added while this is open.
  function refresh() {
    if (!listProc.running) listProc.running = true
    if (!root.installed && !installedProc.running) installedProc.running = true
  }

  function refreshSnapshots() {
    if (!root.current) { root.snapshots = []; return }
    snapProc.command = ["karchy-vm", "snapshot", "list", root.selected, "--json"]
    snapProc.running = true
  }

  onSelectedChanged: {
    root.snapshots = []
    root.error = ""
    root.notice = ""
    refreshSnapshots()
  }

  // The VM `dy` places from the selected one in the (filtered) list.
  function step(dy) {
    var list = root.listRows
    if (list.length === 0) return
    var i = -1
    for (var j = 0; j < list.length; j++) if (list[j].name === root.selected) i = j
    i = i < 0 ? 0 : Math.max(0, Math.min(list.length - 1, i + dy))
    root.selected = list[i].name
  }

  // Start a stopped VM (and show it), ask a running one to shut down: the
  // run switch, here as in the bar panel.
  function power(vm) {
    if (!vm) return
    if (Model.switchAction(vm) === "start") root.startAndOpen(vm.name)
    else root.stopVm(vm.name)
  }

  function update(text) {
    var list = Model.parse(text)
    if (list === null) return
    var sample = Model.sampleCpu(list, root.cpuPrev, Date.now())
    root.cpuPercent = sample.percent
    root.cpuPrev = sample.prev
    var hadCurrent = !!root.current
    root.vms = list
    // First load, or the selected VM was deleted: show the first VM.
    if ((!root.loaded || hadCurrent) && !root.current)
      root.selected = list.length > 0 ? Model.sorted(list)[0].name : ""
    if (!root.loaded) refreshSnapshots()
    root.loaded = true
  }

  // Run one karchy-vm command; its message or error shows at the top of the page.
  function run(args, label, after) {
    if (actionProc.running) return
    root.error = ""
    root.notice = ""
    root.busy = label || ""
    actionProc.after = after || null
    actionProc.pendingParts = 3
    actionProc.command = ["karchy-vm"].concat(args)
    actionProc.running = true
  }

  function setKey(key, value) {
    if (!root.current) return
    root.run(["set", root.selected, key, String(value)], "Saving…")
  }

  // Stop waits for the guest, so it runs detached and the list catches up.
  function stopVm(name) {
    Quickshell.execDetached(["karchy-vm", "stop", name])
    root.notice = "Asked " + name + " to shut down."
  }

  function openVm(name) { Quickshell.execDetached(["karchy-vm", "open", name]) }

  // Follow-ups live here, not in a page: a page can be gone (create swaps
  // to the new VM's page) by the time its command finishes.
  function startAndOpen(name) {
    root.run(["start", name], "Starting " + name + "…", function() { root.openVm(name) })
  }

  function createVm(args, name, start) {
    root.run(args, "Creating " + name + "…", function() {
      root.createIso = ""
      root.selected = name
      if (start) root.startAndOpen(name)
    })
  }

  // The portal's file chooser, through karchy-vm (out of the shell's process).
  function chooseIso(target) {
    if (chooserProc.running) return
    root.isoTarget = target
    chooserProc.command = ["karchy-vm", "choose-iso",
      target === "boot" ? "Boot once from an ISO" : "Choose an installer ISO", root.home + "/Downloads"]
    chooserProc.running = true
  }

  function isoChosen(path) {
    if (root.isoTarget === "create") root.createIso = path
    else if (root.isoTarget === "set") root.setKey("iso", path)
    else if (root.isoTarget === "boot" && root.current) root.run(["start", root.selected, "--iso", path], "Starting…")
    root.isoTarget = ""
  }

  Process {
    id: listProc
    command: ["karchy-vm", "list", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.update(text) }
  }

  Process {
    id: chooserProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path !== "") root.isoChosen(path)
        else root.isoTarget = ""
      }
    }
  }

  Process {
    id: installedProc
    command: ["bash", "-c", "command -v qemu-system-x86_64 >/dev/null && command -v spicy >/dev/null"]
    onExited: function(code) { root.installed = code === 0 }
  }

  Process {
    id: snapProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.snapshots = JSON.parse(text.trim() || "[]") } catch (e) { root.snapshots = [] }
      }
    }
  }

  // Exit and the end of each stream come in no fixed order; finish once all
  // three are in.
  Process {
    id: actionProc
    property var after: null
    property int pendingParts: 0
    property int exitCode: 0
    property string outText: ""
    property string errText: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { actionProc.outText = text; actionProc.part() } }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: { actionProc.errText = text; actionProc.part() } }
    onExited: function(code) { exitCode = code; part() }

    function part() {
      if (--pendingParts > 0) return
      var after = actionProc.after
      actionProc.after = null
      root.busy = ""
      if (exitCode !== 0) {
        root.error = String(errText || "").trim().replace(/^karchy-vm: /gm, "") || "That didn't work."
      } else {
        var out = String(outText || "").trim().split("\n")
        root.notice = out[out.length - 1] || ""
        if (typeof after === "function") Qt.callLater(after)
      }
      root.refresh()
      root.refreshSnapshots()
    }
  }

  Timer { interval: 2000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  // Keep the focused control on screen as Tab walks down a long page.
  function revealFocused(item) {
    var p = item
    while (p && p !== page) p = p.parent
    if (!p) return
    var margin = Style.spacing.panelPadding
    var top = item.mapToItem(content.contentItem, 0, 0).y
    var bottom = top + item.height
    var maxY = Math.max(0, content.contentHeight - content.height)
    if (top - margin < content.contentY) content.contentY = Math.max(0, top - margin)
    else if (bottom + margin > content.contentY + content.height)
      content.contentY = Math.min(maxY, bottom + margin - content.height)
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "Virtual machines"
    color: Commons.Color.background
    readonly property var fitScreen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.lastIpcObject
      ? Hyprland.focusedMonitor.lastIpcObject : null
    readonly property real screenWidth: fitScreen ? fitScreen.width / fitScreen.scale : 1280
    readonly property real screenHeight: fitScreen ? fitScreen.height / fitScreen.scale : 800
    implicitWidth: Math.round(Math.min(Style.space(960), screenWidth * 0.85))
    implicitHeight: Math.round(Math.min(Style.space(680), screenHeight * 0.85))

    onVisibleChanged: {
      if (!visible && root.opened) root.close()
      // Start in the VM list, so j/k, Tab and Escape work at once.
      if (visible) Qt.callLater(function() { vmList.forceActiveFocus() })
    }

    Shortcut {
      sequence: "Ctrl+F"
      enabled: root.opened && !confirm.opened
      onActivated: filterField.forceActiveFocus(Qt.ShortcutFocusReason)
    }

    RowLayout {
      id: frame
      anchors.fill: parent
      spacing: 0
      readonly property Item focusedItem: frame.Window.activeFocusItem
      onFocusedItemChanged: root.revealFocused(focusedItem)
      // Keys the focused control leaves unhandled end up here. An open
      // dropdown's list sits in its own popup and takes Escape first.
      Keys.onEscapePressed: root.close()

      // ---------- VM list ----------
      Rectangle {
        Layout.fillHeight: true
        Layout.preferredWidth: Style.space(250)
        color: Util.alpha(Commons.Color.foreground, 0.04)

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.spacing.lg

          // The window's name, quieter than the page title beside it.
          Text {
            text: "Virtual machines"
            color: Commons.Color.textSecondary
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          TextField {
            id: filterField
            visible: root.rows.length > 1
            Layout.fillWidth: true
            placeholderText: "Filter  (Ctrl+F)"
            onTextChanged: root.filter = text
            Keys.onEscapePressed: function(event) {
              if (text !== "") text = ""
              else vmList.forceActiveFocus(Qt.TabFocusReason)
            }
            Keys.onDownPressed: vmList.forceActiveFocus(Qt.TabFocusReason)
            onAccepted: { if (root.listRows.length > 0) root.selected = root.listRows[0].name; vmList.forceActiveFocus(Qt.TabFocusReason) }
          }

          // One Tab stop; j/k or the arrows move the selection, and the page
          // follows it.
          Item {
            id: vmList
            Layout.fillWidth: true
            Layout.fillHeight: true
            activeFocusOnTab: true
            Accessible.role: Accessible.List
            Accessible.name: "Virtual machines"

            Keys.onPressed: function(event) {
              InputMode.keyPressed()
              if (event.key === Qt.Key_Down || event.text === "j") { root.step(1); event.accepted = true }
              else if (event.key === Qt.Key_Up || event.text === "k") { root.step(-1); event.accepted = true }
              else if (event.key === Qt.Key_Home) { root.step(-1000); event.accepted = true }
              else if (event.key === Qt.Key_End) { root.step(1000); event.accepted = true }
            }

            Flickable {
              id: listFlick
              anchors.fill: parent
              clip: true
              contentHeight: vmColumn.implicitHeight
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: vmColumn
                width: listFlick.width
                spacing: Style.spacing.sm

                Repeater {
                  model: root.listRows
                  delegate: VmRow {
                    required property var modelData
                    width: vmColumn.width
                    vm: modelData
                    cpuPercent: root.cpuPercent[modelData.name]
                    showOpen: false
                    current: root.selected === modelData.name
                    hasCursor: pointerOver || (vmList.activeFocus && current)
                    foreground: Commons.Color.foreground
                    surface: Commons.Color.background
                    onCurrentChanged: if (current) listFlick.contentY = Math.max(0, Math.min(y, listFlick.contentHeight - listFlick.height))
                    onClicked: {
                      root.selected = modelData.name
                      vmList.forceActiveFocus(Qt.MouseFocusReason)
                    }
                    onPowerToggled: root.power(modelData)
                  }
                }

                Text {
                  visible: root.loaded && root.rows.length > 0 && root.listRows.length === 0
                  width: parent.width
                  wrapMode: Text.Wrap
                  text: "No VM matches “" + root.filter + "”."
                  color: Commons.Color.textSecondary
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          Button {
            Layout.fillWidth: true
            focusable: true
            leftAlign: true
            iconText: Icons.glyph("ui.add")
            text: "New VM"
            bordered: true
            selected: root.selected === "" && root.installed
            enabled: root.installed
            onClicked: root.selected = ""
          }
        }
      }

      // ---------- Page ----------
      Flickable {
        id: content
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: width
        contentHeight: page.implicitHeight + Style.spacing.panelPadding * 2
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
          id: page
          x: Style.spacing.panelPadding * 2
          y: Style.spacing.panelPadding
          width: content.width - Style.spacing.panelPadding * 4
          spacing: Style.spacing.xxl

          Loader {
            Layout.fillWidth: true
            active: root.opened
            sourceComponent: !root.installed ? notInstalledPage : (root.current ? detailPage : createPage)
          }
        }
      }
    }

    ConfirmDialog {
      id: confirm
      anchors.fill: parent
      property var onYes: null
      property Item returnFocus: null
      ownsKeys: true
      confirmText: "Delete"
      function finish() {
        opened = false
        onYes = null
        if (returnFocus) returnFocus.forceActiveFocus()
        returnFocus = null
      }
      onCanceled: finish()
      onConfirmed: {
        var action = onYes
        finish()
        if (typeof action === "function") action()
      }
    }
  }

  // Everything this window asks about deletes, discards or forces something,
  // so the dialog opens on Cancel.
  function ask(message, confirmText, action) {
    confirm.returnFocus = frame.Window.activeFocusItem
    confirm.message = message
    confirm.confirmText = confirmText
    confirm.onYes = action
    confirm.opened = true
  }

  // ---------- Pages ----------

  Component {
    id: notInstalledPage
    EmptyState {
      centered: true
      Layout.fillWidth: true
      iconName: "vms"
      title: "Virtual machines aren't set up"
      body: "Add them in Settings › Optional features: that installs QEMU, the UEFI firmware, a software TPM and the viewer."
      actionText: "Open Optional features"
      onAction: Quickshell.execDetached(["karchy-settings", "features"])
    }
  }

  Component {
    id: createPage
    ColumnLayout {
      id: form
      spacing: Style.spacing.xxl

      property string os: "linux"
      property string disk: "64G"
      property string ram: os === "windows" ? "8G" : "4G"
      property int cpus: os === "windows" ? 4 : 2
      property bool startNow: true
      readonly property string name: nameField.text.trim()
      readonly property bool nameTaken: !!Model.find(root.vms, name)
      readonly property bool valid: Model.validName(name) && !nameTaken && Model.validSize(disk) && Model.validRam(ram)
      readonly property bool creating: root.busy.indexOf("Creating") === 0

      function create() {
        if (!valid || root.busy !== "") return
        var args = ["create", name, "--os", os, "--disk", disk, "--ram", ram, "--cpus", String(cpus)]
        if (root.createIso !== "") args.push("--iso", root.createIso)
        root.createVm(args, name, startNow)
      }

      PageHeader {
        iconName: "ui.add"
        title: "New VM"
        explanation: "The VM gets a folder of its own in ~/VMs. It boots the installer ISO until a system is installed on its disk."
      }

      Messages {}

      Card {
        GridLayout {
          Layout.fillWidth: true
          columns: 2
          columnSpacing: Style.spacing.xxl
          rowSpacing: Style.spacing.md

          FormLabel { text: "Name" }
          TextField {
            id: nameField
            Layout.fillWidth: true
            placeholderText: "e.g. arch or win11"
            onAccepted: form.create()
          }

          FormLabel { text: "System" }
          ButtonGroup {
            options: [{ value: "linux", label: "Linux", icon: Icons.glyph(Model.osIcon("linux")) }, { value: "windows", label: "Windows", icon: Icons.glyph(Model.osIcon("windows")) }]
            value: form.os
            onChanged: function(value) { form.os = value }
          }

          FormLabel { text: "Installer ISO" }
          IsoPicker {
            path: root.createIso
            onBrowse: root.chooseIso("create")
            onClear: root.createIso = ""
          }

          FormLabel { text: "Disk" }
          TextField {
            Layout.preferredWidth: Style.space(120)
            text: form.disk
            onTextEdited: form.disk = text.trim()
          }

          FormLabel { text: "Memory" }
          Dropdown {
            Layout.preferredWidth: Style.space(160)
            showLabel: false
            value: form.ram
            options: ramOptions(form.ram)
            onChanged: function(value) { form.ram = value }
          }

          FormLabel { text: "CPUs" }
          NumberField {
            from: 1
            to: 64
            value: form.cpus
            onModified: function(value) { form.cpus = value }
          }
        }

        Body {
          visible: form.os === "windows"
          text: "Windows gets a TPM 2.0 and Secure Boot firmware for Windows 11, a SATA disk and an Intel network card, so its installer works without extra drivers."
        }

        Toggle {
          Layout.fillWidth: true
          label: "Start it and show its screen"
          checked: form.startNow
          onClicked: form.startNow = !form.startNow
        }
      }

      Text {
        visible: form.name !== "" && !form.valid
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: form.nameTaken ? "There is already a VM called " + form.name + "."
          : !Model.validName(form.name) ? "Use letters, digits, '.', '_' and '-' for the name."
          : "Sizes look like 64G (disk) and 4G (memory)."
        color: Commons.Color.status.error
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Button {
        focusable: true
        variant: "primary"
        text: "Create VM"
        iconText: Icons.glyph("ui.add")
        enabled: form.valid && (root.busy === "" || form.creating)
        busy: form.creating
        onClicked: form.create()
      }
    }
  }

  Component {
    id: detailPage
    ColumnLayout {
      id: detail
      spacing: Style.spacing.xxl
      // The page outlives a deleted VM by a moment.
      readonly property var vm: root.current || ({ name: "", state: "stopped", cpus: 1 })
      readonly property bool running: root.currentRunning
      readonly property bool editable: !running && root.busy === ""
      readonly property string role: Model.statusRole(vm)

      // Name, state, and the one thing to do with it now.
      PageHeader {
        iconName: Model.osIcon(detail.vm.os)
        iconColor: detail.running ? Commons.Color.foreground : Commons.Color.textSecondary
        title: detail.vm.name
        status: Model.statusLine(detail.vm, root.cpuPercent[detail.vm.name], "")
        statusColor: detail.role === "success" ? Commons.Color.status.success
          : detail.role === "warning" ? Commons.Color.status.warning
          : Commons.Color.textSecondary

        Button {
          visible: detail.vm.state === "running"
          focusable: true
          text: "Shut down"
          iconText: Icons.glyph("system.power")
          bordered: true
          onClicked: root.stopVm(detail.vm.name)
        }
        Button {
          visible: detail.vm.state === "running"
          focusable: true
          variant: "primary"
          text: "Show screen"
          iconText: Icons.glyph("ui.open-external")
          onClicked: root.openVm(detail.vm.name)
        }
        Button {
          visible: !detail.running
          focusable: true
          text: "Boot once from ISO…"
          iconText: Icons.glyph("disc")
          bordered: true
          enabled: root.busy === ""
          onClicked: root.chooseIso("boot")
        }
        Button {
          visible: !detail.running
          focusable: true
          variant: "primary"
          text: "Start"
          iconText: Icons.glyph("media.play")
          busy: root.busy.indexOf("Starting") === 0
          enabled: root.busy === "" || busy
          onClicked: root.startAndOpen(detail.vm.name)
        }
      }

      Messages {}

      // Live figures from the QEMU process.
      Card {
        visible: detail.vm.state === "running"
        title: "Now"
        KeyValueGrid {
          Layout.fillWidth: true
          rows: [
            { label: "CPU", value: root.cpuPercent[detail.vm.name] !== undefined
              ? root.cpuPercent[detail.vm.name] + "% of " + detail.vm.cpus + (detail.vm.cpus === 1 ? " CPU" : " CPUs") : "…" },
            { label: "Memory in use", value: Model.formatBytes(detail.vm.mem_used) + " of " + Model.ramLabel(detail.vm.ram) },
            { label: "Disk", value: Model.formatBytes(detail.vm.disk_used) + " used of " + Model.formatBytes(detail.vm.disk_size) },
            { label: "Process", value: "QEMU, PID " + detail.vm.pid }
          ]
        }
      }

      Card {
        title: "Settings"
        subtitle: detail.running ? "Shut the VM down to change these." : ""

        GridLayout {
          Layout.fillWidth: true
          columns: 2
          columnSpacing: Style.spacing.xxl
          rowSpacing: Style.spacing.md
          enabled: detail.editable

          FormLabel { text: "System" }
          ButtonGroup {
            options: [{ value: "linux", label: "Linux" }, { value: "windows", label: "Windows" }]
            value: detail.vm.os
            onChanged: function(value) { root.setKey("os", value) }
          }

          FormLabel { text: "CPUs" }
          NumberField {
            from: 1
            to: 64
            value: detail.vm.cpus
            onModified: function(value) { cpuSave.value = value; cpuSave.restart() }
            Timer { id: cpuSave; property int value: 0; interval: 600; onTriggered: root.setKey("cpus", value) }
          }

          FormLabel { text: "Memory" }
          Dropdown {
            Layout.preferredWidth: Style.space(160)
            showLabel: false
            value: detail.vm.ram
            options: ramOptions(detail.vm.ram)
            onChanged: function(value) { root.setKey("ram", value) }
          }

          FormLabel { text: "Disk size" }
          RowLayout {
            spacing: Style.spacing.lg
            Value { text: Model.formatBytes(detail.vm.disk_size) }
            TextField {
              id: growField
              Layout.preferredWidth: Style.space(110)
              placeholderText: "e.g. 128G"
              onAccepted: if (growButton.enabled) growButton.clicked()
            }
            Button {
              id: growButton
              focusable: true
              text: "Grow"
              bordered: true
              enabled: Model.validSize(growField.text.trim())
              onClicked: root.setKey("disk_size", growField.text.trim())
            }
          }

          FormLabel { text: "Installer ISO" }
          IsoPicker {
            path: detail.vm.iso
            onBrowse: root.chooseIso("set")
            onClear: root.setKey("iso", "")
          }

          FormLabel { text: "Graphics" }
          ButtonGroup {
            options: [{ value: "virtio", label: "Virtio" }, { value: "qxl", label: "QXL" }, { value: "std", label: "Standard VGA" }]
            value: detail.vm.display
            onChanged: function(value) { root.setKey("display", value) }
          }

          FormLabel { text: "Disk bus" }
          ButtonGroup {
            options: [{ value: "virtio", label: "Virtio" }, { value: "sata", label: "SATA" }]
            value: detail.vm.disk_bus
            onChanged: function(value) { root.setKey("disk_bus", value) }
          }

          FormLabel { text: "Network card" }
          ButtonGroup {
            options: [{ value: "virtio", label: "Virtio" }, { value: "e1000e", label: "Intel e1000e" }]
            value: detail.vm.nic
            onChanged: function(value) { root.setKey("nic", value) }
          }

          FormLabel { text: "Sound" }
          ButtonGroup {
            options: [{ value: "spice", label: "In the viewer" }, { value: "pipewire", label: "Always" }, { value: "none", label: "Off" }]
            value: detail.vm.audio
            onChanged: function(value) { root.setKey("audio", value) }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.md
          enabled: detail.editable

          Toggle {
            Layout.fillWidth: true
            label: "Network"
            description: "Internet through the host (QEMU user networking)."
            checked: detail.vm.net === "user"
            onClicked: root.setKey("net", checked ? "none" : "user")
          }
          Toggle {
            Layout.fillWidth: true
            label: "UEFI firmware"
            description: "Off boots with a legacy BIOS."
            checked: detail.vm.uefi === "yes"
            onClicked: root.setKey("uefi", checked ? "no" : "yes")
          }
          Toggle {
            Layout.fillWidth: true
            label: "Secure Boot firmware"
            description: "Firmware that can enforce Secure Boot; it starts with no keys enrolled."
            checked: detail.vm.secureboot === "yes"
            onClicked: root.setKey("secureboot", checked ? "no" : "yes")
          }
          Toggle {
            Layout.fillWidth: true
            label: "TPM 2.0"
            description: "A software TPM (swtpm), as Windows 11 needs."
            checked: detail.vm.tpm === "yes"
            onClicked: root.setKey("tpm", checked ? "no" : "yes")
          }
        }
      }

      Card {
        title: "Snapshots"
        subtitle: detail.running ? "Shut the VM down to take or restore a snapshot."
          : root.snapshots.length === 0 ? "A snapshot saves the disk, firmware settings and TPM as they are now." : ""

        Repeater {
          model: root.snapshots
          delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Style.spacing.lg

            Text {
              text: Icons.glyph("snapshot")
              color: Commons.Color.textSecondary
              font.family: Icons.family
              font.pixelSize: Style.font.icon
            }
            Value { text: modelData.name; Layout.fillWidth: true }
            Text {
              text: Model.formatDate(modelData.date)
              color: Commons.Color.textSecondary
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.features: { "tnum": 1 }
            }
            Button {
              focusable: true
              text: "Restore…"
              bordered: true
              enabled: detail.editable
              onClicked: root.ask("Restore " + detail.vm.name + " to “" + modelData.name + "”? Changes since then are lost.", "Restore", function() {
                root.run(["snapshot", "restore", detail.vm.name, modelData.name], "Restoring…")
              })
            }
            PanelActionButton {
              focusable: true
              iconText: Icons.glyph("ui.delete")
              tooltipText: "Delete snapshot"
              hoverColor: Commons.Color.status.error
              enabled: detail.editable
              onClicked: root.ask("Delete snapshot “" + modelData.name + "”?", "Delete", function() {
                root.run(["snapshot", "delete", detail.vm.name, modelData.name], "Deleting snapshot…")
              })
            }
          }
        }

        RowLayout {
          spacing: Style.spacing.lg
          enabled: detail.editable
          TextField {
            id: snapName
            Layout.preferredWidth: Style.space(200)
            placeholderText: "Snapshot name"
            onAccepted: takeSnap.clicked()
          }
          Button {
            id: takeSnap
            focusable: true
            text: "Take snapshot"
            iconText: Icons.glyph("snapshot")
            bordered: true
            enabled: Model.validName(snapName.text.trim())
            onClicked: {
              var snap = snapName.text.trim()
              if (!Model.validName(snap)) return
              snapName.text = ""
              root.run(["snapshot", "create", detail.vm.name, snap], "Saving snapshot…")
            }
          }
        }
      }

      // Apart at the bottom: what can't be undone, each asked about first.
      SectionHeader { text: "Can't be undone" }

      Card {
        DangerRow {
          visible: detail.running
          title: "Force off"
          description: "Like pulling the plug: anything unsaved in the VM is lost. Use it when it won't shut down."
          actionText: "Force off…"
          onTriggered: root.ask("Force " + detail.vm.name + " off? Like pulling the plug: anything unsaved in it is lost.", "Force off", function() {
            root.run(["kill", detail.vm.name], "Forcing off…")
          })
        }
        DangerRow {
          title: "Delete this VM"
          description: "Deletes " + detail.vm.path + ": the disk, its snapshots and the firmware settings." + (detail.running ? " Shut it down first." : "")
          actionText: "Delete VM…"
          actionEnabled: detail.editable
          onTriggered: root.ask("Delete " + detail.vm.name + " and its disk? This can't be undone.", "Delete", function() {
            root.run(["delete", detail.vm.name, "--yes"], "Deleting…")
          })
        }
      }

      Item { Layout.preferredHeight: Style.spacing.lg }
    }
  }

  // Memory choices, keeping a custom value from vm.conf in the list.
  function ramOptions(value) {
    var sizes = ["1G", "2G", "4G", "6G", "8G", "12G", "16G", "24G", "32G"]
    if (value && sizes.indexOf(value) === -1) sizes.unshift(value)
    return sizes.map(function(s) { return { value: s, label: Model.ramLabel(s) } })
  }

  // ---------- Small parts ----------

  // The last command's error, or its message once it worked.
  component Messages: ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.spacing.md
    visible: root.error !== "" || root.notice !== ""
    InlineMessage {
      kind: "error"
      details: root.error
      dismissible: true
      onDismissed: root.error = ""
    }
    InlineMessage {
      kind: "info"
      text: root.error === "" ? root.notice : ""
      dismissible: true
      onDismissed: root.notice = ""
    }
  }

  component Body: Text {
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  component FormLabel: Text {
    Layout.preferredWidth: Style.space(140)
    Layout.alignment: Qt.AlignVCenter
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  component Value: Text {
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.features: { "tnum": 1 }
    elide: Text.ElideMiddle
  }

  // A caps label after a separator, as Settings and the bar panels do it.
  component SectionHeader: ColumnLayout {
    property alias text: header.text
    Layout.fillWidth: true
    Layout.topMargin: Style.spacing.lg
    spacing: Style.spacing.lg
    PanelSeparator { Layout.fillWidth: true }
    PanelSectionHeader { id: header }
  }

  // One destructive action with what it does, in the "Can't be undone" card.
  component DangerRow: RowLayout {
    id: danger
    property string title: ""
    property string description: ""
    property string actionText: ""
    property bool actionEnabled: true
    signal triggered()
    Layout.fillWidth: true
    spacing: Style.spacing.xxl
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.xxs
      Text {
        Layout.fillWidth: true
        text: danger.title
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Body { text: danger.description }
    }
    Button {
      focusable: true
      variant: "destructive"
      text: danger.actionText
      enabled: danger.actionEnabled
      onClicked: danger.triggered()
    }
  }

  component IsoPicker: RowLayout {
    id: picker
    property string path: ""
    signal browse()
    signal clear()
    Layout.fillWidth: true
    spacing: Style.spacing.lg
    Value {
      Layout.fillWidth: true
      text: picker.path !== "" ? Model.baseName(picker.path) : "None"
      color: picker.path !== "" ? Commons.Color.foreground : Commons.Color.textSecondary
    }
    Button {
      focusable: true
      text: "Choose…"
      bordered: true
      onClicked: picker.browse()
    }
    Button {
      visible: picker.path !== ""
      focusable: true
      text: "Eject"
      bordered: true
      onClicked: picker.clear()
    }
  }
}
