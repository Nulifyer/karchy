const assert = require("assert")
const M = require(process.argv[2] + "/shell/plugins/services/battery/BatteryModel.js")
const T = M.warningThresholds({}, 15, 5)
assert.deepStrictEqual(T, { low: 15, critical: 5 })
assert.deepStrictEqual(M.warningThresholds({ low: 20, critical: 10 }, 15, 5), { low: 20, critical: 10 })
assert.deepStrictEqual(M.warningThresholds({ low: 0 }, 15, 5), { low: 0, critical: 5 }, "low off")
assert.deepStrictEqual(M.warningThresholds({ critical: 0 }, 15, 5), { low: 15, critical: 0 }, "critical off")
assert.deepStrictEqual(M.warningThresholds({ low: "x", critical: null }, 15, 5), { low: 15, critical: 5 }, "junk falls back")
assert.deepStrictEqual(M.warningThresholds({ low: 5, critical: 8 }, 15, 5), { low: 0, critical: 8 }, "critical at or above low leaves only critical")
assert.deepStrictEqual(M.warningThresholds({ low: 250, critical: -3 }, 15, 5), { low: 100, critical: 0 })
assert.deepStrictEqual(M.warningThresholds(null, 15, 5), { low: 15, critical: 5 })

// Walk a sequence of samples and collect the warnings shown.
function run(samples, thresholds = T) {
  let warned = "", shown = []
  for (const [level, onBattery, discharging] of samples) {
    const step = M.warningStep(warned, { level, onBattery, discharging }, thresholds)
    warned = step.warned
    shown.push(step.notify)
  }
  return shown.filter(Boolean).join(",") + "|" + warned
}
const B = (l) => [l, true, true]      // on battery, discharging
const AC = (l) => [l, false, false]   // charger in

assert.strictEqual(run([B(50), B(16)]), "|", "above the low level: nothing")
assert.strictEqual(run([B(16), B(15), B(14), B(13)]), "low|low", "low shows once")
assert.strictEqual(run([B(15), B(16), B(15), B(16), B(15)]), "low|low", "a wobbling level does not repeat it")
assert.strictEqual(run([B(16), B(15), B(10), B(5), B(4), B(3)]), "low,critical|critical", "low, then critical, each once")
assert.strictEqual(run([B(5), B(6), B(5)]), "critical|critical", "critical does not repeat")
assert.strictEqual(run([B(4)]), "critical|critical", "starting under critical shows only critical")
assert.strictEqual(run([B(4), B(7)]), "critical|critical", "no low warning after the critical one")
assert.strictEqual(run([B(15), AC(15), B(15)]), "low,low|low", "the charger clears it: the next discharge warns again")
assert.strictEqual(run([B(4), AC(4), AC(9), B(9)]), "critical,low|low", "after charging a little, low warns again")
assert.strictEqual(run([B(4), AC(5), B(4)]), "critical,critical|critical")
assert.strictEqual(run([AC(3), AC(2)]), "|", "plugged in: nothing, however low")
assert.strictEqual(run([B(15), [14, true, false], B(14)]), "low|low", "an unknown state on battery forgets nothing")
assert.strictEqual(run([[10, true, false]]), "|", "on battery but not discharging: nothing shown")
assert.strictEqual(run([[-1, false, false], B(10)]), "low|low", "no battery, then one appears low")
assert.strictEqual(run([B(10), [-1, true, false], B(10)]), "low,low|low", "a battery that went away starts over")
assert.strictEqual(run([B(15), B(5)], { low: 0, critical: 5 }), "critical|critical", "low turned off")
assert.strictEqual(run([B(15), B(5), B(1)], { low: 15, critical: 0 }), "low|low", "critical turned off")
assert.strictEqual(run([B(1)], { low: 0, critical: 0 }), "|", "both off")
// batteryPercentage / isDischarging keep working
assert.strictEqual(M.batteryPercentage({ isPresent: true, percentage: 0.149 }), 15)
assert.strictEqual(M.batteryPercentage(null), -1)
console.log("battery model: ok")
