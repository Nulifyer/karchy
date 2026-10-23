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
    ".steam", ".svn", ".tmp", ".tox", ".var", ".venv", ".vscode",
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


def inspect_directory(directory):
    children = []
    try:
        with os.scandir(directory) as entries:
            for entry in entries:
                if entry.name in PROJECT_MARKERS:
                    return True, []
                try:
                    if entry.is_dir(follow_symlinks=False):
                        children.append(entry.path)
                except OSError:
                    continue
    except OSError:
        return False, []
    return False, children


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


def launch_command(action, path, editor):
    if not os.path.isdir(path):
        raise ValueError("Project directory no longer exists: " + path)
    if action == "terminal":
        return ["uwsm-app", "--", "xdg-terminal-exec", "--dir=" + path]
    if not isinstance(editor, list) or not editor or any(
            not isinstance(arg, str) or not arg or "\0" in arg for arg in editor):
        raise ValueError("Editor must be a nonempty array of command arguments.")
    return ["uwsm-app", "--", *editor, path]


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
    args = parser.parse_args()
    try:
        if args.command == "scan":
            if not os.path.isdir(os.path.expanduser(args.home)):
                raise ValueError("Home directory does not exist: " + args.home)
            for row in discover(args.home, args.root):
                print(json.dumps(row, ensure_ascii=True), flush=True)
        else:
            command = launch_command(args.action, args.path, json.loads(args.editor_json))
            executable = "xdg-terminal-exec" if args.action == "terminal" else json.loads(args.editor_json)[0]
            if shutil.which(executable) is None:
                raise ValueError("Command not found: " + executable)
            # Keep the application independent of the shell's plugin lifecycle.
            # exec errors in the launcher itself remain visible to the caller.
            subprocess.Popen(command, cwd=args.path, start_new_session=True,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    raise SystemExit(main())
