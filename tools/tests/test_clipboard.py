import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('clipboard', Path(__file__).resolve().parents[2] / 'nix/modules/vm/clipboard.py')
clipboard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clipboard)


class ClipboardTests(unittest.TestCase):
    def test_unicode_multiline_and_nul_roundtrip(self):
        text = 'Hello → world\nSecond line\x00'
        self.assertEqual(clipboard.decode(clipboard.encode({'text': text})), {'text': text})

    def test_rejects_invalid_and_oversized_frames(self):
        for message in (b'[]', b'{"text":1}', clipboard.encode({'text': 'a' * (clipboard.TEXT_LIMIT + 1)}), b'x' * (clipboard.FRAME_LIMIT + 1)):
            with self.assertRaises(ValueError):
                clipboard.decode(message)
