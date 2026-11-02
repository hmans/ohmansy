import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('firmware_display', Path(__file__).resolve().parents[1] / 'dev/firmware-display.py')
display = importlib.util.module_from_spec(spec)
spec.loader.exec_module(display)


class FirmwareDisplayTests(unittest.TestCase):
    def test_validates_wire_format(self):
        self.assertEqual(display.resolution_value(None, 1024, 768), struct.pack('<III', 7, 1024, 768))
        for value in [b'', struct.pack('<III', 3, 800, 600), bytes(16)]:
            with self.assertRaises(ValueError):
                display.resolution_value(value, 1024, 768)

    def test_backup_precedes_change_and_repeated_setting_is_noop(self):
        with tempfile.TemporaryDirectory() as directory:
            variable, backup = Path(directory) / 'variable', Path(directory) / 'backup'
            self.assertTrue(display.set_resolution(variable, '1024x768', backup))
            self.assertEqual(json.loads(backup.read_text()), {'previous': None})
            self.assertFalse(display.set_resolution(variable, '1024x768', backup))
            with self.assertRaises(FileExistsError):
                display.set_resolution(variable, '1280x800', backup)
            self.assertEqual(variable.read_bytes(), struct.pack('<III', 7, 1024, 768))

    def test_preserves_previous_variable_in_backup(self):
        with tempfile.TemporaryDirectory() as directory:
            variable, backup = Path(directory) / 'variable', Path(directory) / 'backup'
            previous = struct.pack('<III', 7, 1920, 1200)
            variable.write_bytes(previous)
            display.set_resolution(variable, '1024x768', backup)
            self.assertEqual(json.loads(backup.read_text())['previous'], previous.hex())
