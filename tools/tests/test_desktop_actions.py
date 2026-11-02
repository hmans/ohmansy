"""Check desktop helper decisions without touching a running desktop."""
import json
import os
from pathlib import Path
import shutil
import subprocess
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


if __name__ == "__main__":
    unittest.main()
