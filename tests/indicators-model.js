const assert = require("assert")
const M = require(process.argv[2] + "/shell/plugins/bar/widgets/IndicatorsModel.js")
const shipped = ["Updates", "ScreenRecording", "Dnd", "StayAwake", "Reminder", "Minimized"]
const eq = (settings, want) => assert.deepStrictEqual(M.entries(settings, shipped), want)
// No settings: everything karchy ships, in order.
eq({}, shipped)
eq(undefined, shipped)
eq({ items: [] }, shipped)
// hidden leaves indicators out; the rest, and later ones, still show.
eq({ hidden: ["Reminder", "Dnd"] }, ["Updates", "ScreenRecording", "StayAwake", "Minimized"])
// A copy of the defaults from before 2026-11-17 gets the new indicators at their place.
eq({ items: ["Updates", "ScreenRecording", "Reminder", "Minimized"] }, shipped)
// A list the user cut down keeps its choices; only new indicators are added.
eq({ items: ["Minimized", "Updates"] }, ["Minimized", "Updates", "Dnd", "StayAwake"])
eq({ items: ["Reminder"] }, ["Dnd", "StayAwake", "Reminder"])
// hidden wins over an added indicator; a list that knew of an indicator keeps it out.
eq({ items: ["Updates"], hidden: ["StayAwake"] }, ["Updates", "Dnd"])
eq({ items: ["Updates"], known: shipped }, ["Updates"])
eq({ items: ["Updates", "Dnd"], known: shipped }, ["Updates", "Dnd"])
eq({ items: ["Updates", "Dnd"], known: shipped.concat(["Later"]) }, ["Updates", "Dnd"])
eq({ items: ["Dnd"], known: ["Dnd"] }, ["Updates", "ScreenRecording", "Dnd", "StayAwake", "Reminder", "Minimized"])
// Entries with settings and unknown ids pass through; duplicates and blanks are dropped.
eq({ items: [{ id: "Updates", x: 1 }, "Plugin", "", "Updates", null] }, [{ id: "Updates", x: 1 }, "Dnd", "StayAwake", "Plugin"])
// The older `indicators` key works like `items`.
eq({ indicators: ["Updates", "ScreenRecording", "Reminder", "Minimized"] }, shipped)
console.log("indicators model ok")
