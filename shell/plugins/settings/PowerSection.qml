import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Power: what the computer does when left alone, when the lid
// closes and when the power button is pressed, when sleep turns into
// hibernation, and the battery warnings, through karchy-settings-power.
//
// The page shows what this machine has: a desktop gets one column of idle
// times and no lid or battery rows, a laptop gets "On battery" beside
// "Plugged in", and hibernation appears only where it works. Every control
// shows the value in effect, read back after each change, and each group
// says in a sentence what that adds up to.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  // The Settings window, for its confirm dialog (set by its Loader).
  property var settings: null
  property var values: ({})
  property var saved: ({})
  property var foreign: []
  property var batteryAction: ({})
  property string profile: ""
  property bool battery: false
  property bool lid: false
  property bool hibernation: false
  property bool ready: false
  // Why the last change didn't (fully) take, shown under the group it was in:
  // "idle", "lid", "powerKey", "hibernateAfter", "battery", or "" for the page.
  property string error: ""
  property string errorGroup: ""
  property string runningGroup: ""
  // Changes waiting for the one being applied.
  property var queue: []

  // After every status read, so a choice that didn't take snaps back.
  signal loaded()

  readonly property bool onBattery: UPower.onBattery
  // A battery that appears or goes (a dock, the kernel's test battery).
  readonly property bool systemBattery: !!UPower.displayDevice && UPower.displayDevice.isLaptopBattery
  onSystemBatteryChanged: refresh()

  // On opening the page and when the machine changes. What went wrong with
  // an earlier change is no longer news by then.
  function refresh() {
    if (setProc.running) return
    root.error = ""
    statusProc.running = true
  }

  function load(text) {
    try {
      var status = JSON.parse(text)
      root.values = status.values || {}
      root.saved = status.saved || {}
      root.foreign = status.foreign || []
      root.batteryAction = status.batteryAction || {}
      root.profile = String(status.profile || "")
      root.battery = status.battery === true
      root.lid = status.lid === true
      root.hibernation = status.hibernation === true
      root.ready = true
    } catch (e) {}
    root.loaded()
  }

  function run(args) {
    if (setProc.running) { root.queue = root.queue.concat([args]); return }
    root.error = ""
    root.runningGroup = root.groupOf(args[1] || "")
    setProc.command = ["karchy-settings-power"].concat(args)
    setProc.running = true
  }

  // The dropdowns hold "0" for never; the command calls it by name.
  function set(setting, value) {
    var timed = setting.indexOf("screenOff.") === 0 || setting.indexOf("lock.") === 0
      || setting.indexOf("sleep.") === 0 || setting === "hibernateAfter"
    root.run(["set", setting, timed && String(value) === "0" ? "never" : String(value)])
  }

  function groupOf(setting) {
    var name = String(setting).split(".")[0]
    return name === "screenOff" || name === "lock" || name === "sleep" ? "idle" : name
  }

  function isForeign(setting) { return root.foreign.indexOf(setting) !== -1 }

  function plural(n, unit) { return n + " " + unit + (n === 1 ? "" : "s") }

  // "5 minutes", "1 hour 30 minutes", "45 seconds".
  function duration(seconds) {
    seconds = Number(seconds)
    if (seconds < 60 || (seconds < 600 && seconds % 60 !== 0)) return plural(seconds, "second")
    var minutes = Math.round(seconds / 60)
    if (minutes < 60) return plural(minutes, "minute")
    var hours = Math.floor(minutes / 60)
    return plural(hours, "hour") + (minutes % 60 ? " " + plural(minutes % 60, "minute") : "")
  }

  function timeChoices(minutes) {
    var out = []
    for (var i = 0; i < minutes.length; i++) out.push({ value: String(minutes[i] * 60), label: root.duration(minutes[i] * 60) })
    out.push({ value: "0", label: "Never" })
    return out
  }

  function timeName(seconds) { return Number(seconds) === 0 ? "Never" : root.duration(seconds) }

  readonly property var screenChoices: timeChoices([1, 2, 5, 10, 15, 30, 60])
  readonly property var sleepChoices: timeChoices([5, 10, 15, 30, 45, 60, 120])

  // What the three idle times add up to on one power source ("battery" or
  // "ac"). The lock screen turns the screen off itself, 5 seconds after it
  // appears, so a later (or no) screen-off time is the lock's; and nothing
  // happens after the computer is asleep.
  function idleSummary(source) {
    var off = Number(root.values["screenOff." + source] || 0)
    var lock = Number(root.values["lock." + source] || 0)
    var sleep = Number(root.values["sleep." + source] || 0)
    var asleep = function(t) { return sleep > 0 && t >= sleep }
    var steps = []
    if (lock > 0 && !asleep(lock)) {
      if (off > 0 && off < lock) steps.push("turns the screen off after " + duration(off))
      steps.push((off > 0 && off < lock ? "locks after " : "locks and turns the screen off after ") + duration(lock))
    } else if (off > 0 && !asleep(off)) {
      steps.push("turns the screen off after " + duration(off) + (lock > 0 ? "" : ", without locking"))
    }
    if (sleep > 0) steps.push("sleeps after " + duration(sleep))

    var text = steps.length === 0 ? "stays on, unlocked, with the screen lit"
      : steps.length === 1 ? steps[0]
      : steps.slice(0, -1).join(", ") + ", then " + steps[steps.length - 1]
    return text + (sleep === 0 ? ". Never goes to sleep on its own." : ".")
  }

  // Whether the three times don't simply do what each says: one never comes
  // (the computer is asleep first, or the lock has already turned the screen
  // off), the screen goes off without locking, or nothing happens at all.
  // Only then is the summary worth its line.
  function idleNeedsSaying(source) {
    var off = Number(root.values["screenOff." + source] || 0)
    var lock = Number(root.values["lock." + source] || 0)
    var sleep = Number(root.values["sleep." + source] || 0)
    if (off === 0 && lock === 0 && sleep === 0) return true
    if (sleep > 0 && ((off > 0 && off >= sleep) || (lock > 0 && lock >= sleep))) return true
    if (lock > 0 && off > lock) return true
    return off > 0 && lock === 0
  }

  function capitalized(text) { return text.charAt(0).toUpperCase() + text.slice(1) }

  readonly property var lidChoices: {
    var out = [{ value: "sleep", label: "Sleep" }, { value: "ignore", label: "Lock and stay on" }]
    if (root.hibernation) out.push({ value: "hibernate", label: "Hibernate" })
    out.push({ value: "poweroff", label: "Shut down" })
    return out
  }

  readonly property var dockedChoices: {
    var out = [{ value: "ignore", label: "Keep running on that display" }, { value: "sleep", label: "Sleep" }]
    if (root.hibernation) out.push({ value: "hibernate", label: "Hibernate" })
    out.push({ value: "poweroff", label: "Shut down" })
    return out
  }

  readonly property var powerKeyChoices: {
    var out = [{ value: "menu", label: "Open the power menu" }, { value: "sleep", label: "Sleep" }]
    if (root.hibernation) out.push({ value: "hibernate", label: "Hibernate" })
    out.push({ value: "shutdown", label: "Shut down" })
    out.push({ value: "nothing", label: "Do nothing" })
    return out
  }

  // logind's own names for the actions the page doesn't offer.
  function actionName(action) {
    var names = { lock: "Lock", reboot: "Restart", halt: "Halt", kexec: "Restart (kexec)", hibernate: "Hibernate",
                  custom: "Set in your Hyprland config" }
    return names[action] || String(action)
  }

  function percentChoices(levels, keep) {
    var out = []
    for (var i = 0; i < levels.length; i++)
      if (keep(levels[i])) out.push({ value: String(levels[i]), label: levels[i] + "%" })
    return out
  }

  readonly property string lastResort: {
    var percent = Number(root.batteryAction.percent || 0)
    var action = String(root.batteryAction.action || "")
    if (percent <= 0) return ""
    // UPower powers off where it is told to hibernate and the machine can't.
    var does = action === "hibernate" ? (root.hibernation ? "hibernates, so nothing open is lost" : "shuts down")
      : action === "poweroff" ? "shuts down"
      : action === "hybridsleep" ? "sleeps, with the session also saved to disk"
      : "sleeps or shuts down, whichever it can"
    return "At " + percent + "% it " + does + "."
  }

  readonly property string profileName: {
    var names = { "power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance" }
    return names[root.profile] || root.profile
  }

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: ["karchy-settings-power", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }

  // A change prints the new status, and on stderr why it didn't (fully) take.
  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") root.load(text) }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.errorGroup = root.runningGroup
        root.error = text.trim()
      }
    }
    onExited: function(exitCode) {
      if (root.queue.length > 0) {
        var next = root.queue[0]
        root.queue = root.queue.slice(1)
        root.run(next)
      } else if (exitCode !== 0) {
        statusProc.running = true
      }
    }
  }

  // The line under a group that says what its choices add up to.
  component Outcome: Text {
    Layout.fillWidth: true
    Layout.maximumWidth: Style.space(620)
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    lineHeight: 1.15
  }

  // What went wrong with a change, under the group it was made in, so it is
  // in view wherever the page is scrolled to.
  component GroupError: InlineMessage {
    property string group: ""
    kind: "error"
    text: root.errorGroup === group ? root.error : ""
    dismissible: true
    onDismissed: root.error = ""
  }

  // "On battery" and "Plugged in" over the two columns; the one in use now
  // is marked.
  component SourceHeading: Text {
    property bool now: false
    property string name: ""
    Layout.fillWidth: true
    textFormat: Text.PlainText
    text: name + (now ? " (now)" : "")
    color: now ? Commons.Color.foreground : Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.bold: true
    elide: Text.ElideRight
  }

  PageHeader {
    title: "Power"
    explanation: "Idle times and battery warnings you edit by hand in ~/.config/karchy/shell.json take priority over these. Lid and hibernation are system settings, changed without a password at this computer."
  }

  GroupError { group: "" }

  SettingsHeader { text: "When left alone" }

  GridLayout {
    Layout.fillWidth: true
    columns: root.battery ? 3 : 2
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    Item { visible: root.battery; implicitWidth: 1; implicitHeight: 1 }
    SourceHeading { visible: root.battery; name: "On battery"; now: root.onBattery }
    SourceHeading { visible: root.battery; name: "Plugged in"; now: !root.onBattery }

    SettingsLabel { text: "Turn off the screen" }
    PowerChoice { visible: root.battery; page: root; setting: "screenOff.battery"; choices: root.screenChoices; nameFor: root.timeName }
    PowerChoice { page: root; setting: "screenOff.ac"; choices: root.screenChoices; nameFor: root.timeName }

    SettingsLabel { text: "Lock" }
    PowerChoice { visible: root.battery; page: root; setting: "lock.battery"; choices: root.screenChoices; nameFor: root.timeName }
    PowerChoice { page: root; setting: "lock.ac"; choices: root.screenChoices; nameFor: root.timeName }

    SettingsLabel { text: "Sleep" }
    PowerChoice { visible: root.battery; page: root; setting: "sleep.battery"; choices: root.sleepChoices; nameFor: root.timeName }
    PowerChoice { page: root; setting: "sleep.ac"; choices: root.sleepChoices; nameFor: root.timeName }
  }

  GroupError { group: "idle" }

  // Said only when the times interact: one of them never comes.
  Outcome {
    visible: root.ready && (root.idleNeedsSaying("ac") || (root.battery && root.idleNeedsSaying("battery")))
    text: root.battery
      ? "On battery: " + root.idleSummary("battery") + "\nPlugged in: " + root.idleSummary("ac")
      : root.capitalized(root.idleSummary("ac"))
  }

  SettingsHeader { visible: root.lid; text: "Lid" }

  GridLayout {
    visible: root.lid
    Layout.fillWidth: true
    columns: root.battery ? 3 : 2
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    Item { visible: root.battery; implicitWidth: 1; implicitHeight: 1 }
    SourceHeading { visible: root.battery; name: "On battery"; now: root.onBattery }
    SourceHeading { visible: root.battery; name: "Plugged in"; now: !root.onBattery }

    SettingsLabel { text: "When the lid closes" }
    PowerChoice { visible: root.battery; page: root; setting: "lid.battery"; choices: root.lidChoices; nameFor: root.actionName }
    PowerChoice { page: root; setting: "lid.ac"; choices: root.lidChoices; nameFor: root.actionName }

    SettingsLabel { text: "External display" }
    PowerChoice {
      Layout.columnSpan: root.battery ? 2 : 1
      page: root
      setting: "lid.docked"
      choices: root.dockedChoices
      nameFor: root.actionName
    }
  }

  GroupError { group: "lid" }

  // Stays while the choice does: a consequence, not an explanation.
  InlineMessage {
    visible: root.lid && (root.values["lid.battery"] === "ignore" || root.values["lid.ac"] === "ignore")
    kind: "warning"
    text: "A closed laptop that stays on can overheat in a bag and drain the battery."
  }

  // Why a choice may do nothing; which file, for whoever goes looking.
  InlineMessage {
    visible: root.lid && (root.isForeign("lid.battery") || root.isForeign("lid.ac") || root.isForeign("lid.docked"))
    kind: "warning"
    text: "A system configuration file controls the lid, so these choices may have no effect."
    details: "A file in /etc/systemd/logind.conf.d that sorts after 60-karchy-settings.conf."
  }

  SettingsHeader { text: "Power button" }

  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    SettingsLabel { text: "Pressing it" }
    PowerChoice { page: root; setting: "powerKey"; choices: root.powerKeyChoices; nameFor: root.actionName }
  }

  GroupError { group: "powerKey" }

  InlineMessage {
    visible: root.error === "" && root.isForeign("powerKey") && root.values.powerKey === "custom"
    kind: "warning"
    text: "Your own Hyprland binding for the power button overrides this setting."
    details: "A binding for XF86PowerOff in ~/.config/hypr."
  }

  SettingsHeader { visible: root.hibernation; text: "Hibernation" }

  GridLayout {
    visible: root.hibernation
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    SettingsLabel { text: "After sleeping for" }
    PowerChoice {
      page: root
      setting: "hibernateAfter"
      choices: [
        { value: "30", label: "30 minutes" }, { value: "60", label: "1 hour" }, { value: "120", label: "2 hours" },
        { value: "240", label: "4 hours" }, { value: "480", label: "8 hours" }, { value: "0", label: "Never" }
      ]
      nameFor: function(minutes) { return Number(minutes) < 0 ? "When the battery runs low" : root.timeName(Number(minutes) * 60) }
    }
  }

  GroupError { group: "hibernateAfter" }

  InlineMessage {
    visible: root.hibernation && root.ready && root.isForeign("hibernateAfter")
    kind: "warning"
    text: "A system configuration file controls hibernation, so this choice may have no effect."
    details: "A file in /etc/systemd/sleep.conf.d that sorts after 60-karchy-settings.conf."
  }

  // What the choice costs, or what happens with none made.
  Outcome {
    visible: root.hibernation && root.ready && !root.isForeign("hibernateAfter") && Number(root.values.hibernateAfter) <= 0
    text: Number(root.values.hibernateAfter) === 0
      ? "Sleep still uses power: a battery runs down over days."
      : "Hibernates when the battery is nearly empty."
  }

  SettingsHeader { visible: root.battery; text: "Battery" }

  GridLayout {
    visible: root.battery
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    SettingsLabel { text: "Warn at" }
    PowerChoice {
      page: root
      setting: "battery.low"
      choices: root.percentChoices([10, 15, 20, 25, 30], function(level) { return level > Number(root.values["battery.critical"] || 0) })
      nameFor: function(level) { return Number(level) === 0 ? "No warning" : level + "%" }
    }

    SettingsLabel { text: "Warn again at" }
    PowerChoice {
      page: root
      setting: "battery.critical"
      choices: root.percentChoices([5, 7, 10], function(level) {
        return Number(root.values["battery.low"] || 0) === 0 || level < Number(root.values["battery.low"]) })
      nameFor: function(level) { return Number(level) === 0 ? "No warning" : level + "%" }
    }
  }

  GroupError { group: "battery" }

  Outcome {
    visible: root.battery && root.lastResort !== ""
    text: root.lastResort
  }

  SettingsHeader { visible: root.profile !== ""; text: "Power mode" }

  Outcome {
    visible: root.profile !== ""
    color: Commons.Color.foreground
    text: root.profileName + ". Change it from the battery in the bar."
  }

  Button {
    focusable: true
    visible: Object.keys(root.saved).length > 0
    Layout.topMargin: Style.spacing.lg
    text: "Back to karchy's defaults"
    bordered: true
    // Drops every power choice saved here, so it asks first.
    onClicked: if (root.settings) root.settings.ask("Go back to karchy's defaults? Every idle time, lid, power button, hibernation and battery choice made here is forgotten.",
      "Back to defaults", function() { root.run(["reset"]) })
  }
}
