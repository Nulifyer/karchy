import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import "BatteryModel.js" as BatteryModel

Item {
  id: root

  property var shell: null
  property string karchyPath: Quickshell.env("KARCHY_PATH")

  // A low and a critical warning, each shown once per discharge. The levels
  // are `battery.low` and `battery.critical` in shell.json (percent, 0 = off).
  // What happens to an unattended laptop below them is UPower's
  // CriticalPowerAction (system/laptop/upower.conf, and Settings › Power's
  // "Nearly empty at"), which acts at a level karchy-settings-power keeps
  // under the last warning.
  readonly property int defaultLowPercent: 15
  readonly property int defaultCriticalPercent: 5
  readonly property var batteryConfig: shell && shell.shellConfig && shell.shellConfig.battery
    ? shell.shellConfig.battery : ({})
  readonly property var thresholds: BatteryModel.warningThresholds(batteryConfig, defaultLowPercent, defaultCriticalPercent)
  onThresholdsChanged: checkBattery()
  // The charger going in or out brings the source's own power profile and
  // screen brightness (karchy-power-source, Settings › Power). The first
  // battery warning of a discharge asks for the battery's profile again, which
  // is Power saver unless `battery.saver` is off: karchy-powerprofiles-set
  // decides that from the charge, so the session's start agrees with it.
  property string pendingPowerSource: ""
  property bool pendingLowBattery: false
  property string runningPowerSource: ""
  // Follows power-profiles-daemon's change signals, so nothing polls it.
  // Quickshell never attaches that listener if the daemon failed when the
  // shell started, so a one-off read on startup, on a power source change and
  // after karchy-powerprofiles-set (which asks for it over IPC) recovers.
  property string activePowerProfile: ""
  property bool powerProfileReadPending: false
  property int powerProfileSignals: 0
  property int powerProfileReadSignals: 0

  PersistentProperties {
    id: persisted
    reloadableId: "karchy-battery"
    // The highest warning shown in this discharge: "", "low" or "critical".
    property string warned: ""
  }

  function batteryPercentage() {
    return BatteryModel.batteryPercentage(UPower.displayDevice)
  }

  function isDischarging() {
    return BatteryModel.isDischarging(UPower.displayDevice, UPower.onBattery, UPowerDeviceState.Discharging)
  }

  function batterySample() {
    return {
      level: batteryPercentage(),
      onBattery: UPower.onBattery,
      discharging: isDischarging()
    }
  }

  function checkBattery() {
    var sample = batterySample()
    var before = persisted.warned
    var step = BatteryModel.warningStep(before, sample, thresholds)
    persisted.warned = step.warned
    if (step.notify && before === "") applyLowBattery()
    if (step.notify) sendBatteryWarning(step.notify, sample.level)
    else if (step.clear) clearWarningsProcess.running = true
  }

  // The two warnings have a process each: the critical one must not wait for
  // a slow battery-low hook.
  function sendBatteryWarning(kind, level) {
    var process = kind === "critical" ? criticalWarningProcess : lowWarningProcess
    if (process.running) return
    process.command = [kind === "critical" ? "karchy-battery-critical" : "karchy-battery-low", String(level)]
    process.running = true
  }

  function applyPowerSource() {
    pendingPowerSource = UPower.onBattery ? "battery" : "ac"
    // The source's command picks the profile for the charge as it is now.
    pendingLowBattery = false
    runPendingPowerCommand()
  }

  function applyLowBattery() {
    if (batteryConfig.saver !== true) return
    // A change to battery power that is pending or running covers it.
    if (pendingPowerSource !== "" || (powerProfileProcess.running && runningPowerSource === "battery")) return
    pendingLowBattery = true
    runPendingPowerCommand()
  }

  // The newest power source wins over one still waiting; the low-battery
  // request waits its turn.
  function runPendingPowerCommand() {
    if (powerProfileProcess.running) return
    if (pendingPowerSource !== "") {
      runningPowerSource = pendingPowerSource
      powerProfileProcess.command = ["karchy-power-source", pendingPowerSource]
      pendingPowerSource = ""
    } else if (pendingLowBattery) {
      runningPowerSource = ""
      powerProfileProcess.command = ["karchy-powerprofiles-set", "battery"]
      pendingLowBattery = false
    } else {
      return
    }
    powerProfileProcess.running = true
  }

  function refreshPowerProfile() {
    // A read already running may have sampled the profile before the change
    // this refresh is for, so run another once it finishes.
    if (powerProfileReadProcess.running) {
      powerProfileReadPending = true
      return
    }
    powerProfileReadPending = false
    powerProfileReadSignals = powerProfileSignals
    powerProfileReadProcess.running = true
  }

  function profileName(profile) {
    switch (profile) {
      case PowerProfile.PowerSaver: return "power-saver"
      case PowerProfile.Performance: return "performance"
      default: return "balanced"
    }
  }

  Process { id: lowWarningProcess }
  Process { id: criticalWarningProcess }

  // With the charger in, the warnings on screen no longer hold: the critical
  // one never leaves by itself. The notifications are found by their titles,
  // the ones karchy-battery-low and karchy-battery-critical send.
  Process {
    id: clearWarningsProcess
    command: ["bash", "-c", "for title in battery.lowTitle battery.criticalTitle; do karchy-shell -q notifications dismiss \"$(karchy-i18n \"$title\")\"; done"]
  }

  Process {
    id: powerProfileProcess
    onExited: {
      // Deferred: the process still reports running while it signals exit.
      Qt.callLater(root.runPendingPowerCommand)
      root.refreshPowerProfile()
    }
  }

  Process {
    id: powerProfileReadProcess
    // Read the property straight from the daemon rather than via
    // `powerprofilesctl get`. That is a PyGObject script, and spawning a Python
    // interpreter for it trips a CPython 3.14 shutdown race
    // (python/cpython#124619): the GLib D-Bus worker thread re-enters the
    // interpreter after finalization and the process dies with SIGSEGV.
    command: ["busctl", "--json=short", "get-property", "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles", "ActiveProfile"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.activePowerProfile = BatteryModel.profileAfterRead(root.activePowerProfile, text, root.powerProfileReadSignals, root.powerProfileSignals)
    }
    onExited: {
      // Deferred: the process still reports running while it signals exit.
      if (root.powerProfileReadPending) Qt.callLater(root.refreshPowerProfile)
    }
  }

  Connections {
    target: PowerProfiles
    function onProfileChanged() {
      root.powerProfileSignals++
      root.activePowerProfile = root.profileName(PowerProfiles.profile)
    }
  }

  ShellIpc {
    target: "battery"

    function refreshPowerProfile(): void { root.refreshPowerProfile() }

    function status(): string {
      var sample = root.batterySample()
      return JSON.stringify({
        level: sample.level,
        onBattery: sample.onBattery,
        discharging: sample.discharging,
        low: root.thresholds.low,
        critical: root.thresholds.critical,
        warned: persisted.warned
      })
    }
  }

  // UPower signals every change of the battery's level and state, so the
  // warnings follow those signals; nothing polls.
  Connections {
    target: UPower.displayDevice
    function onPercentageChanged() { root.checkBattery() }
    function onStateChanged() { root.checkBattery() }
    function onIsPresentChanged() { root.checkBattery() }
    function onReadyChanged() { root.checkBattery() }
  }

  Connections {
    target: UPower
    function onOnBatteryChanged() {
      root.applyPowerSource()
      root.checkBattery()
      root.refreshPowerProfile()
    }
  }

  Component.onCompleted: {
    root.checkBattery()
    root.refreshPowerProfile()
  }
}
