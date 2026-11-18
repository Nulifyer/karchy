#!/usr/bin/env python3
"""Streaming project discovery and argument-safe desktop launches."""

import argparse
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys

PROJECT_MARKERS = {".devcontainer", ".git", ".hg", ".idea", ".jj", ".svn", ".vscode"}
IGNORED_DIRECTORY_NAMES = {
    ".android", ".bun", ".cache", ".cargo", ".devcontainer", ".dotnet",
    ".git", ".gradle", ".hg", ".idea", ".jj", ".local", ".npm", ".nuget",
    ".pnpm-store", ".pki", ".pytest_cache", ".ruff_cache", ".rustup", ".ssh",
    ".steam", ".svn", ".t3", ".tmp", ".tox", ".var", ".venv", ".vscode",
    ".vscode-oss", ".vscode-oss-shared", ".vscode-shared", ".yarn",
    "__pycache__", "build", "cache", "caches", "dist", "node_modules",
    "out", "target", "vendor", "venv",
}


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
    """(is_project, children); a linked checkout is neither nor descended."""
    children = []
    project = False
    try:
        with os.scandir(directory) as entries:
            for entry in entries:
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
            resolved = str(Path(path).resolve(strict=True))
        except (OSError, RuntimeError):
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
    if shutil.which(executable) is None:
        raise ValueError("Command not found: " + executable)


def start(command, cwd):
    # Keep the application independent of the shell's plugin lifecycle.
    # exec errors in the launcher itself remain visible to the caller.
    subprocess.Popen(command, cwd=cwd, start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    scan = commands.add_parser("scan")
    scan.add_argument("--home", default=os.path.expanduser("~"))
    scan.add_argument("--root", default=os.environ.get("Z_PROJECTS_ROOT") or "~/Projects")
    launch = commands.add_parser("launch")
    launch.add_argument("--action", choices=["editor", "terminal"], required=True)
    launch.add_argument("--path", required=True)
    launch.add_argument("--editor-json", default='["code"]')
    create = commands.add_parser("create", help="create a project folder and open it in the editor")
    create.add_argument("--root", default=os.environ.get("Z_PROJECTS_ROOT") or "~/Projects")
    create.add_argument("--name", required=True)
    create.add_argument("--editor-json", default='["code"]')
    args = parser.parse_args()
    try:
        if args.command == "scan":
            if not os.path.isdir(os.path.expanduser(args.home)):
                raise ValueError("Home directory does not exist: " + args.home)
            for row in discover(args.home, args.root):
                print(json.dumps(row, ensure_ascii=True), flush=True)
        elif args.command == "create":
            editor = json.loads(args.editor_json)
            path = create_project(args.root, args.name, editor)
            start(launch_command("editor", path, editor), path)
            print(path)
        else:
            command = launch_command(args.action, args.path, json.loads(args.editor_json))
            require_command("xdg-terminal-exec" if args.action == "terminal" else json.loads(args.editor_json)[0])
            start(command, args.path)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    raise SystemExit(main())
