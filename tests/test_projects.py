import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "projects.py"
spec = importlib.util.spec_from_file_location("projects", SOURCE)
projects = importlib.util.module_from_spec(spec)
spec.loader.exec_module(projects)


class DiscoveryTest(unittest.TestCase):
    def test_discovery_contract_and_json_transport(self):
        with tempfile.TemporaryDirectory() as fixture:
            home = Path(fixture) / "home"
            root = home / "Projects"
            expected = [root / "alpha", root / ".hidden", home / ".agents",
                        home / "work" / "outer", home / "worktree",
                        home / "a space\tand\n雪"]
            for path in expected:
                path.mkdir(parents=True)
            for path in expected[2:]:
                (path / ".git").touch()
            (home / ".git").touch()
            for path in [home / "work/outer/nested/.git", home / "node_modules/no/.git",
                         home / ".cache/no/.git", home / ".local/no/.git",
                         home / "go/pkg/no/.git", root / "alpha/nested/.git"]:
                path.mkdir(parents=True)
            linked = Path(fixture) / "linked"
            linked.mkdir()
            (root / "link-a").symlink_to(linked, target_is_directory=True)
            (root / "link-b").symlink_to(linked, target_is_directory=True)
            (home / "external-link").symlink_to(linked, target_is_directory=True)
            (root / "broken").symlink_to(Path(fixture) / "missing")
            output = subprocess.check_output([sys.executable, str(SOURCE), "scan",
                                              "--home", str(home), "--root", str(root)], text=True)
            rows = [json.loads(line) for line in output.splitlines()]
            self.assertEqual({r["path"] for r in rows}, {str(p) for p in expected} | {str(linked)})
            self.assertEqual(len(rows), 7)
            self.assertEqual([r["name"] for r in rows[:3]], [".hidden", "alpha", "link-a"])
            self.assertTrue(all(r["primary"] for r in rows[:3]))
            self.assertEqual(next(r for r in rows if r["name"] == ".agents")["displayPath"], "~/.agents")

    def test_all_markers(self):
        with tempfile.TemporaryDirectory() as fixture:
            home = Path(fixture)
            for marker in projects.PROJECT_MARKERS:
                (home / marker[1:] / marker).mkdir(parents=True)
            self.assertEqual(len(list(projects.discover(str(home), str(home / "Projects")))), 7)

    def test_absent_roots_and_symlink_loop(self):
        with tempfile.TemporaryDirectory() as fixture:
            home = Path(fixture)
            (home / "loop").symlink_to(home, target_is_directory=True)
            self.assertEqual(list(projects.discover(str(home), str(home / "missing"))), [])

    def test_launch_arguments_are_literal_and_cwd_is_explicit(self):
        with tempfile.TemporaryDirectory(prefix="project '$(literal) ") as path:
            self.assertEqual(projects.launch_command("terminal", path, []),
                             ["uwsm-app", "--", "xdg-terminal-exec", "--dir=" + path])
            self.assertEqual(projects.launch_command("editor", path, ["code", "--new-window"]),
                             ["uwsm-app", "--", "code", "--new-window", path])
            with self.assertRaises(ValueError):
                projects.launch_command("editor", path, "code")
        with self.assertRaises(ValueError):
            projects.launch_command("terminal", path, [])

    def test_missing_editor_reports_error_without_launching(self):
        with tempfile.TemporaryDirectory() as path:
            result = subprocess.run(
                [sys.executable, str(SOURCE), "launch", "--action", "editor", "--path", path,
                 "--editor-json", '["nulifyer-picker-nonexistent-editor"]'],
                capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("Command not found", result.stderr)


if __name__ == "__main__":
    unittest.main()
