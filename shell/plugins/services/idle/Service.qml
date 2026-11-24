import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Wayland
import "IdleModel.js" as IdleModel
import qs.Commons

Item {
  id: root

  // Injected by karchy-shell (the first-party service loader).
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string stayAwakeStateDir: home + "/.local/state/karchy/indicators"
  readonly property string stayAwakeStatePath: stayAwakeStateDir + "/stay-awake"
  readonly property int defaultScreensaverSeconds: 150
  readonly property int defaultLockSeconds: 300
  // The screen turns off after this long idle, locked or not. 0 turns it off.
  readonly property int defaultScreenOffSeconds: 300
  // Sleep after this long idle, on battery only unless idle.suspendOnAC is
  // true or idle.ac.suspend gives plugged-in its own time. 0 turns it off.
  readonly property int defaultSuspendSeconds: 900
  // The built-in screen is dimmed this long before it turns off (0 = not),
  // to this percent: on battery only, unless idle.ac.dim is set. See
  // "Dimming" below.
  readonly property int defaultDimSeconds: onBattery ? 30 : 0
  readonly property int defaultDimBrightness: 10
  readonly property var idleConfig: shell && shell.shellConfig && shell.shellConfig.idle
    ? shell.shellConfig.idle : ({})
  // A desktop's UPower reports no laptop battery and never "on battery", so
  // it follows the plugged-in times.
  readonly property bool hasBattery: UPower.displayDevice && UPower.displayDevice.isLaptopBattery
  readonly property bool onBattery: hasBattery && UPower.onBattery
  // The times for the power source in use (Settings › Power); see IdleModel.
  readonly property var timeouts: IdleModel.timeouts(idleConfig, onBattery, {
    screensaver: defaultScreensaverSeconds,
    screenOff: defaultScreenOffSeconds,
    lock: defaultLockSeconds,
    suspend: defaultSuspendSeconds,
    dim: defaultDimSeconds,
    dimBrightness: defaultDimBrightness
  })
  readonly property int screensaverTimeoutSeconds: timeouts.screensaver
  readonly property int screenOffTimeoutSeconds: timeouts.screenOff
  readonly property int lockTimeoutSeconds: timeouts.lock
  readonly property int suspendTimeoutSeconds: timeouts.suspend
  readonly property bool suspendNow: suspendTimeoutSeconds > 0
  readonly property bool screensaverEnabled: screensaverTimeoutSeconds > 0
  readonly property bool screenOffEnabled: screenOffTimeoutSeconds > 0
  readonly property bool lockEnabled: lockTimeoutSeconds > 0
  readonly property bool idleTimersEnabled: screensaverEnabled || screenOffEnabled || lockEnabled || suspendNow
  // The kernel backlight karchy-hw-display picks, which the brightness keys
  // already look up: only a built-in screen is dimmed.
  readonly property bool hasBacklight: !!(shell && shell.brightnessKeys && shell.brightnessKeys.device)
  // Seconds idle until the screen is dimmed on this power source, 0 for never.
  readonly property int dimAfterSeconds: IdleModel.dimAfter(timeouts, hasBacklight)
  readonly property int firstIdleTimeoutSeconds: IdleModel.firstIdleTimeout(
    screensaverTimeoutSeconds, screenOffTimeoutSeconds, lockTimeoutSeconds, suspendTimeoutSeconds, dimAfterSeconds)
  readonly property int dimDelaySeconds: IdleModel.delayAfterFirstIdle(dimAfterSeconds, firstIdleTimeoutSeconds)
  readonly property int screensaverDelaySeconds: IdleModel.delayAfterFirstIdle(screensaverTimeoutSeconds, firstIdleTimeoutSeconds)
  readonly property int screenOffDelaySeconds: IdleModel.delayAfterFirstIdle(screenOffTimeoutSeconds, firstIdleTimeoutSeconds)
  readonly property int lockDelaySeconds: IdleModel.delayAfterFirstIdle(lockTimeoutSeconds, firstIdleTimeoutSeconds)
  readonly property int suspendDelaySeconds: IdleModel.delayAfterFirstIdle(suspendTimeoutSeconds, firstIdleTimeoutSeconds)
  readonly property bool idleEnabled: stayAwakeStateLoaded && !stayAwake
  readonly property string screensaverClass: "org.karchy.screensaver"

  // Inhibitors that never reach the compositor: org.freedesktop.ScreenSaver
  // cookies (games, Electron, the portal) and logind locks, as reported by
  // karchy-system-idle-inhibit. Wayland idle inhibitors and Hyprland's
  // idle_inhibit rules are honoured by the IdleMonitor itself. An "idle" hold
  // stops the whole cycle, as a Wayland inhibitor does; a "sleep" hold only
  // makes the idle suspend wait.
  property var inhibitors: []
  readonly property bool idleInhibited: IdleModel.inhibits(inhibitors, "idle")
  readonly property bool sleepInhibited: IdleModel.inhibits(inhibitors, "sleep")
  // The suspend deadline passed while something held sleep.
  property bool suspendWaiting: false

  function applyInhibitors(line) {
    var next = IdleModel.parseInhibitors(line)
    if (next === null) return
    var before = IdleModel.describeInhibitors(root.inhibitors)
    var after = IdleModel.describeInhibitors(next)
    root.inhibitors = next
    if (before !== after) logEvent("inhibitors", after || "none")
  }

  onIdleInhibitedChanged: {
    if (!idleInhibited) return
    // The monitor stops while idle is held; end what an idle stretch started.
    if (root.idledThisCycle || suspendTimer.running || root.suspendWaiting) cancelIdleCycle("inhibited")
  }

  onSleepInhibitedChanged: {
    if (sleepInhibited || !root.suspendWaiting) return
    root.suspendWaiting = false
    if (root.idleEnabled && idleMonitor.isIdle && root.suspendNow) suspendSystem("suspend-after-inhibitor")
  }

  // A retimed IdleMonitor can reuse its notification's address and never
  // rebind isIdle, so idle is never reported again; pulsing it off sends the
  // pointer through null. While idle that pulse would read as the user coming
  // back, so retiming waits until they have.
  function retimeIdleMonitor() {
    var timeout = Math.max(1, root.firstIdleTimeoutSeconds)
    if (idleMonitor.isIdle || idleMonitor.timeout === timeout) return

    idleMonitor.timeout = timeout
    if (root.idleEnabled) {
      root.logEvent("idle-monitor-rearm", "timeout=" + timeout)
      idleMonitorRearmTimer.restart()
    }
  }

  onFirstIdleTimeoutSecondsChanged: retimeIdleMonitor()

  // The charger pulled or plugged in during an idle stretch: sleep follows the
  // new source's time, counted from when the stretch began.
  onSuspendTimeoutSecondsChanged: {
    if (!idleMonitor.isIdle || !root.idleEnabled || root.idleSince <= 0) return
    suspendTimer.stop()
    root.suspendWaiting = false
    if (root.suspendTimeoutSeconds <= 0) return
    suspendTimer.interval = Math.max(1000, root.suspendTimeoutSeconds * 1000 - (Date.now() - root.idleSince))
    suspendTimer.restart()
    logEvent("suspend-rearm", "in " + Math.round(suspendTimer.interval / 1000) + "s")
  }

  property bool stayAwake: false
  property bool stayAwakeStateLoaded: false
  property bool hasPendingStayAwakePersist: false
  property bool pendingStayAwakePersist: false
  property bool idledThisCycle: false
  property bool screensaverStartedThisCycle: false
  // The idle service turned the screen off in this cycle.
  property bool screenOffThisCycle: false
  // When the current idle stretch began (ms), 0 while in use.
  property double idleSince: 0

  // Dimming. The built-in screen's backlight is lowered some time before the
  // screen turns off (Settings › Power, "Dim it first") and put back at the
  // first sign of activity. What was there, and whether it is still this
  // service's to put back, is karchy-brightness-display's note: it dims
  // nothing that is already darker and undoes nothing somebody else has set
  // since. This service only says when:
  // - dim: the dim timer, in an unlocked session with the screen still on.
  // - undim: activity (the end of the idle stretch), stay-awake, an inhibitor,
  //   the charger going in or out (karchy-power-source then sets that
  //   source's brightness, if it has one). The screen turning off and waking
  //   undim by themselves (karchy-brightness-display off and on), and so does
  //   the lock before every sleep (karchy-system-sleep-lock), the service's
  //   own start, the session's start and end (karchy-brightness-restore), and
  //   root before systemd saves the backlight at shutdown (D-172).
  // One undim follows every dim and never overtakes it: IdleModel.dimStep
  // holds that order, and this only starts the commands it names.
  property var dimState: ({})
  // A dimming is in place or being undone. The brightness keys then go
  // through karchy-brightness-display, which steps from the level the screen
  // had (shell/services/BrightnessKeys.qml).
  readonly property bool dimPending: IdleModel.dimPending(dimState)

  function dimEvent(event, allowed) {
    var step = IdleModel.dimStep(root.dimState, event, allowed)
    root.dimState = step.state
    if (step.run === "dim") {
      logEvent("dim", "to " + root.timeouts.dimBrightness + "%")
      dimProcess.command = ["bash", "-lc",
        "[[ $(karchy-shell lock isLocked 2>/dev/null) == \"true\" ]] || karchy-brightness-display dim " + root.timeouts.dimBrightness]
      dimProcess.running = true
    } else if (step.run === "undim") {
      logEvent("undim")
      undimProcess.running = true
    }
  }

  // Nothing to dim on a screen that is already off.
  function dimScreen() { dimEvent("dim", !root.screenOffThisCycle) }
  function undimScreen() { dimEvent("undim") }

  // The charger pulled or plugged in: somebody is there, and the brightness
  // of the new source may follow.
  onOnBatteryChanged: undimScreen()
  property string lastEvent: "starting"
  property string lastEventAt: ""
  property var screensaverWindows: ({})
  property int screensaverWindowCount: 0

  function nowIso() {
    return new Date().toISOString()
  }

  function logEvent(event, details) {
    var suffix = details === undefined || details === null || details === "" ? "" : ": " + String(details)
    root.lastEventAt = nowIso()
    root.lastEvent = event + suffix
    console.log("karchy idle " + root.lastEventAt + " " + root.lastEvent)
  }

  function runProcess(process, label, command) {
    if (process.running) {
      logEvent("process-skip", label + " already running")
      return false
    }
    logEvent("process-start", label + " " + command)
    process.command = ["bash", "-lc", command]
    process.running = true
    return true
  }

  function launchScreensaver() {
    // Nothing to draw on a screen that is already off.
    if (root.screenOffThisCycle) return
    root.screensaverStartedThisCycle = true
    screensaverLaunchGraceTimer.restart()
    runProcess(screensaverProcess, "screensaver", "[[ $(karchy-shell lock isLocked 2>/dev/null) == \"true\" ]] || karchy-launch-screensaver")
  }

  // The screen turns off on its own deadline, whether or not the session
  // locks (settings audit F4). A locked session is left alone: the lock screen
  // turns the screen off itself, 5 seconds after it appears or was last used.
  function turnScreenOff() {
    root.screenOffThisCycle = true
    runProcess(screenOffProcess, "screen-off",
      "[[ $(karchy-shell lock isLocked 2>/dev/null) == \"true\" ]] || { karchy-brightness-keyboard off; karchy-brightness-display off; }")
  }

  function lockSystem(reason) {
    logEvent("lock-system", reason || "requested")
    screensaverTimer.stop()
    screenOffTimer.stop()
    lockTimer.stop()
    // A locked session is not dimmed. A screen dimmed before the lock stays
    // so for the lock screen's 5 seconds and is put back as it goes dark.
    dimTimer.stop()
    screensaverLaunchGraceTimer.stop()
    root.idledThisCycle = false
    root.screensaverStartedThisCycle = false
    resetScreensaverWindows()
    runProcess(lockProcess, "lock", "karchy-system-lock")
  }

  // Suspend (then hibernate, where the laptop can) after the lock, unless sleep
  // is turned off. Whether the machine is on battery is checked when the timer
  // fires, so unplugging during the idle stretch counts. systemd refuses
  // suspend-then-hibernate when the swap can't hold memory right now, and a
  // plain suspend is better than staying awake.
  function suspendSystem(reason) {
    logEvent("suspend-system", reason || "requested")
    runProcess(suspendProcess, "suspend",
      "karchy-toggle-enabled suspend-off || karchy-sleep-disabled || " +
      "{ if karchy-hibernation-available; then systemctl suspend-then-hibernate || systemctl suspend; else systemctl suspend; fi; }")
  }

  function startIdleCycle() {
    if (root.idledThisCycle) {
      logEvent("idle-cycle-already-running")
      return
    }

    logEvent("idle-cycle-start", "screensaver=" + root.screensaverTimeoutSeconds + " dim=" + root.dimAfterSeconds
      + " screenOff=" + root.screenOffTimeoutSeconds + " lock=" + root.lockTimeoutSeconds + " suspend=" + root.suspendTimeoutSeconds)
    root.idledThisCycle = true
    root.screensaverStartedThisCycle = false
    root.screenOffThisCycle = false
    root.idleSince = Date.now() - idleMonitor.timeout * 1000
    resetScreensaverWindows()

    // Set this cycle's deadlines once: a bound interval would restart a pending
    // timer from the moment shell.json changes, locking early or late.
    if (root.screensaverEnabled) {
      if (root.screensaverDelaySeconds === 0) launchScreensaver()
      else {
        screensaverTimer.interval = root.screensaverDelaySeconds * 1000
        screensaverTimer.restart()
      }
    }

    if (root.dimAfterSeconds > 0) {
      if (root.dimDelaySeconds === 0) dimScreen()
      else {
        dimTimer.interval = root.dimDelaySeconds * 1000
        dimTimer.restart()
      }
    }

    // A screen-off time at or after the lock's is the lock screen's to keep:
    // it turns the screen off 5 seconds after locking.
    if (root.screenOffEnabled && !(root.lockEnabled && root.lockTimeoutSeconds <= root.screenOffTimeoutSeconds)) {
      if (root.screenOffDelaySeconds === 0) turnScreenOff()
      else {
        screenOffTimer.interval = root.screenOffDelaySeconds * 1000
        screenOffTimer.restart()
      }
    }

    if (root.lockEnabled) {
      if (root.lockDelaySeconds === 0) lockSystem("lock-timeout-immediate")
      else {
        lockTimer.interval = root.lockDelaySeconds * 1000
        lockTimer.restart()
      }
    }

    // The suspend deadline outlives the lock (which ends the screensaver
    // cycle) and is cancelled by activity.
    if (root.suspendTimeoutSeconds > 0) {
      suspendTimer.interval = Math.max(1, root.suspendDelaySeconds) * 1000
      suspendTimer.restart()
    }
  }

  function endIdleStretch() {
    root.idleSince = 0
    screenOffTimer.stop()
    root.screenOffThisCycle = false
    dimTimer.stop()
    undimScreen()
  }

  function cancelIdleCycle(reason) {
    logEvent("idle-cycle-cancel", reason || "requested")
    suspendTimer.stop()
    root.suspendWaiting = false
    screensaverTimer.stop()
    lockTimer.stop()
    screensaverLaunchGraceTimer.stop()
    endIdleStretch()

    if (root.idledThisCycle) runProcess(wakeProcess, "wake", "karchy-system-wake")

    root.idledThisCycle = false
    root.screensaverStartedThisCycle = false
    resetScreensaverWindows()
  }

  function resetScreensaverWindows() {
    root.screensaverWindows = ({})
    root.screensaverWindowCount = 0
  }

  function setScreensaverWindow(address, visible) {
    var next = IdleModel.screensaverWindowsAfter(root.screensaverWindows, address, visible)
    root.screensaverWindows = next.windows
    root.screensaverWindowCount = next.count
  }

  function handleScreensaverWindowOpened(address) {
    setScreensaverWindow(address, true)
    screensaverLaunchGraceTimer.stop()
  }

  function handleScreensaverWindowClosed(address) {
    setScreensaverWindow(address, false)

    if (!root.idleEnabled || !root.idledThisCycle || !root.screensaverStartedThisCycle) return
    if (root.screensaverWindowCount > 0) return

    // The user dismissed the screensaver before the lock deadline. Treat that
    // as activity and cancel the pending lock; the lock timer is only allowed
    // to fire while the screensaver remains up.
    root.cancelIdleCycle("screensaver-dismissed")
  }

  function eventParts(event, count) {
    return IdleModel.eventParts(event, count)
  }

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    if (name === "openwindow") {
      var open = eventParts(event, 4)
      if (String(open[2] || "") === root.screensaverClass) root.handleScreensaverWindowOpened(open[0])
    } else if (name === "closewindow") {
      var close = eventParts(event, 1)
      var address = String(close[0] || "")
      if (root.screensaverWindows[address]) root.handleScreensaverWindowClosed(address)
    }
  }

  function handleActiveSignal() {
    if (!root.idledThisCycle) {
      endIdleStretch()
      // Locked by the idle cycle, then woken: no sleep after all.
      if (suspendTimer.running || root.suspendWaiting) {
        suspendTimer.stop()
        root.suspendWaiting = false
        logEvent("suspend-cancel", "activity")
      }
      return
    }

    // Starting the screensaver can make the compositor report activity. Keep
    // the lock timer running once the screensaver exists (or during its short
    // launch grace); Hyprland window events cancel the cycle if it exits before
    // the normal lock deadline.
    if (root.screensaverStartedThisCycle && (root.screensaverWindowCount > 0 || screensaverLaunchGraceTimer.running)) {
      logEvent("idle-monitor-active", "screensaver cycle remains armed")
      return
    }

    cancelIdleCycle("activity")
  }

  function handleIdleChanged() {
    logEvent("idle-monitor", idleMonitor.isIdle ? "idle" : "active")
    if (!root.idleEnabled || !root.idleTimersEnabled) return

    if (idleMonitor.isIdle) startIdleCycle()
    else handleActiveSignal()
  }

  function statusJson() {
    return JSON.stringify({
      enabled: root.idleEnabled,
      stayAwake: root.stayAwake,
      stayAwakeStateLoaded: root.stayAwakeStateLoaded,
      stayAwakeStatePath: root.stayAwakeStatePath,
      idle: idleMonitor.isIdle,
      inIdleCycle: root.idledThisCycle,
      screensaverStarted: root.screensaverStartedThisCycle,
      onBattery: root.onBattery,
      screensaver: root.screensaverTimeoutSeconds,
      screenOff: root.screenOffTimeoutSeconds,
      screenOffDone: root.screenOffThisCycle,
      dim: root.timeouts.dim,
      dimAfter: root.dimAfterSeconds,
      dimBrightness: root.timeouts.dimBrightness,
      dimmed: root.dimPending,
      lock: root.lockTimeoutSeconds,
      suspend: root.suspendTimeoutSeconds,
      suspendNow: root.suspendNow,
      suspendWaiting: root.suspendWaiting,
      idleInhibited: root.idleInhibited,
      sleepInhibited: root.sleepInhibited,
      inhibitors: root.inhibitors,
      screensaverDelay: root.screensaverDelaySeconds,
      lockDelay: root.lockDelaySeconds,
      screensaverWindows: root.screensaverWindowCount,
      timers: {
        idleMonitorRearm: idleMonitorRearmTimer.running,
        screensaver: screensaverTimer.running,
        screenOff: screenOffTimer.running,
        dim: dimTimer.running,
        lock: lockTimer.running,
        suspend: suspendTimer.running,
        screensaverLaunchGrace: screensaverLaunchGraceTimer.running
      },
      processes: {
        screensaver: screensaverProcess.running,
        lock: lockProcess.running,
        wake: wakeProcess.running
      },
      lastEvent: root.lastEvent,
      lastEventAt: root.lastEventAt
    })
  }

  function persistStayAwake(value) {
    var command = value
      ? "mkdir -p \"$HOME/.local/state/karchy/indicators\" && touch \"$HOME/.local/state/karchy/indicators/stay-awake\""
      : "rm -f \"$HOME/.local/state/karchy/indicators/stay-awake\""

    if (stayAwakeStateWriter.running) {
      root.pendingStayAwakePersist = !!value
      root.hasPendingStayAwakePersist = true
      return
    }

    stayAwakeStateWriter.command = ["bash", "-lc", command]
    stayAwakeStateWriter.running = true
  }

  function refreshStayAwakeState() {
    if (!stayAwakeStateProbe.running) stayAwakeStateProbe.running = true
  }

  function applyStayAwake(value, persist, reason) {
    var enabled = !!value
    var changed = !root.stayAwakeStateLoaded || root.stayAwake !== enabled

    if (persist) persistStayAwake(enabled)

    root.stayAwake = enabled
    root.stayAwakeStateLoaded = true

    if (!changed) return enabled ? "disabled" : "enabled"

    logEvent("stay-awake", (enabled ? "enabled" : "disabled") + (reason ? " " + reason : ""))
    if (enabled) cancelIdleCycle("stay-awake")
    else Qt.callLater(root.handleIdleChanged)

    return enabled ? "disabled" : "enabled"
  }

  function setIdleEnabled(value) {
    return applyStayAwake(!value, true, "ipc")
  }

  // With both timeouts at 0 the monitor stops reporting, so nothing else would end a running cycle.
  onIdleTimersEnabledChanged: if (!idleTimersEnabled) cancelIdleCycle("idle-timers-disabled")

  // The timeout is set by retimeIdleMonitor, never bound. Disabled while a
  // D-Bus or logind inhibitor holds idle, so the countdown starts afresh when
  // the last one is released, as it does after a Wayland inhibitor.
  IdleMonitor {
    id: idleMonitor
    enabled: root.idleEnabled && root.idleTimersEnabled && !root.idleInhibited && !idleMonitorRearmTimer.running
    respectInhibitors: true
    onIsIdleChanged: {
      root.handleIdleChanged()
      if (!isIdle) root.retimeIdleMonitor()
    }
  }

  Timer {
    id: idleMonitorRearmTimer
    interval: 150
    repeat: false
  }

  Timer {
    id: screensaverTimer
    repeat: false
    onTriggered: if (root.screensaverEnabled) root.launchScreensaver()
  }

  Timer {
    id: screenOffTimer
    repeat: false
    onTriggered: if (root.idleEnabled && root.idledThisCycle && root.screenOffEnabled) root.turnScreenOff()
  }

  Timer {
    id: dimTimer
    repeat: false
    onTriggered: if (root.idleEnabled && root.idledThisCycle && root.dimAfterSeconds > 0) root.dimScreen()
  }

  Timer {
    id: lockTimer
    repeat: false
    onTriggered: if (root.idleEnabled && root.idledThisCycle && root.lockEnabled) root.lockSystem("lock-timeout")
  }

  Timer {
    id: suspendTimer
    repeat: false
    onTriggered: {
      if (!(root.idleEnabled && idleMonitor.isIdle && root.suspendNow)) {
        root.logEvent("suspend-skip", "active, stay-awake or sleep is off on this power source")
      } else if (root.sleepInhibited) {
        // systemd would refuse; sleep once the holder lets go, if still idle.
        root.suspendWaiting = true
        root.logEvent("suspend-wait", IdleModel.describeInhibitors(root.inhibitors))
      } else {
        root.suspendSystem("suspend-timeout")
      }
    }
  }

  Timer {
    id: screensaverLaunchGraceTimer
    interval: 3000
    repeat: false
    onTriggered: {
      if (root.idleEnabled && root.idledThisCycle && root.screensaverStartedThisCycle && root.screensaverWindowCount === 0 && !idleMonitor.isIdle) {
        root.cancelIdleCycle("screensaver-not-running")
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  Process {
    id: screensaverProcess
    onExited: function(exitCode, exitStatus) { root.logEvent("process-exit", "screensaver exitCode=" + exitCode + " status=" + exitStatus) }
  }
  Process {
    id: screenOffProcess
    onExited: function(exitCode, exitStatus) { root.logEvent("process-exit", "screen-off exitCode=" + exitCode + " status=" + exitStatus) }
  }
  Process {
    id: dimProcess
    onExited: function(exitCode, exitStatus) {
      root.logEvent("process-exit", "dim exitCode=" + exitCode + " status=" + exitStatus)
      root.dimEvent("dimExited")
    }
  }
  Process {
    id: undimProcess
    command: ["karchy-brightness-display", "undim"]
    onExited: function(exitCode, exitStatus) {
      root.logEvent("process-exit", "undim exitCode=" + exitCode + " status=" + exitStatus)
      root.dimEvent("undimExited")
    }
  }
  Process {
    id: lockProcess
    onExited: function(exitCode, exitStatus) { root.logEvent("process-exit", "lock exitCode=" + exitCode + " status=" + exitStatus) }
  }
  Process {
    id: suspendProcess
    onExited: function(exitCode, exitStatus) { root.logEvent("process-exit", "suspend exitCode=" + exitCode + " status=" + exitStatus) }
  }
  Process {
    id: wakeProcess
    onExited: function(exitCode, exitStatus) { root.logEvent("process-exit", "wake exitCode=" + exitCode + " status=" + exitStatus) }
  }

  // Prints the D-Bus and logind inhibitors, one JSON line per change, and
  // starts their service when it is missing. No line means none are known.
  Process {
    id: inhibitWatchProcess
    command: ["karchy-system-idle-inhibit", "watch"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        inhibitWatchRestartTimer.interval = inhibitWatchRestartTimer.firstDelayMs
        root.applyInhibitors(line)
      }
    }
    onExited: function(exitCode, exitStatus) {
      root.logEvent("process-exit", "inhibit-watch exitCode=" + exitCode + " status=" + exitStatus)
      root.applyInhibitors("[]")
      inhibitWatchRestartTimer.restart()
    }
  }

  // A watcher that died is started again after a pause, which doubles each
  // time it dies without printing anything, so a broken one cannot spin.
  Timer {
    id: inhibitWatchRestartTimer
    readonly property int firstDelayMs: 5000
    readonly property int longestDelayMs: 600000
    interval: firstDelayMs
    repeat: false
    onTriggered: {
      interval = Math.min(interval * 2, longestDelayMs)
      inhibitWatchProcess.running = true
    }
  }

  Process {
    id: stayAwakeStateProbe
    command: ["bash", "-c", "mkdir -p \"$HOME/.local/state/karchy/indicators\"; if [[ -f $HOME/.local/state/karchy/indicators/stay-awake ]]; then echo yes; else echo no; fi"]
    stdout: SplitParser {
      onRead: function(line) { root.applyStayAwake(String(line).trim() === "yes", false, "state-file") }
    }
    onExited: function() { stayAwakeStateDirWatcher.reload() }
  }

  Process {
    id: stayAwakeStateWriter
    onExited: function() {
      if (root.hasPendingStayAwakePersist) {
        var pending = root.pendingStayAwakePersist
        root.hasPendingStayAwakePersist = false
        root.persistStayAwake(pending)
        return
      }

      root.refreshStayAwakeState()
    }
  }

  FileView {
    id: stayAwakeStateDirWatcher
    path: root.stayAwakeStateDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.refreshStayAwakeState()
  }

  Component.onCompleted: {
    logEvent("service-ready")
    // A dimming this service no longer knows of (the shell restarted, or a
    // session or boot ended while dimmed) is undone at once; with none noted
    // this is one file test. Started as an undim of dimStep's, so a dim that
    // comes before it ends waits for it.
    root.dimState = ({ undimRunning: true })
    undimProcess.running = true
    retimeIdleMonitor()
    refreshStayAwakeState()
  }

  ShellIpc {
    target: "idle"

    function status(): string {
      return root.statusJson()
    }

    function debug(): string {
      return root.statusJson()
    }

    function enable(): string {
      return root.setIdleEnabled(true)
    }

    function disable(): string {
      return root.setIdleEnabled(false)
    }

    function toggle(): string {
      return root.setIdleEnabled(!root.idleEnabled)
    }
  }
}
