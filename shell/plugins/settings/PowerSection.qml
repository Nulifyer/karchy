import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Power: how the computer runs and what it does when left alone
// or closed, on battery and plugged in; the power button; and the battery
// warnings, through karchy-settings-power.
//
// Everything that can differ by power source is one table: a row a setting,
// "On battery" beside "Plugged in". The page shows what this machine has: a
// desktop gets one column and no lid, brightness, dimming or battery rows,
// the power mode appears where power-profiles-daemon runs, and hibernation
// only where it works. Every control shows the value in effect, read back after each
// change, and a group says in a sentence what its choices add up to when
// that isn't plain from them.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  // The Settings window, for its confirm dialog (set by its Loader).
  property var settings: null
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
  // "use", "idle", "lid", "powerKey", "battery", or "" for the page.
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
    var timed = setting.indexOf("screenOff.") === 0 || setting.indexOf("lock.") === 0
      || setting.indexOf("sleep.") === 0 || setting.indexOf("dim.") === 0 || setting === "hibernateAfter"
    var zero = timed ? "never" : setting.indexOf("brightness.") === 0 ? "keep" : "0"
    root.run(["set", setting, String(value) === "0" ? zero : String(value)])
  }

  function groupOf(setting) {
    var name = String(setting).split(".")[0]
    if (name === "profile" || name === "brightness") return "use"
    if (name === "empty") return "battery"
    if (name === "screenOff" || name === "dim" || name === "lock" || name === "sleep" || name === "hibernateAfter" || name === "hibernate") return "idle"
    return name
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
    return root.profileName(root.runningProfile) + " is running now, not this choice: a low battery or an app can hold another mode for a while."
  }

  function brightnessName(percent) { return Number(percent) === 0 ? "Leave as it is" : percent + "%" }

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

  // The battery warnings that are on, as the shell counts them: a second
  // warning at or above the first leaves only the second.
  readonly property int warnLow: {
    var low = Number(root.values["battery.low"] || 0), again = Number(root.values["battery.critical"] || 0)
    return again >= low ? 0 : low
  }
  readonly property int warnAgain: Number(root.values["battery.critical"] || 0)
  // The later of them, 0 with both off: the nearly-empty level stays under it.
  readonly property int lastWarning: warnAgain > 0 ? warnAgain : warnLow
  readonly property int emptyLevel: Number(root.values["empty.level"] || 0)

  // What a laptop left running on its battery does when it is nearly empty.
  // Hibernation is offered only where it works; told to hibernate elsewhere,
  // UPower shuts down, and that is then the value shown.
  readonly property var emptyChoices: {
    var out = []
    if (root.hibernation) out.push({ value: "hibernate", label: "Hibernate" })
    out.push({ value: "poweroff", label: "Shut down" })
    return out
  }

  // UPower's own names for what the page doesn't offer (set in a file).
  function emptyName(action) {
    var names = { hibernate: "Hibernate", poweroff: "Shut down", hybridsleep: "Sleep, saved to disk too",
                  suspend: "Sleep", sleep: "Sleep", ignore: "Nothing" }
    return names[action] || String(action)
  }

  readonly property string lastResort: {
    var action = String(root.values["empty.action"] || "")
    if (root.emptyLevel <= 0 || action === "") return ""
    var does = action === "hibernate" ? "hibernates, so nothing open is lost"
      : action === "poweroff" ? "shuts down; unsaved work is lost"
      : action === "hybridsleep" ? "sleeps, with the session also saved to disk"
      : action === "ignore" ? "does nothing, and the battery runs out"
      : "sleeps, and what is open is lost when the battery runs out"
    return "At " + root.emptyLevel + "% it " + does + "."
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

  // The second cell of a group's heading on a desktop.
  component NoHeading: Item {
    visible: !root.battery
    implicitWidth: 1
    implicitHeight: 1
  }

  // A line that belongs to a group in the table.
  component TableOutcome: Outcome { Layout.columnSpan: table.columns }
  component TableError: GroupError { Layout.columnSpan: table.columns; Layout.fillWidth: true }
  component TableWarning: InlineMessage { Layout.columnSpan: table.columns; Layout.fillWidth: true; kind: "warning" }

  PageHeader {
    title: "Power"
    explanation: "The power mode is the one the battery in the bar sets. Screen brightness, idle times and battery warnings you edit by hand in shell.json win over these. Lid, hibernation and the nearly empty battery are system settings, changed without a password at this computer."
    ConfigFileLink { closes: root.settings; file: ".config/karchy/shell.json" }
  }

  GroupError { group: "" }

  // Everything that has a value for each power source: a row a setting, a
  // column a source. Hidden rows leave no gap, so a desktop reads as a plain
  // list with one column.
  GridLayout {
    id: table
    Layout.fillWidth: true
    columns: root.battery ? 3 : 2
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    readonly property bool useGroup: root.profiles.length > 0 || (root.battery && root.backlight)

    // ---------- While in use: how it runs ----------
    GroupRule { visible: table.useGroup; Layout.topMargin: Style.spacing.lg }
    GroupName { visible: table.useGroup; text: "While in use" }
    SourceHeading { visible: table.useGroup && root.battery; name: "On battery"; now: root.onBattery }
    SourceHeading { visible: table.useGroup && root.battery; name: "Plugged in"; now: !root.onBattery }
    NoHeading { visible: table.useGroup && !root.battery }

    SettingsLabel { visible: root.profiles.length > 0; text: "Power mode" }
    PowerChoice { visible: root.profiles.length > 0 && root.battery; page: root; setting: "profile.battery"; choices: root.profileChoices; nameFor: root.profileName }
    PowerChoice { visible: root.profiles.length > 0; page: root; setting: "profile.ac"; choices: root.profileChoices; nameFor: root.profileName }

    // Set once, when the charger goes in or out; the brightness keys work as
    // before afterwards.
    SettingsLabel { visible: root.battery && root.backlight; text: "Screen brightness" }
    PowerChoice { visible: root.battery && root.backlight; page: root; setting: "brightness.battery"; choices: root.brightnessChoices; nameFor: root.brightnessName }
    PowerChoice { visible: root.battery && root.backlight; page: root; setting: "brightness.ac"; choices: root.brightnessChoices; nameFor: root.brightnessName }

    TableError { group: "use" }

    TableOutcome {
      visible: root.profiles.length > 0 && root.profileNote !== ""
      text: root.profileNote
    }

    // ---------- When left alone: screen, lock, sleep, hibernation ----------
    GroupRule { Layout.topMargin: table.useGroup ? Style.spacing.xxl + Style.spacing.lg - table.rowSpacing : Style.spacing.lg }
    GroupName { text: "When left alone" }
    SourceHeading { name: "On battery"; now: root.onBattery }
    SourceHeading { name: "Plugged in"; now: !root.onBattery }
    NoHeading {}

    SettingsLabel { text: "Turn off the screen" }
    PowerChoice { visible: root.battery; page: root; setting: "screenOff.battery"; choices: root.screenChoices; nameFor: root.timeName }
    PowerChoice { page: root; setting: "screenOff.ac"; choices: root.screenChoices; nameFor: root.timeName }

    // The built-in screen only, and only where it ever turns off by itself.
    SettingsLabel { visible: root.backlight; text: "Dim it first" }
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

    SettingsLabel { text: "Lock" }
    PowerChoice { visible: root.battery; page: root; setting: "lock.battery"; choices: root.screenChoices; nameFor: root.timeName }
    PowerChoice { page: root; setting: "lock.ac"; choices: root.screenChoices; nameFor: root.timeName }

    SettingsLabel { text: "Sleep" }
    PowerChoice { visible: root.battery; page: root; setting: "sleep.battery"; choices: root.sleepChoices; nameFor: root.timeName }
    PowerChoice { page: root; setting: "sleep.ac"; choices: root.sleepChoices; nameFor: root.timeName }

    // After any sleep: idle, the lid, the power button or the menu. A
    // desktop has the one time; a laptop also says whether it counts while
    // plugged in.
    SettingsLabel { visible: root.hibernation; text: "Then hibernate after" }
    PowerChoice { visible: root.hibernation; page: root; setting: "hibernateAfter"; choices: root.hibernateChoices; nameFor: root.hibernateName }
    PowerChoice {
      visible: root.hibernation && root.battery
      enabled: current !== "" && Number(root.values.hibernateAfter) !== 0
      page: root
      setting: "hibernate.ac"
      choices: root.hibernateAcChoices
    }

    TableError { group: "idle" }

    // Said only when the times interact: one of them never comes.
    TableOutcome {
      visible: root.ready && (root.idleNeedsSaying("ac") || (root.battery && root.idleNeedsSaying("battery")))
      text: root.battery
        ? "On battery: " + root.idleSummary("battery") + "\nPlugged in: " + root.idleSummary("ac")
        : root.capitalized(root.idleSummary("ac"))
    }

    TableWarning {
      visible: root.hibernation && root.ready && (root.isForeign("hibernateAfter") || root.isForeign("hibernate.ac"))
      text: "A system configuration file controls hibernation, so that choice may have no effect."
      details: "A file in /etc/systemd/sleep.conf.d that sorts after 60-karchy-settings.conf."
    }

    // What the choice costs, or what happens with none made.
    TableOutcome {
      visible: root.hibernation && root.ready && !root.isForeign("hibernateAfter") && Number(root.values.hibernateAfter) <= 0
      text: Number(root.values.hibernateAfter) === 0
        ? "Sleep still uses power: a battery runs down over days."
        : "Hibernates when the battery is nearly empty."
    }

    // ---------- Lid ----------
    GroupRule { visible: root.lid }
    GroupName { visible: root.lid; text: "Lid" }
    SourceHeading { visible: root.lid && root.battery; name: "On battery"; now: root.onBattery }
    SourceHeading { visible: root.lid && root.battery; name: "Plugged in"; now: !root.onBattery }
    NoHeading { visible: root.lid && !root.battery }

    SettingsLabel { visible: root.lid; text: "When the lid closes" }
    PowerChoice { visible: root.lid && root.battery; page: root; setting: "lid.battery"; choices: root.lidChoices; nameFor: root.actionName }
    PowerChoice { visible: root.lid; page: root; setting: "lid.ac"; choices: root.lidChoices; nameFor: root.actionName }

    SettingsLabel { visible: root.lid; text: "External display" }
    PowerChoice {
      visible: root.lid
      Layout.columnSpan: root.battery ? 2 : 1
      page: root
      setting: "lid.docked"
      choices: root.dockedChoices
      nameFor: root.actionName
    }

    TableError { group: "lid" }

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

  SettingsHeader { visible: root.battery; text: "Low battery" }

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
      choices: root.percentChoices([10, 15, 20, 25, 30], function(level) {
        return level > Number(root.values["battery.critical"] || 0) && level > root.emptyLevel })
      nameFor: function(level) { return Number(level) === 0 ? "No warning" : level + "%" }
    }

    SettingsLabel { text: "Warn again at" }
    PowerChoice {
      page: root
      setting: "battery.critical"
      choices: root.percentChoices([5, 7, 10], function(level) {
        return level > root.emptyLevel && (Number(root.values["battery.low"] || 0) === 0 || level < Number(root.values["battery.low"])) })
      nameFor: function(level) { return Number(level) === 0 ? "No warning" : level + "%" }
    }

    // Power saver from the first warning until the charger goes in, or until
    // another mode is picked by hand: karchy's default.
    SettingsLabel { visible: root.profiles.indexOf("power-saver") !== -1; text: "At the first warning" }
    PowerChoice {
      visible: root.profiles.indexOf("power-saver") !== -1
      page: root
      setting: "battery.saver"
      choices: [{ value: "on", label: "Switch to Power saver" }, { value: "off", label: "Keep the power mode" }]
    }

    // UPower's last resort for a laptop nobody plugs in: always under the
    // last warning, so the warnings come first.
    SettingsLabel { text: "Nearly empty at" }
    PowerChoice {
      page: root
      setting: "empty.level"
      choices: root.percentChoices([2, 3, 4, 5, 7, 10], function(level) { return root.lastWarning === 0 || level < root.lastWarning })
      nameFor: function(level) { return level + "%" }
    }

    SettingsLabel { text: "When nearly empty" }
    PowerChoice { page: root; setting: "empty.action"; choices: root.emptyChoices; nameFor: root.emptyName }
  }

  GroupError { group: "battery" }

  // Set by hand in shell.json: a warning the computer never gets to show.
  InlineMessage {
    visible: root.battery && root.ready && root.lastWarning > 0 && root.emptyLevel >= root.lastWarning
    kind: "warning"
    text: "The computer acts at " + root.emptyLevel + "%, at or before the last warning (" + root.lastWarning + "%), so that warning is never seen."
  }

  InlineMessage {
    visible: root.battery && root.ready && (root.isForeign("empty.level") || root.isForeign("empty.action"))
    kind: "warning"
    text: "A system configuration file controls the nearly empty battery, so these choices may have no effect."
    details: "A file in /etc/UPower/UPower.conf.d that sorts after 60-karchy-settings.conf, or UPower hasn't started again since the change."
  }

  Outcome {
    visible: root.battery && root.lastResort !== ""
    text: root.lastResort
  }

  Button {
    focusable: true
    visible: Object.keys(root.saved).length > 0
    Layout.topMargin: Style.spacing.lg
    text: "Back to karchy's defaults"
    bordered: true
    // Drops every power choice saved here, so it asks first.
    onClicked: if (root.settings) root.settings.ask("Go back to karchy's defaults? Every power mode, brightness, dimming, idle time, lid, power button, hibernation and battery choice made here is forgotten.",
      "Back to defaults", function() { root.run(["reset"]) })
  }
}
