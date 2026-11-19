#!/usr/bin/env python3
"""Streaming project discovery and argument-safe desktop launches."""

import json
import os
import signal
import sys

# A scan runs on every opening, so it imports only what it needs; argparse,
# pathlib, shutil and subprocess together cost more than the walk on a small
# home folder.

PROJECT_MARKERS = {".devcontainer", ".git", ".hg", ".idea", ".jj", ".svn", ".vscode"}
IGNORED_DIRECTORY_NAMES = {
    ".android", ".bun", ".cache", ".cargo", ".claude", ".codex",
    ".devcontainer", ".dotnet", ".git", ".gradle", ".hg", ".idea", ".jj",
    ".local", ".npm", ".nuget", ".nv", ".pnpm-store", ".pki", ".pytest_cache",
    ".ruff_cache", ".rustup", ".ssh", ".steam", ".svn", ".t3", ".tmp", ".tox",
    ".var", ".venv", ".vscode",
    ".vscode-oss", ".vscode-oss-shared", ".vscode-shared", ".yarn",
    "__pycache__", "build", "cache", "caches", "dist", "node_modules",
    "out", "target", "vendor", "venv", ".wine",
}
# Chromium writes this file at the root of every profile, so it marks browser
# and Electron app state (Brave, VS Code, Obsidian, ...) wherever it lives.
APP_PROFILE_MARKER = "Local State"


def directories(directory, follow_symlinks=False):
    try:
        with os.scandir(directory) as entries:
            for entry in entries:
                try:
                    if entry.is_dir(follow_symlinks=follow_symlinks):
                        yield entry.path
                except OSError:
                    continue
    except OSError:
        return


def linked_checkout(entry):
    """True for a git linked worktree or a secondary jj workspace.

    Coding agents and `git worktree add` leave these copies of a project
    elsewhere in the home folder; the picker lists the main checkout only.
    """
    try:
        if entry.name == ".git" and entry.is_file(follow_symlinks=False):
            with open(entry.path, encoding="utf-8", errors="replace") as file:
                gitdir = file.readline().strip()
            return gitdir.startswith("gitdir:") and "/worktrees/" in gitdir
        if entry.name == ".jj" and entry.is_dir(follow_symlinks=False):
            return os.path.isfile(os.path.join(entry.path, "repo"))
    except OSError:
        pass
    return False


def inspect_directory(directory):
    """(is_project, children); a linked checkout or app profile is neither."""
    children = []
    project = False
    try:
        with os.scandir(directory) as entries:
            for entry in entries:
                if entry.name == APP_PROFILE_MARKER:
                    return False, []
                if entry.name in PROJECT_MARKERS:
                    if linked_checkout(entry):
                        return False, []
                    project = True
                    continue
                if project:
                    continue
                try:
                    if entry.is_dir(follow_symlinks=False):
                        children.append(entry.path)
                except OSError:
                    continue
    except OSError:
        return False, []
    return (True, []) if project else (False, children)


def discover(home, projects_root):
    home = os.path.abspath(os.path.expanduser(home))
    projects_root = os.path.abspath(os.path.expanduser(projects_root))
    seen = set()

    def candidate(path, primary):
        try:
            resolved = os.path.realpath(path, strict=True)
        except OSError:
            return None
        if resolved in seen:
            return None
        seen.add(resolved)
        display_path = resolved
        if resolved == home:
            display_path = "~"
        elif resolved.startswith(home + os.sep):
            display_path = "~/" + resolved[len(home) + 1:]
        return {"name": os.path.basename(path), "path": resolved,
                "displayPath": display_path, "primary": primary}

    for path in sorted(directories(projects_root, follow_symlinks=True)):
        row = candidate(path, True)
        if row:
            yield row

    excluded = {projects_root, os.path.realpath(projects_root), os.path.join(home, "go", "pkg")}
    stack = list(directories(home))
    while stack:
        path = stack.pop()
        if path in excluded or os.path.basename(path) in IGNORED_DIRECTORY_NAMES:
            continue
        project, children = inspect_directory(path)
        if project:
            row = candidate(path, False)
            if row:
                yield row
        else:
            stack.extend(children)


def check_editor(editor):
    if not isinstance(editor, list) or not editor or any(
            not isinstance(arg, str) or not arg or "\0" in arg for arg in editor):
        raise ValueError("Editor must be a nonempty array of command arguments.")


def launch_command(action, path, editor):
    if not os.path.isdir(path):
        raise ValueError("Project directory no longer exists: " + path)
    if action == "terminal":
        return ["uwsm-app", "--", "xdg-terminal-exec", "--dir=" + path]
    check_editor(editor)
    return ["uwsm-app", "--", *editor, path]


def project_folder(projects_root, name):
    """The new project's folder: one plain name directly inside the root."""
    name = name.strip()
    if not name:
        raise ValueError("Type a name for the project.")
    if name in {".", ".."} or "/" in name or "\0" in name:
        raise ValueError("A project name can't be . or .. or contain a slash.")
    if len(os.fsencode(name)) > 255:
        raise ValueError("That name is too long for a folder.")
    root = os.path.abspath(os.path.expanduser(projects_root))
    return os.path.join(root, name)


def create_project(projects_root, name, editor):
    """Create the folder and return it; refuse one that already exists.

    The editor is checked first, so a missing editor leaves nothing behind.
    """
    path = project_folder(projects_root, name)
    check_editor(editor)
    require_command(editor[0])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        os.mkdir(path)
    except FileExistsError:
        raise ValueError(display(path) + " already exists. Pick it from the list instead.") from None
    return path


def display(path):
    home = os.path.expanduser("~")
    return "~" + path[len(home):] if path.startswith(home + os.sep) else path


def require_command(executable):
    import shutil
    if shutil.which(executable) is None:
        raise ValueError("Command not found: " + executable)


def start(command, cwd):
    # Keep the application independent of the shell's plugin lifecycle.
    # exec errors in the launcher itself remain visible to the caller.
    import subprocess
    subprocess.Popen(command, cwd=cwd, start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL)


COMMANDS = {
    "scan": {"--home", "--root"},
    "launch": {"--action", "--path", "--editor-json"},
    "create": {"--root", "--name", "--editor-json"},
}
USAGE = """usage: projects.py scan [--home DIR] [--root DIR]
       projects.py launch --action editor|terminal --path DIR [--editor-json JSON]
       projects.py create --name NAME [--root DIR] [--editor-json JSON]"""


def parse_args(argv):
    """The command and its options; takes --opt VALUE and --opt=VALUE."""
    if not argv or argv[0] not in COMMANDS:
        raise ValueError(USAGE)
    command, allowed, options = argv[0], COMMANDS[argv[0]], {}
    rest = iter(argv[1:])
    for arg in rest:
        name, equals, value = arg.partition("=")
        if name not in allowed:
            raise ValueError("Unknown option: " + arg + "\n" + USAGE)
        if not equals:
            value = next(rest, None)
            if value is None:
                raise ValueError("Option needs a value: " + name)
        options[name[2:].replace("-", "_")] = value
    root = os.environ.get("Z_PROJECTS_ROOT") or "~/Projects"
    options.setdefault("home", os.path.expanduser("~"))
    options.setdefault("root", root)
    options.setdefault("editor_json", '["code"]')
    if command == "launch" and options.get("action") not in {"editor", "terminal"}:
        raise ValueError("--action must be editor or terminal.")
    if command == "launch" and "path" not in options:
        raise ValueError("--path is required.")
    if command == "create" and "name" not in options:
        raise ValueError("--name is required.")
    return command, options


def main():
    try:
        command, args = parse_args(sys.argv[1:])
        if command == "scan":
            if not os.path.isdir(os.path.expanduser(args["home"])):
                raise ValueError("Home directory does not exist: " + args["home"])
            for row in discover(args["home"], args["root"]):
                print(json.dumps(row, ensure_ascii=True), flush=True)
        elif command == "create":
            editor = json.loads(args["editor_json"])
            path = create_project(args["root"], args["name"], editor)
            start(launch_command("editor", path, editor), path)
            print(path)
        else:
            editor = json.loads(args["editor_json"])
            command = launch_command(args["action"], args["path"], editor)
            require_command("xdg-terminal-exec" if args["action"] == "terminal" else editor[0])
            start(command, args["path"])
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    raise SystemExit(main())
