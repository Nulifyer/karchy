#!/usr/bin/env python3
"""Install this folder as an Omarchy or karchy plugin and bind Ctrl+Alt+P."""

from datetime import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

PLUGIN_ID = "nulifyer.project-picker"
BEGIN = "-- BEGIN nulifyer.project-picker"
END = "-- END nulifyer.project-picker"


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def copy_if_changed(source, destination):
    if Path(destination).is_file() and Path(source).read_bytes() == Path(destination).read_bytes():
        return str(destination)
    return shutil.copy2(source, destination)


def desktop():
    """The shell this runs under: karchy (Omarchy's shell under its own names) or Omarchy."""
    if os.environ.get("KARCHY_PATH") or shutil.which("karchy-shell"):
        return "karchy"
    return "omarchy"


def main():
    source = Path(__file__).resolve().parent
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    name = desktop()
    cli, shell_cli = name, name + "-shell"
    destination = config / name / "plugins" / PLUGIN_ID
    bindings = config / "hypr/bindings.lua"
    for command in ["python3", cli, shell_cli, "hyprctl", "uwsm-app", "xdg-terminal-exec"]:
        if shutil.which(command) is None:
            raise SystemExit("Required command not found: " + command)
    run(cli, "plugin", "validate", str(source))
    if run(shell_cli, "shell", "ping") != "ok":
        raise SystemExit("The " + name + " shell is not running.")

    # Inspect live bindings before touching the configuration.
    live_bindings = json.loads(run("hyprctl", "-j", "binds"))
    existing = bindings.read_text() if bindings.exists() else ""
    previous_block = re.search(re.escape(BEGIN) + r".*?" + re.escape(END), existing, flags=re.S)
    ctrl_alt_p = [bind for bind in live_bindings if bind.get("modmask") == 12
                  and bind.get("key", "").upper() == "P"]
    # Hyprland's Lua bindings report a callback number as `arg`, so a picker
    # binding is also known by its description.
    def opens_picker(bind):
        return PLUGIN_ID in bind.get("arg", "") or bind.get("description") == "Project picker"
    conflicts = [bind for bind in ctrl_alt_p if not opens_picker(bind)]
    # The desktop's own configuration may already bind the picker (karchy
    # lists Ctrl+Alt+P as its own). A second binding would toggle it twice.
    bound_elsewhere = not previous_block and any(opens_picker(bind) for bind in ctrl_alt_p)
    unbind = bool(conflicts) or bool(previous_block and 'hl.unbind(' in previous_block.group())
    block = BEGIN + "\n"
    if unbind:
        block += 'hl.unbind("CTRL + ALT + P")\n'
    block += 'o.bind("CTRL + ALT + P", "Project picker",\n'
    block += '  "' + shell_cli + ' shell toggle nulifyer.project-picker \'{}\'")\n' + END
    if previous_block:
        updated = existing[:previous_block.start()] + block + existing[previous_block.end():]
    else:
        updated = existing.rstrip() + "\n\n" + block + "\n"

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = Path.home() / ".local/state/nulifyer.project-picker/backups" / stamp
    backup.mkdir(parents=True)
    for path in [bindings, config / name / "shell.json"]:
        if path.exists():
            shutil.copy2(path, backup / path.name)
    code_changed = destination.exists() and source != destination and any(
        not (destination / name).exists()
        or (source / name).read_bytes() != (destination / name).read_bytes()
        for name in ["ProjectPicker.qml", "Search.js"])
    if destination.exists() and source != destination:
        shutil.copytree(destination, backup / "plugin", ignore=shutil.ignore_patterns(".git", "__pycache__"))
    if source != destination:
        shutil.copytree(source, destination, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns(".git", "__pycache__", "*.pyc"),
                        copy_function=copy_if_changed)
    run(cli, "plugin", "validate", str(destination))
    run(shell_cli, "shell", "rescanPlugins")
    run(cli, "plugin", "enable", PLUGIN_ID)
    if code_changed:
        print("Restarting the " + name + " shell to load the updated QML.", flush=True)
        run(cli, "restart", "shell")
    if bound_elsewhere:
        print("Installed: " + str(destination))
        print("Shortcut: Ctrl+Alt+P (already bound by your desktop configuration)")
        print("Backups: " + str(backup))
        return
    bindings.parent.mkdir(parents=True, exist_ok=True)
    bindings.write_text(updated)
    run("hyprctl", "reload")
    errors = run("hyprctl", "configerrors")
    if errors:
        # Roll back our binding edit if the compositor rejects its configuration.
        bindings.write_text(existing)
        run("hyprctl", "reload")
        raise SystemExit("Hyprland reported configuration errors; binding edit rolled back:\n" + errors)
    for conflict in conflicts:
        print("Replaced Ctrl+Alt+P binding: " + conflict.get("description", "") + " " + conflict.get("arg", ""))
    print("Installed: " + str(destination))
    print("Shortcut: Ctrl+Alt+P")
    print("Backups: " + str(backup))


if __name__ == "__main__":
    main()
