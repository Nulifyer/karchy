import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Power: the power mode, the screen and sleep times, the lid and
// the power button, on battery and plugged in; and the battery levels,
// through karchy-settings-power.
//
// The words and the grouping are the ones people know from Windows Settings ›
// System › Power & battery (D-177): "Power mode", "Screen and sleep" with
// "Turn my screen off after" and "Make my device sleep after", the lid and
// the power button together, "Critical battery level" and "Critical battery
// action"; macOS, GNOME and KDE for what Windows has no row for (the
// screensaver, dimming, a brightness for each power source). A new row takes
// its name from there first.
//
// Everything that can differ by power source is one table: a row a setting,
// "On battery" beside "Plugged in". The page shows what this machine has: a
// desktop gets one column and no lid, brightness, dimming or battery rows,
// the power mode appears where power-profiles-daemon runs, and hibernation
// only where it works. Every control shows the value in effect, read back
// after each change. A line under a group is said only for what its rows
// don't show: a time that never comes, work that would be lost. The
// screensaver's time is the one value that follows the others when it isn't
// chosen: Never on a power source where the screen never turns off, the
// session never locks and the computer never sleeps (D-176).
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  // The Settings window, for its confirm dialog (set by its Loader).
  property var settings: null
  // Labels beside their controls where the page has room, above them where
  // it is narrow (the window is a tile).
  readonly property bool wide: width >= Style.spacing.formWide
  property var values: ({})
  property var saved: ({})
  property var foreign: []
  // The power profile running now, and the ones this machine has.
  property string profile: ""
  property var profiles: []
  property bool battery: false
  // A built-in screen whose brightness can be set.
  property bool backlight: false
  property bool lid: false
  property bool hibernation: false
  property bool ready: false
  // Why the last change didn't (fully) take, shown under the group it was in:
  // "mode", "idle", "buttons", "battery", or "" for the page.
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

  // The shell's battery service follows power-profiles-daemon's signals, so
  // the profile running now is live where there is one (a laptop); elsewhere
  // it is the one read with the status. A change may be a profile picked in
  // the bar's panel, which is this page's setting too, so the page reads again.
  readonly property var batteryService: root.settings && root.settings.shell
    ? root.settings.shell.serviceFor("karchy.battery") : null
  readonly property string liveProfile: batteryService ? String(batteryService.activePowerProfile || "") : ""
  onLiveProfileChanged: refresh()
  readonly property string runningProfile: liveProfile !== "" ? liveProfile : profile
  readonly property string sourceNow: root.battery && root.onBattery ? "battery" : "ac"

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
      root.profile = String(status.profile || "")
      root.profiles = status.profiles || []
      root.battery = status.battery === true
      root.backlight = status.backlight === true
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

  // The dropdowns hold "0" for never and for a brightness left as it is; the
  // command calls those by name.
  function set(setting, value) {
    var timed = setting.indexOf("screensaver.") === 0 || setting.indexOf("screenOff.") === 0 || setting.indexOf("lock.") === 0
      || setting.indexOf("sleep.") === 0 || setting.indexOf("dim.") === 0 || setting === "hibernateAfter"
    var zero = timed ? "never" : setting.indexOf("brightness.") === 0 ? "keep" : "0"
    root.run(["set", setting, String(value) === "0" ? zero : String(value)])
  }

  function groupOf(setting) {
    var name = String(setting).split(".")[0]
    if (name === "profile" || name === "brightness") return "mode"
    if (name === "lid" || name === "powerKey") return "buttons"
    if (name === "criticalBattery") return "battery"
    if (name === "screensaver" || name === "screenOff" || name === "dim" || name === "lock" || name === "sleep"
        || name === "hibernateAfter" || name === "hibernate") return "idle"
    return name
  }

  function isForeign(setting) { return root.foreign.indexOf(setting) !== -1 }

  function plural(n, unit) { return n + " " + unit + (n === 1 ? "" : "s") }

  // "5 minutes", "2.5 minutes", "1 hour 30 minutes", "45 seconds".
  function duration(seconds) {
    seconds = Number(seconds)
    if (seconds > 60 && seconds < 600 && seconds % 60 === 30) return (seconds / 60) + " minutes"
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

  function profileName(profile) {
    var names = { "power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance" }
    return names[profile] || String(profile)
  }

  readonly property var profileChoices: {
    var out = []
    for (var i = 0; i < root.profiles.length; i++) out.push({ value: root.profiles[i], label: root.profileName(root.profiles[i]) })
    return out
  }

  // Said only while it is so: another profile runs than the one chosen for
  // this power source.
  readonly property string profileNote: {
    var chosen = String(root.values["profile." + root.sourceNow] || "")
    if (!root.ready || chosen === "" || root.runningProfile === "" || root.runningProfile === chosen) return ""
    return root.profileName(root.runningProfile) + " is on now: a low battery or an app can hold another power mode for a while."
  }

  function brightnessName(percent) { return Number(percent) === 0 ? "Don't change" : percent + "%" }

  readonly property var brightnessChoices: {
    var out = []
    for (var percent = 10; percent <= 100; percent += 10) out.push({ value: String(percent), label: percent + "%" })
    out.push({ value: "0", label: root.brightnessName(0) })
    return out
  }

  // How long before the screen turns off the built-in screen is dimmed.
  function dimName(seconds) { return Number(seconds) === 0 ? "Never" : root.duration(seconds) + " before" }

  readonly property var dimChoices: {
    var out = []
    var seconds = [10, 30, 60, 120]
    for (var i = 0; i < seconds.length; i++) out.push({ value: String(seconds[i]), label: root.dimName(seconds[i]) })
    out.push({ value: "0", label: "Never" })
    return out
  }

  // Whether the screen ever turns off by itself on a power source: at the
  // screen-off time, or the lock's where that comes first, or when the
  // computer sleeps. With the screen-off time at Never the lock stays lit.
  function screenTurnsOff(source) {
    return Number(root.values["screenOff." + source] || 0) > 0 || Number(root.values["sleep." + source] || 0) > 0
  }

  readonly property var screenChoices: timeChoices([1, 2, 5, 10, 15, 30, 60])
  // karchy's own time is 2.5 minutes, half way to its screen-off time.
  readonly property var screensaverChoices: timeChoices([1, 2.5, 5, 10, 15, 30])
  readonly property var sleepChoices: timeChoices([5, 10, 15, 30, 45, 60, 120])

  // What the times of one power source ("battery" or "ac") do that their
  // rows don't show, as sentences; none when each time simply comes.
  // - The screensaver starts only before the screen-off time and sleep:
  //   there is nothing to draw on a dark screen. The lock comes under it
  //   (D-184), so a lock before it stops nothing.
  // - Where there is no screensaver, the lock screen turns the screen off
  //   itself, 5 seconds after it appears, so a screen-off time after the
  //   lock's never comes. With one, the lock screen shows it until then.
  // A time at or after sleep's never comes either, and the rows say so by
  // themselves: the computer is asleep.
  function idleNotes(source) {
    var saver = Number(root.values["screensaver." + source] || 0)
    var off = Number(root.values["screenOff." + source] || 0)
    var lock = Number(root.values["lock." + source] || 0)
    var sleep = Number(root.values["sleep." + source] || 0)
    var notes = []
    var first = root.firstOf(off, 0, sleep)
    if (saver > 0 && first > 0 && saver >= first) {
      notes.push("the screensaver never starts: "
        + (first === sleep ? "the computer is asleep" : "the screen is off") + " by then")
    }
    if (!(saver > 0) && lock > 0 && off > lock && !(sleep > 0 && lock >= sleep))
      notes.push("the screen turns off when it locks, after " + duration(lock))
    return notes
  }

  // The soonest of the times that are set, 0 with none.
  function firstOf(off, lock, sleep) {
    var first = 0
    var times = [sleep, lock, off]
    for (var i = 0; i < times.length; i++)
      if (times[i] > 0 && (first === 0 || times[i] < first)) first = times[i]
    return first
  }

  // The notes of both power sources, a line each, named by its source on a
  // laptop.
  readonly property string idleNote: {
    if (!root.ready) return ""
    var lines = []
    var sources = root.battery ? [["battery", "On battery, "], ["ac", "Plugged in, "]] : [["ac", ""]]
    for (var i = 0; i < sources.length; i++) {
      var notes = root.idleNotes(sources[i][0])
      for (var j = 0; j < notes.length; j++)
        lines.push(sources[i][1] === "" ? root.capitalized(notes[j]) + "." : sources[i][1] + notes[j] + ".")
    }
    return lines.join("\n")
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

  // The battery warnings that are on, as the shell counts them: a second
  // warning at or above the first leaves only the second.
  readonly property int warnLow: {
    var low = Number(root.values["battery.low"] || 0), again = Number(root.values["battery.critical"] || 0)
    return again >= low ? 0 : low
  }
  readonly property int warnAgain: Number(root.values["battery.critical"] || 0)
  // The later of them, 0 with both off: the critical battery level stays under it.
  readonly property int lastWarning: warnAgain > 0 ? warnAgain : warnLow
  readonly property int criticalLevel: Number(root.values["criticalBattery.level"] || 0)

  // What a laptop left running on its battery does at the critical level.
  // Hibernation is offered only where it works; told to hibernate elsewhere,
  // UPower shuts down, and that is then the value shown.
  readonly property var criticalChoices: {
    var out = []
    if (root.hibernation) out.push({ value: "hibernate", label: "Hibernate" })
    out.push({ value: "poweroff", label: "Shut down" })
    return out
  }

  // UPower's own names for what the page doesn't offer (set in a file).
  function criticalName(action) {
    var names = { hibernate: "Hibernate", poweroff: "Shut down", hybridsleep: "Sleep, saved to disk too",
                  suspend: "Sleep", sleep: "Sleep", ignore: "Nothing" }
    return names[action] || String(action)
  }

  // What the critical battery action loses, where it loses something:
  // hibernation and a sleep saved to disk keep what is open.
  readonly property string criticalNote: {
    var action = String(root.values["criticalBattery.action"] || "")
    if (root.criticalLevel <= 0 || action === "" || action === "hibernate" || action === "hybridsleep") return ""
    return action === "poweroff" ? "Unsaved work is lost when it shuts down."
      : "Unsaved work is lost when the battery runs out."
  }

  function hibernateName(minutes) {
    return Number(minutes) < 0 ? "When the battery runs low" : root.timeName(Number(minutes) * 60)
  }

  readonly property var hibernateChoices: [
    { value: "30", label: "30 minutes" }, { value: "60", label: "1 hour" }, { value: "120", label: "2 hours" },
    { value: "240", label: "4 hours" }, { value: "480", label: "8 hours" }, { value: "0", label: "Never" }
  ]

  // Plugged in, a sleeping laptop hibernates after the same time or not at
  // all: the time then counts from when the charger is pulled.
  readonly property var hibernateAcChoices: [
    { value: "same", label: root.hibernateName(root.values.hibernateAfter) },
    { value: "never", label: Number(root.values.hibernateAfter) === 0 ? "Never" : "Not while plugged in" }
  ]

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

  // A line under a group for what its rows don't show.
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

  // A group's heading inside the table: a rule across it, then the group's
  // name with "On battery" and "Plugged in" over the two columns (a desktop
  // has one column and needs no names). The one in use now is marked.
  component GroupRule: PanelSeparator {
    Layout.columnSpan: table.columns
    Layout.fillWidth: true
    Layout.topMargin: Style.spacing.xxl + Style.spacing.lg - table.rowSpacing
    Layout.bottomMargin: Style.spacing.lg - table.rowSpacing
  }

  component GroupName: PanelSectionHeader {
    Layout.columnSpan: root.wide ? 1 : table.columns
    Layout.alignment: Qt.AlignVCenter
    Layout.bottomMargin: Style.spacing.xxl - table.rowSpacing
  }

  component SourceHeading: PanelSectionHeader {
    property bool now: false
    property string name: ""
    visible: root.battery
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignVCenter
    Layout.bottomMargin: Style.spacing.xxl - table.rowSpacing
    text: name + (now ? " (now)" : "")
    color: now ? Commons.Color.foreground : Commons.Color.secondaryText(foreground, surface)
    elide: Text.ElideRight
  }

  // A setting's name in the table: the first column, or on a narrow page a
  // line across the table above the setting's choices.
  component RowLabel: SettingsLabel {
    Layout.columnSpan: root.wide ? 1 : table.columns
    Layout.fillWidth: !root.wide
  }

  // The second cell of a group's heading on a desktop (a narrow page has no
  // second cell).
  component NoHeading: Item {
    visible: !root.battery && root.wide
    implicitWidth: 1
    implicitHeight: 1
  }

  // A line that belongs to a group in the table.
  component TableOutcome: Outcome { Layout.columnSpan: table.columns }
  component TableError: GroupError { Layout.columnSpan: table.columns; Layout.fillWidth: true }
  component TableWarning: InlineMessage { Layout.columnSpan: table.columns; Layout.fillWidth: true; kind: "warning" }

  PageHeader {
    title: "Power"
    explanation: "Power mode is the same setting as in the bar's battery panel. Screen brightness is set once, when you plug in or unplug; the brightness keys work as usual afterwards. Hibernation counts from when the computer goes to sleep. What you set by hand in shell.json wins over the brightness, the times and the battery warnings here. Lid, hibernation and critical battery are system settings, changed without a password at this computer."
    ConfigFileLink { closes: root.settings; file: ".config/karchy/shell.json" }
  }

  GroupError { group: "" }

  // Everything that has a value for each power source: a row a setting, a
  // column a source. Hidden rows leave no gap, so a desktop reads as a plain
  // list with one column.
  GridLayout {
    id: table
    Layout.fillWidth: true
    // A narrow page has no label column: each setting's name is a line of
    // its own above its choices, which keep their two columns on a laptop.
    columns: root.wide ? (root.battery ? 3 : 2) : (root.battery ? 2 : 1)
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    readonly property bool modeGroup: root.profiles.length > 0 || (root.battery && root.backlight)
    // Both columns of a laptop, for a setting with one value.
    readonly property int bothSources: root.wide ? (root.battery ? 2 : 1) : table.columns

    // ---------- Power mode, and the brightness that goes with a source ----------
    // The first group has no name of its own: its first row is "Power
    // mode", as the group is called in Windows and GNOME. Only the two
    // sources are named, where there are two.
    GroupRule { visible: table.modeGroup; Layout.topMargin: Style.spacing.lg }
    Item { visible: table.modeGroup && root.battery && root.wide; implicitWidth: 1; implicitHeight: 1 }
    SourceHeading { visible: table.modeGroup && root.battery; name: "On battery"; now: root.onBattery }
    SourceHeading { visible: table.modeGroup && root.battery; name: "Plugged in"; now: !root.onBattery }

    RowLabel { visible: root.profiles.length > 0; text: "Power mode" }
    PowerChoice { visible: root.profiles.length > 0 && root.battery; page: root; setting: "profile.battery"; choices: root.profileChoices; nameFor: root.profileName }
    PowerChoice { visible: root.profiles.length > 0; page: root; setting: "profile.ac"; choices: root.profileChoices; nameFor: root.profileName }

    // Set once, when the charger goes in or out; the brightness keys work as
    // before afterwards.
    RowLabel { visible: root.battery && root.backlight; text: "Screen brightness" }
    PowerChoice { visible: root.battery && root.backlight; page: root; setting: "brightness.battery"; choices: root.brightnessChoices; nameFor: root.brightnessName }
    PowerChoice { visible: root.battery && root.backlight; page: root; setting: "brightness.ac"; choices: root.brightnessChoices; nameFor: root.brightnessName }

    TableError { group: "mode" }

    TableOutcome {
      visible: root.profiles.length > 0 && root.profileNote !== ""
      text: root.profileNote
    }

    // ---------- Screen and sleep: screensaver, screen, lock, sleep, hibernation ----------
    GroupRule { Layout.topMargin: table.modeGroup ? Style.spacing.xxl + Style.spacing.lg - table.rowSpacing : Style.spacing.lg }
    GroupName { text: "Screen and sleep" }
    SourceHeading { name: "On battery"; now: root.onBattery }
    SourceHeading { name: "Plugged in"; now: !root.onBattery }
    NoHeading {}

    // First in the list as it is first in time. Where it isn't chosen it
    // follows the rows under it: Never where all three of them are.
    RowLabel { text: "Start the screensaver after" }
    PowerChoice { visible: root.battery; page: root; setting: "screensaver.battery"; choices: root.screensaverChoices; nameFor: root.timeName }
    PowerChoice { page: root; setting: "screensaver.ac"; choices: root.screensaverChoices; nameFor: root.timeName }

    RowLabel { text: "Turn my screen off after" }
    PowerChoice { visible: root.battery; page: root; setting: "screenOff.battery"; choices: root.screenChoices; nameFor: root.timeName }
    PowerChoice { page: root; setting: "screenOff.ac"; choices: root.screenChoices; nameFor: root.timeName }

    // The built-in screen only, and only where it ever turns off by itself.
    RowLabel { visible: root.backlight; text: "Dim my screen" }
    PowerChoice {
      visible: root.backlight && root.battery
      enabled: current !== "" && root.screenTurnsOff("battery")
      page: root; setting: "dim.battery"; choices: root.dimChoices; nameFor: root.dimName
    }
    PowerChoice {
      visible: root.backlight
      enabled: current !== "" && root.screenTurnsOff("ac")
      page: root; setting: "dim.ac"; choices: root.dimChoices; nameFor: root.dimName
    }

    RowLabel { text: "Lock my screen after" }
    PowerChoice { visible: root.battery; page: root; setting: "lock.battery"; choices: root.screenChoices; nameFor: root.timeName }
    PowerChoice { page: root; setting: "lock.ac"; choices: root.screenChoices; nameFor: root.timeName }

    RowLabel { text: "Make my device sleep after" }
    PowerChoice { visible: root.battery; page: root; setting: "sleep.battery"; choices: root.sleepChoices; nameFor: root.timeName }
    PowerChoice { page: root; setting: "sleep.ac"; choices: root.sleepChoices; nameFor: root.timeName }

    // After any sleep: idle, the lid, the power button or the menu. A
    // desktop has the one time; a laptop also says whether it counts while
    // plugged in. "Then": the time counts from when sleep begins, where
    // Windows' "hibernate after" counts from when the device was last used.
    RowLabel { visible: root.hibernation; text: "Then hibernate after" }
    PowerChoice { visible: root.hibernation; page: root; setting: "hibernateAfter"; choices: root.hibernateChoices; nameFor: root.hibernateName }
    PowerChoice {
      visible: root.hibernation && root.battery
      enabled: current !== "" && Number(root.values.hibernateAfter) !== 0
      page: root
      setting: "hibernate.ac"
      choices: root.hibernateAcChoices
    }

    TableError { group: "idle" }

    // A time that never comes, though its row shows it.
    TableOutcome {
      visible: root.idleNote !== ""
      text: root.idleNote
    }

    TableWarning {
      visible: root.hibernation && root.ready && (root.isForeign("hibernateAfter") || root.isForeign("hibernate.ac"))
      text: "A system configuration file controls hibernation, so that choice may have no effect."
      details: "A file in /etc/systemd/sleep.conf.d that sorts after 60-karchy-settings.conf."
    }

    // What "Never" costs a laptop.
    TableOutcome {
      visible: root.hibernation && root.battery && root.ready && !root.isForeign("hibernateAfter") && Number(root.values.hibernateAfter) === 0
      text: "Sleep still uses the battery: it runs down over days."
    }

    // ---------- Lid and power button ----------
    GroupRule {}
    GroupName { text: root.lid ? "Lid & power button" : "Power button" }
    SourceHeading { visible: root.lid && root.battery; name: "On battery"; now: root.onBattery }
    SourceHeading { visible: root.lid && root.battery; name: "Plugged in"; now: !root.onBattery }
    // No lid: nothing here differs by power source.
    Item { visible: root.wide && !(root.lid && root.battery); Layout.columnSpan: table.bothSources; implicitWidth: 1; implicitHeight: 1 }

    RowLabel { visible: root.lid; text: "Closing the lid" }
    PowerChoice { visible: root.lid && root.battery; page: root; setting: "lid.battery"; choices: root.lidChoices; nameFor: root.actionName }
    PowerChoice { visible: root.lid; page: root; setting: "lid.ac"; choices: root.lidChoices; nameFor: root.actionName }

    RowLabel { visible: root.lid; text: "With an external display" }
    PowerChoice {
      visible: root.lid
      Layout.columnSpan: table.bothSources
      page: root
      setting: "lid.docked"
      choices: root.dockedChoices
      nameFor: root.actionName
    }

    RowLabel { text: "Pressing the power button" }
    PowerChoice {
      Layout.columnSpan: table.bothSources
      page: root
      setting: "powerKey"
      choices: root.powerKeyChoices
      nameFor: root.actionName
    }

    TableError { group: "buttons" }

    TableWarning {
      visible: root.error === "" && root.isForeign("powerKey") && root.values.powerKey === "custom"
      text: "Your own Hyprland binding for the power button overrides this setting."
      details: "A binding for XF86PowerOff in ~/.config/hypr."
    }

    // Stays while the choice does: a consequence, not an explanation.
    TableWarning {
      visible: root.lid && (root.values["lid.battery"] === "ignore" || root.values["lid.ac"] === "ignore")
      text: "A closed laptop that stays on can overheat in a bag and drain the battery."
    }

    // Why a choice may do nothing; which file, for whoever goes looking.
    TableWarning {
      visible: root.lid && (root.isForeign("lid.battery") || root.isForeign("lid.ac") || root.isForeign("lid.docked"))
      text: "A system configuration file controls the lid, so these choices may have no effect."
      details: "A file in /etc/systemd/logind.conf.d that sorts after 60-karchy-settings.conf."
    }
  }

  SettingsHeader { visible: root.battery; text: "Battery" }

  GridLayout {
    visible: root.battery
    Layout.fillWidth: true
    columns: root.wide ? 2 : 1
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    SettingsLabel { text: "Low battery warning" }
    PowerChoice {
      page: root
      setting: "battery.low"
      choices: root.percentChoices([10, 15, 20, 25, 30], function(level) {
        return level > Number(root.values["battery.critical"] || 0) && level > root.criticalLevel })
      nameFor: function(level) { return Number(level) === 0 ? "Off" : level + "%" }
    }

    SettingsLabel { text: "Second warning" }
    PowerChoice {
      page: root
      setting: "battery.critical"
      choices: root.percentChoices([5, 7, 10], function(level) {
        return level > root.criticalLevel && (Number(root.values["battery.low"] || 0) === 0 || level < Number(root.values["battery.low"])) })
      nameFor: function(level) { return Number(level) === 0 ? "Off" : level + "%" }
    }

    // Power saver from the first warning until the charger goes in, or until
    // another mode is picked by hand: karchy's default.
    SettingsLabel { visible: root.profiles.indexOf("power-saver") !== -1; text: "Automatic Power saver" }
    PowerChoice {
      visible: root.profiles.indexOf("power-saver") !== -1
      page: root
      setting: "battery.saver"
      choices: [{ value: "on", label: "At the low battery warning" }, { value: "off", label: "Off" }]
    }

    // UPower's last resort for a laptop nobody plugs in: always under the
    // last warning, so the warnings come first.
    SettingsLabel { text: "Critical battery level" }
    PowerChoice {
      page: root
      setting: "criticalBattery.level"
      choices: root.percentChoices([2, 3, 4, 5, 7, 10], function(level) { return root.lastWarning === 0 || level < root.lastWarning })
      nameFor: function(level) { return level + "%" }
    }

    SettingsLabel { text: "Critical battery action" }
    PowerChoice { page: root; setting: "criticalBattery.action"; choices: root.criticalChoices; nameFor: root.criticalName }
  }

  GroupError { group: "battery" }

  // Set by hand in shell.json: a warning the computer never gets to show.
  InlineMessage {
    visible: root.battery && root.ready && root.lastWarning > 0 && root.criticalLevel >= root.lastWarning
    kind: "warning"
    text: "The critical battery level (" + root.criticalLevel + "%) is not under the last warning (" + root.lastWarning + "%), so that warning never shows."
  }

  InlineMessage {
    visible: root.battery && root.ready && (root.isForeign("criticalBattery.level") || root.isForeign("criticalBattery.action"))
    kind: "warning"
    text: "A system configuration file controls the critical battery, so these choices may have no effect."
    details: "A file in /etc/UPower/UPower.conf.d that sorts after 60-karchy-settings.conf, or UPower hasn't started again since the change."
  }

  Outcome {
    visible: root.battery && root.criticalNote !== ""
    text: root.criticalNote
  }

  Button {
    focusable: true
    visible: Object.keys(root.saved).length > 0
    Layout.topMargin: Style.spacing.lg
    text: "Back to karchy's defaults"
    bordered: true
    // Drops every power choice saved here, so it asks first.
    onClicked: if (root.settings) root.settings.ask("Go back to karchy's defaults? Every choice made on this page is forgotten.",
      "Back to defaults", function() { root.run(["reset"]) })
  }
}
