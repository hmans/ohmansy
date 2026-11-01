import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('guest_dev', Path(__file__).resolve().parents[2] / 'tools/dev/guest-dev.py')
guest_dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guest_dev)


class SourceTransferTests(unittest.TestCase):
    def test_only_official_flake_is_transferred(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ['flake.nix', 'flake.lock', 'nix/module.nix',
                         'flakey/flake.nix', '.local/ssh/id_ed25519',
                         'app/legacy/guest/ssh/account.nix', 'tools/dev/local.py']:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('test')
            with patch.object(guest_dev, 'ROOT', root):
                data = guest_dev.source_archive()
            with tarfile.open(fileobj=io.BytesIO(data)) as archive:
                self.assertEqual(set(archive.getnames()), {'flake.nix', 'flake.lock', 'nix/module.nix'})

    def test_refuses_symlink_into_personal_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'flake.nix').write_text('test')
            (root / 'flake.lock').write_text('test')
            (root / 'nix').mkdir()
            (root / 'nix/personal.nix').symlink_to(root / 'flake.nix')
            with patch.object(guest_dev, 'ROOT', root), self.assertRaises(ValueError):
                guest_dev.source_archive()


if __name__ == '__main__':
    unittest.main()
