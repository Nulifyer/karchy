#!/usr/bin/env python3
"""karchy-settings-keybindings: the pure logic (keys, resolving the record
into rows, the rules a change writes, the generated Lua), and, where a lua
interpreter is installed, karchy's real Lua layer under a stand-in Hyprland:
what it binds agrees with what the command resolves and predicts.

Run: python3 tests/keybindings.py [repository]
"""
import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent)
sys.dont_write_bytecode = True
loader = importlib.machinery.SourceFileLoader("kb", str(REPO / "bin/karchy-settings-keybindings"))
kb = importlib.util.module_from_spec(importlib.util.spec_from_loader("kb", loader))
loader.exec_module(kb)

checks = 0


def eq(got, want, what=""):
    global checks
    checks += 1
    assert got == want, f"{what}\n  got:  {got!r}\n  want: {want!r}"


def refused(call, containing):
    global checks
    checks += 1
    try:
        call()
    except kb.Refused as refusal:
        assert containing in str(refusal), f"refused with {str(refusal)!r}, wanted {containing!r}"
        return
    raise AssertionError(f"not refused: wanted {containing!r}")


def bind(keys, name, what="", layer="default", **more):
    return dict({"op": "bind", "keys": keys, "description": name, "what": what or name.lower(), "layer": layer}, **more)


DEFAULTS = [
    bind("ALT + F4", "Close window", group="Windows"),
    bind("ALT + TAB", "Focus on next window", group="Windows"),
    bind("ALT + TAB", "Reveal active window on top", group="Windows"),
    bind("SUPER + mouse:272", "Move window", group="Windows", mouse=True),
    bind("SUPER + code:10", "Switch to workspace 1", group="Workspaces and monitors"),
    bind("SUPER + code:20", "Make window narrower", group="Windows"),
    bind("SUPER + SPACE", "Menu", "menu=root", group="Shell and system"),
    bind("SUPER + ESCAPE", "Power menu", "menu=system", group="Shell and system"),
    bind("XF86PowerOff", "Power menu", "menu=system", group="Shell and system", locked=True),
    bind("SUPER + K", "Keybindings", "karchy-settings keybindings", group="Shell and system"),
    bind("SUPER + RETURN", "Terminal", "karchy-launch-terminal", group="Apps"),
    bind("SUPER + E", "File manager", "karchy-launch-files", group="Apps"),
    {"op": "bind", "keys": "switch:on:Lid Switch", "what": "karchy-system-lid-close", "layer": "default", "group": "Laptop lid", "locked": True},
    bind("CTRL + ALT + P", "Project picker", "karchy-shell shell toggle karchy.project-picker", layer="addon", owner="project-picker", group="Project picker"),
]
KEYMAP = dict(kb.FALLBACK_KEYCODES)


def rows_for(rules, user=()):
    return kb.resolve(kb.predict(DEFAULTS + list(user), rules), KEYMAP)


def row(rows, action, keys=None):
    return kb.find_row(rows, action, keys)


def change(rules, user, action, keys, from_keys=None, mode=""):
    rows, _ = rows_for(rules, user)
    target = row(rows, action, from_keys)
    numbered = kb.numbered(rules)
    return kb.unnumbered(kb.change_rules(kb.with_conflicts(numbered, rows, keys, KEYMAP, target, mode) if keys else numbered, target, keys))


# ---- keys
eq(kb.normalize("SUPER + Shift + t"), "super+shift+t")
eq(kb.normalize("shift+SUPER+T"), "super+shift+t")
eq(kb.canonical("super+shift+t"), "SUPER + SHIFT + T")
eq(kb.canonical("ctrl + alt + code:20"), "CTRL + ALT + code:20")
eq(kb.canonical("XF86AudioMute"), "XF86AudioMute")
eq(kb.identity("SUPER + code:20", KEYMAP), kb.identity("super + MINUS", KEYMAP), "a key by code and by name")
eq(kb.labels("SUPER + SHIFT + code:10", KEYMAP), ["Super", "Shift", "1"])
eq(kb.labels("SUPER + RETURN", KEYMAP), ["Super", "Enter"])
eq(kb.labels("XF86AudioRaiseVolume", KEYMAP), ["Volume up"])
eq(kb.labels("SUPER + mouse:272", KEYMAP), ["Super", "Left mouse"])
eq(kb.valid_keys("SUPER + T"), True)
eq(kb.valid_keys("SUPER + "), False)
eq(kb.valid_keys('SUPER + "); os.exit()'), False)

# ---- the defaults resolve into one row each
rows, stale = rows_for([])
eq(len(rows), len(DEFAULTS) - 1, "the lid switch is no row")
eq(stale, [])
eq([r["conflicts"] for r in rows if r["conflicts"]], [], "karchy's own Alt+Tab pair is no conflict")
eq(row(rows, "Terminal")["state"], "default")
eq(row(rows, "Terminal")["source"], "karchy")
eq(row(rows, "Project picker")["source"], "Project picker")
eq(row(rows, "Project picker")["layer"], "addon")
eq(kb.source_label({"layer": "addon", "owner": "50-karchy-project-picker"}), "Project picker", "the file as the package installs it")
eq(bool(row(rows, "Move window")["readOnly"]), True, "mouse bindings are shown, not edited")
eq(row(rows, "Switch to workspace 1")["labels"], ["Super", "1"])
refused(lambda: row(rows, "Power menu"), "Say which keys")
eq(row(rows, "Power menu", "XF86PowerOff")["keys"], "XF86PowerOff")
refused(lambda: row(rows, "No such thing"), "No action is called")

# ---- changing a default: the old keys unbound, the new ones bound (as VS Code writes it)
rules = change([], [], "Terminal", "super + t")
eq(rules, [{"unbind": "SUPER + RETURN", "action": "Terminal"}, {"bind": "SUPER + T", "action": "Terminal", "replaces": "SUPER + RETURN"}])
rows, _ = rows_for(rules)
terminal = row(rows, "Terminal")
eq((terminal["keys"], terminal["state"], terminal["source"], terminal["defaultKeys"]), ("SUPER + T", "changed", "Settings", "SUPER + RETURN"))
eq([(l["source"], l["keys"], l["state"]) for l in terminal["chain"]], [("karchy", "SUPER + RETURN", "replaced"), ("Settings", "SUPER + T", "wins")])
eq(terminal["chain"][0]["by"], "Settings")
eq(len(rows), len(DEFAULTS) - 1, "a changed binding is still one row")
# changing it again rewrites the same two rules, it doesn't pile up
rules = change(rules, [], "Terminal", "SUPER + SHIFT + RETURN")
eq(rules, [{"unbind": "SUPER + RETURN", "action": "Terminal"}, {"bind": "SUPER + SHIFT + RETURN", "action": "Terminal", "replaces": "SUPER + RETURN"}])
# the default's keys again is a reset: no rules left
eq(change(rules, [], "Terminal", "SUPER + RETURN"), [])
# reset deletes the person's rules rather than adding any
rows, _ = rows_for(rules)
eq(kb.unnumbered(kb.rules_without_row(kb.numbered(rules), row(rows, "Terminal"))), [])

# ---- removing, then binding again
rules = change([], [], "File manager", "")
eq(rules, [{"unbind": "SUPER + E", "action": "File manager"}])
rows, _ = rows_for(rules)
files = row(rows, "File manager")
eq((files["keys"], files["state"], files["labels"]), ("", "removed", []))
eq([(l["keys"], l["state"], l["by"]) for l in files["chain"]], [("SUPER + E", "removed", "Settings")])
rules = change(rules, [], "File manager", "SUPER + SHIFT + E")
eq(rules, [{"unbind": "SUPER + E", "action": "File manager"}, {"bind": "SUPER + SHIFT + E", "action": "File manager", "replaces": "SUPER + E"}])

# ---- one action off a key two actions share: the other stays
rules = change([], [], "Reveal active window on top", "")
rows, _ = rows_for(rules)
eq(row(rows, "Focus on next window")["keys"], "ALT + TAB")
eq(row(rows, "Reveal active window on top")["state"], "removed")

# ---- bindings of the person's own
custom = [{"bind": "SUPER + SHIFT + R", "description": "SSH", "command": "footclient ssh my-server"}]
rows, _ = rows_for(custom)
ssh = row(rows, "SSH")
eq((ssh["state"], ssh["custom"], ssh["group"], ssh["source"], ssh["what"]), ("added", True, "Your own", "Settings", "footclient ssh my-server"))
eq(change(custom, [], "SSH", "SUPER + CTRL + R"), [{"bind": "SUPER + CTRL + R", "description": "SSH", "command": "footclient ssh my-server"}], "edited in place")
eq(change(custom, [], "SSH", ""), [], "removed by deleting its rule")
# one more binding for an existing action is a row of its own
extra = [{"bind": "SUPER + SHIFT + SPACE", "action": "Menu"}]
rows, _ = rows_for(extra)
eq(sorted(r["keys"] for r in rows if r["action"] == "Menu"), ["SUPER + SHIFT + SPACE", "SUPER + SPACE"])
eq(row(rows, "Menu", "SUPER + SHIFT + SPACE")["state"], "added")

# ---- conflicts are found against the resolved set, by physical key
rows, _ = rows_for([])
eq([r["action"] for r in kb.conflicts_for(rows, "SUPER + e", KEYMAP)], ["File manager"])
eq([r["action"] for r in kb.conflicts_for(rows, "SUPER + minus", KEYMAP)], ["Make window narrower"], "minus is code:20")
refused(lambda: change([], [], "Terminal", "SUPER + E"), "also bound to \"File manager\"")
rules = change([], [], "Terminal", "SUPER + E", mode="replace")
eq(rules, [{"unbind": "SUPER + E", "action": "File manager"}, {"unbind": "SUPER + RETURN", "action": "Terminal"}, {"bind": "SUPER + E", "action": "Terminal", "replaces": "SUPER + RETURN"}])
rows, _ = rows_for(rules)
eq((row(rows, "Terminal")["keys"], row(rows, "File manager")["state"], row(rows, "Terminal")["conflicts"]), ("SUPER + E", "removed", []))
rules = change([], [], "Terminal", "SUPER + E", mode="keep")
rows, _ = rows_for(rules)
eq((row(rows, "Terminal")["conflicts"], row(rows, "File manager")["conflicts"]), (["File manager"], ["Terminal"]), "keeping both shows on both rows")
# replacing takes a changed binding's rules out, and a rule edited in the same step is still found
both = custom + change([], [], "Terminal", "SUPER + T")
rules = change(both, [], "SSH", "SUPER + T", mode="replace")
eq(rules, [{"bind": "SUPER + T", "description": "SSH", "command": "footclient ssh my-server"}, {"unbind": "SUPER + RETURN", "action": "Terminal"}])

# ---- never without the menu, a terminal or this page
rows, _ = rows_for([])
for action, label in (("Menu", "the menu"), ("Terminal", "a terminal"), ("Keybindings", "Settings › Keybindings")):
    after, _ = rows_for(change([], [], action, ""))
    refused(lambda: kb.check_essentials(rows, after), "no key for " + label)
after, _ = rows_for(change(extra, [], "Menu", "", "SUPER + SPACE"))
kb.check_essentials(rows_for(extra)[0], after)  # another binding for the menu remains: allowed
after, _ = rows_for(change([], [], "Terminal", "SUPER + T"))
kb.check_essentials(rows, after)  # moved, not removed

# ---- the person's own bindings.lua wins, and shows as read-only
USER = "/home/someone/.config/hypr/bindings.lua"
mine = [
    {"op": "unbind", "keys": "SUPER + E", "layer": "user", "owner": USER},
    bind("SUPER + E", "File manager", "karchy-launch-files ~/Projects", layer="user", owner=USER),
    bind("SUPER + SHIFT + R", "SSH", "footclient ssh my-server", layer="user", owner=USER),
]
rows, _ = rows_for([], mine)
files = row(rows, "File manager")
eq((files["layer"], files["source"], files["state"], files["what"]), ("user", "your bindings.lua", "changed", "karchy-launch-files ~/Projects"))
eq([(l["source"], l["state"]) for l in files["chain"]], [("karchy", "replaced"), ("your bindings.lua", "wins")])
eq("which wins" in files["readOnly"], True)
eq((row(rows, "SSH")["state"], row(rows, "SSH")["group"]), ("yours", "Your own"))
refused(lambda: change([], mine, "File manager", "SUPER + F"), "can't be changed here")
# all four layers on one action: the add-on's default, a Settings change, and bindings.lua on top
four = [
    {"op": "unbind", "keys": "CTRL + ALT + O", "layer": "user", "owner": USER},
    bind("SUPER + P", "Project picker", "karchy-shell shell toggle karchy.project-picker", layer="user", owner=USER),
]
rules = change([], [], "Project picker", "CTRL + ALT + O")
rows, _ = rows_for(rules, four)
picker = row(rows, "Project picker")
eq([(l["source"], l["keys"], l["state"]) for l in picker["chain"]],
   [("Project picker", "CTRL + ALT + P", "replaced"), ("Settings", "CTRL + ALT + O", "replaced"), ("your bindings.lua", "SUPER + P", "wins")])
eq([l.get("by") for l in picker["chain"]], ["Settings", "your bindings.lua", None])
eq((picker["keys"], picker["layer"], picker["group"]), ("SUPER + P", "user", "Project picker"))
# their rebind of a default keeps the default's history, even with a Settings binding on the same keys;
# that Settings binding stays a row (removed), so its rule can be deleted
echo = [{"bind": "SUPER + E", "description": "Echo", "command": "true"}]
rows, _ = rows_for(echo, mine)
eq([(l["source"], l["state"]) for l in row(rows, "File manager")["chain"]], [("karchy", "replaced"), ("your bindings.lua", "wins")])
eq((row(rows, "File manager")["group"], row(rows, "Echo")["state"], row(rows, "Echo")["readOnly"], row(rows, "Echo")["firstKeys"]), ("Apps", "removed", "", "SUPER + E"))
eq(row(rows, "Echo")["chain"][0]["by"], "your bindings.lua")
eq(change(echo, mine, "Echo", "", "SUPER + E"), [])
# a default the person's file unbinds, with nothing in its place
rows, _ = rows_for([], [{"op": "unbind", "keys": "SUPER + K", "layer": "user", "owner": USER}])
eq((row(rows, "Keybindings")["state"], row(rows, "Keybindings")["chain"][0]["by"]), ("removed", "your bindings.lua"))

# ---- a rule whose action is gone does nothing and is reported
gone = [{"unbind": "SUPER + J", "action": "Gone"}, {"bind": "SUPER + J", "action": "Gone", "replaces": "SUPER + G"}]
rows, stale = rows_for(gone)
eq(([s["rule"] for s in stale], len(rows)), ([1, 2], len(DEFAULTS) - 1))

# ---- the generated Lua: nothing in a name or a command can end a string
tricky = [{"bind": "SUPER + X", "description": 'Say "hi"\\ é', "command": 'printf "a\\nb"; echo \']]\'\n'}]
lua = kb.generate_lua(tricky)
eq('command = "printf \\"a\\\\nb\\"; echo \']]\'\\010"' in lua, True, lua)
eq('description = "Say \\"hi\\"\\\\ \\195\\169"' in lua, True, lua)
eq(kb.generate_lua([]).count("{ "), 0)

# ---- keybindings.json: a broken file is reported, never overwritten; junk rules are dropped
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "keybindings.json"
    path.write_text("{ not json")
    eq((kb.read_rules(path)[0], "not valid JSON" in kb.read_rules(path)[1]), ([], True))
    path.write_text(json.dumps({"version": 1, "rules": [{"bind": "SUPER + T", "action": "Terminal", "extra": 1}, {"bind": 'x"); os.exit()', "action": "A"}, "junk", {"unbind": "SUPER + E"}]}))
    eq(kb.read_rules(path), ([{"bind": "SUPER + T", "action": "Terminal"}, {"unbind": "SUPER + E"}], ""))
    eq(kb.read_rules(Path(tmp) / "missing.json"), ([], ""))

# ---- karchy's real Lua layer under a stand-in Hyprland
lua_bin = shutil.which("lua")
if lua_bin:
    def run_layers(rules, user_lua, break_settings=False):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home"
            (home / ".config/hypr").mkdir(parents=True)
            (home / ".config/hypr/bindings.lua").write_text(user_lua)
            state = home / ".local/state/karchy/hypr"
            state.mkdir(parents=True)
            if rules or break_settings:
                (state / "keybindings.lua").write_text("this is not lua(" if break_settings else kb.generate_lua(rules))
            run = Path(tmp) / "run"
            run.mkdir()
            env = dict(os.environ, KARCHY_PATH=str(REPO), HOME=str(home), XDG_STATE_HOME=str(home / ".local/state"), XDG_RUNTIME_DIR=str(run))
            out = subprocess.run([lua_bin, str(REPO / "tests/keybindings-layers.lua")], env=env, capture_output=True, text=True)
            assert out.returncode == 0, out.stderr
            live = sorted(tuple(line.split("\t")) for line in out.stdout.splitlines())
            return json.loads((run / "karchy-keybindings.json").read_text()), live

    def bound(rows):
        return sorted((kb.normalize(r["keys"]), r["action"]) for r in rows if r["keys"])

    def with_lid(rows, live):
        # the lid switches are bound but are no rows
        return sorted(rows + [pair for pair in live if pair[0].startswith("switch:")])

    trace, live = run_layers([], "")
    eq(trace["errors"], [])
    rows, _ = kb.resolve(trace["events"], KEYMAP)
    eq(with_lid(bound(rows), live), [pair for pair in live], "the defaults: every bound key is a row")
    eq({e["layer"] for e in trace["events"]}, {"default"})
    eq({r["group"] for r in rows} >= {"Windows", "Workspaces and monitors", "Shell and system", "Apps", "Capture", "Hardware keys", "Clipboard"}, True)
    eq(row(rows, "Terminal")["what"], "karchy-launch-terminal")
    eq(row(rows, "Menu")["what"], "menu=root")
    eq(kb.essential_bindings(rows), {"menu": 1, "terminal": 1, "keybindings": 1}, "the defaults bind all three essentials")

    rules = [
        {"unbind": "SUPER + RETURN", "action": "Terminal"}, {"bind": "SUPER + T", "action": "Terminal", "replaces": "SUPER + RETURN"},
        {"unbind": "SUPER + T", "action": "Toggle window floating/tiling"},
        {"unbind": "ALT + TAB", "action": "Reveal active window on top"},
        {"bind": "SUPER + SHIFT + R", "description": 'Say "hi"', "command": 'notify-send "hi\\there"'},
        {"unbind": "SUPER + J", "action": "Gone"},
    ]
    user_lua = 'o.rebind("SUPER + E", "File manager", "karchy-launch-files ~/Projects")\nhl.unbind("SUPER + K")\no.bind("SUPER + SHIFT + K", "Keybindings", "karchy-settings keybindings")\nhl.bind("SUPER + F9", hl.dsp.exec_cmd("true"), { description = "Raw bind" })\n'
    trace, live = run_layers(rules, user_lua)
    eq(trace["errors"], [])
    rows, stale = kb.resolve(trace["events"], KEYMAP)
    eq(with_lid(bound(rows), live), live, "after Settings rules and a bindings.lua: the rows are what is bound")
    eq([s["rule"] for s in stale], [6])
    eq([(l["source"], l["keys"], l["state"]) for l in row(rows, "Terminal")["chain"]], [("karchy", "SUPER + RETURN", "replaced"), ("Settings", "SUPER + T", "wins")])
    eq(row(rows, "Focus on next window")["keys"], "ALT + TAB", "the other action on Alt+Tab stays bound")
    eq(("alt+tab", "Focus on next window") in live and ("alt+tab", "Reveal active window on top") not in live, True)
    eq([(l["source"], l["state"]) for l in row(rows, "File manager")["chain"]], [("karchy", "replaced"), ("your bindings.lua", "wins")])
    eq([(l["source"], l["keys"], l["state"]) for l in row(rows, "Keybindings")["chain"]], [("karchy", "SUPER + K", "replaced"), ("your bindings.lua", "SUPER + SHIFT + K", "wins")])
    eq((row(rows, "Raw bind")["layer"], row(rows, 'Say "hi"')["what"]), ("user", 'notify-send "hi\\there"'))
    # the command's prediction is what the Lua layer did
    strip = lambda rs: [{k: v for k, v in r.items() if k != "_entries"} for r in rs]
    base, _ = run_layers([], user_lua)
    predicted, predicted_stale = kb.resolve(kb.predict(base["events"], rules), KEYMAP)
    eq(strip(predicted), strip(rows), "predict() agrees with karchy/hypr/keys.lua")
    eq(predicted_stale, stale)

    # a generated file that doesn't load costs the changes, not the defaults
    trace, live = run_layers([], "", break_settings=True)
    eq(len(trace["errors"]), 1)
    eq("could not be loaded" in trace["errors"][0], True)
    rows, _ = kb.resolve(trace["events"], KEYMAP)
    eq(kb.essential_bindings(rows), {"menu": 1, "terminal": 1, "keybindings": 1})
else:
    print("keybindings: no lua interpreter, the Lua layer was not run")

print(f"keybindings: {checks} checks passed")
