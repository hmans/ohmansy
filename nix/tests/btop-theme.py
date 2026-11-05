"""Check config ownership and theme updates without a desktop or user signals."""

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys

spec = importlib.util.spec_from_file_location("btop_theme", sys.argv.pop(1))
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)


class ThemeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.environment = patch.dict(os.environ, {"XDG_CONFIG_HOME": str(self.root / "config")})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.commands = patch.object(theme.subprocess, "run")
        self.run = self.commands.start()
        self.addCleanup(self.commands.stop)
        self.run.return_value.stdout = "'prefer-dark'\n"
        self.config = self.root / "config/btop/btop.conf"
        self.link = self.root / "config/btop/themes/ohmansy.theme"

    def test_fresh_config_and_dark_appearance(self):
        theme.prepare(self.root)
        self.assertEqual(self.config.read_text(), 'color_theme = "ohmansy"\ntheme_background = false\n')
        self.assertEqual(self.link.readlink(), self.root / "dark.theme")

    def test_existing_settings_are_preserved(self):
        self.config.parent.mkdir(parents=True)
        original = 'color_theme = "custom"\ntheme_background = true\nupdate_ms = 900\n'
        self.config.write_text(original)
        theme.prepare(self.root)
        self.assertEqual(self.config.read_text(), original)

    def test_switch_reloads_once_without_changing_config(self):
        theme.prepare(self.root)
        original = self.config.read_bytes()
        self.run.reset_mock()
        theme.sync(self.root, "dark")
        self.run.assert_not_called()
        theme.sync(self.root, "light")
        self.assertEqual(self.link.readlink(), self.root / "light.theme")
        self.assertEqual(self.config.read_bytes(), original)
        self.run.assert_called_once_with(
            ["pkill", "-USR2", "-u", str(os.getuid()), "-x", "btop"], check=False,
        )

    def test_no_desktop_preference_uses_light(self):
        self.run.return_value.stdout = ""
        theme.prepare(self.root)
        self.assertEqual(self.link.readlink(), self.root / "light.theme")


unittest.main()
