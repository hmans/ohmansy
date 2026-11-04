"""Check desktop helper decisions without touching a running desktop."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "nix/modules/desktop/actions.sh"


@unittest.skipUnless(shutil.which("jq"), "jq is required")
class DesktopActionsTest(unittest.TestCase):
    def run_action(self, action, windows, *args):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root / "windows.json"
            fixture.write_text(json.dumps(windows))
            log = root / "calls"
            niri = root / "niri"
            niri.write_text('#!/bin/sh\nif [ "$2" = "--json" ]; then\n'
                            'cat "$FIXTURE"\nelse\nprintf "%s\\n" "$*" >> "$CALLS"\nfi\n')
            niri.chmod(0o755)
            environment = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                               FIXTURE=str(fixture), CALLS=str(log))
            result = subprocess.run(["bash", "-euo", "pipefail", str(SCRIPT), action, *args],
                                    env=environment, capture_output=True, text=True)
            return result, log.read_text().splitlines() if log.exists() else []

    @staticmethod
    def window(identifier, column, row=1, focused=False):
        return {"id": identifier, "workspace_id": 1, "is_focused": focused,
                "layout": {"pos_in_scrolling_layout": [column, row]}}

    def test_pull_from_stacked_left_column(self):
        result, calls = self.run_action("consume-left", [
            self.window(10, 1), self.window(11, 1, 2), self.window(20, 2, focused=True)])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["msg action consume-or-expel-window-right --id 10"] * 2)

    def test_split_bottom_left_preserves_remaining_focus(self):
        result, calls = self.run_action("expel-left", [
            self.window(10, 1), self.window(11, 1, 2, focused=True)])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, ["msg action consume-or-expel-window-left --id 11",
                                 "msg action focus-window --id 10"])

    def test_no_left_column_is_noop(self):
        result, calls = self.run_action("consume-left", [self.window(10, 1, focused=True)])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(calls, [])

    def test_rejects_non_numeric_ids_and_unknown_power_actions(self):
        for action in ["clipboard-copy", "focus-window", "power-action"]:
            result, calls = self.run_action(action, [], "1; exit 0")
            self.assertEqual(result.returncode, 2)
            self.assertEqual(calls, [])


class DesktopPowerActionsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.log = self.directory / 'calls.jsonl'
        self.env = dict(os.environ, PATH=str(self.directory), ACTION_LOG=str(self.log))
        source = Path(__file__).resolve().parents[2] / 'nix/modules/desktop/actions.sh'
        self.action = self.directory / 'ohmansy-desktop'
        self.action.write_text(f'#!{shutil.which("bash")}\nset -euo pipefail\n' + source.read_text())
        self.action.chmod(0o755)
        mock = f'''#!{sys.executable}
import json, os, sys
with open(os.environ['ACTION_LOG'], 'a') as log:
    log.write(json.dumps([os.path.basename(sys.argv[0]), *sys.argv[1:]]) + '\\n')
if os.environ.get('FAIL_LOCK') and sys.argv[1:] == ['--user', 'start', 'ohmansy-lock.service']:
    sys.exit(1)
'''
        for name in ['systemctl', 'niri']:
            program = self.directory / name
            program.write_text(mock)
            program.chmod(0o755)

    def run_action(self, *args):
        result = subprocess.run([str(self.action), *args], env=self.env, capture_output=True)
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        return result.returncode, calls

    def test_lock_shortcut_and_menu_keep_the_session(self):
        for args in [('lock',), ('power-action', 'lock')]:
            with self.subTest(args=args):
                self.log.write_text('')
                code, calls = self.run_action(*args)
                self.assertEqual(code, 0)
                self.assertEqual(calls, [['systemctl', '--user', 'start', 'ohmansy-lock.service']])

    def test_logout_requests_compositor_confirmation(self):
        code, calls = self.run_action('power-action', 'logout')
        self.assertEqual(code, 0)
        self.assertEqual(calls, [['niri', 'msg', 'action', 'quit']])

    def test_suspend_waits_for_lock(self):
        code, calls = self.run_action('power-action', 'suspend')
        self.assertEqual(code, 0)
        self.assertEqual(calls, [
            ['systemctl', '--user', 'start', 'ohmansy-lock.service'],
            ['systemctl', 'suspend'],
        ])

    def test_failed_lock_prevents_suspend(self):
        self.env['FAIL_LOCK'] = '1'
        code, calls = self.run_action('power-action', 'suspend')
        self.assertNotEqual(code, 0)
        self.assertEqual(calls, [['systemctl', '--user', 'start', 'ohmansy-lock.service']])


if __name__ == "__main__":
    unittest.main()
