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

    def test_real_archive_excludes_development_access(self):
        with tarfile.open(fileobj=io.BytesIO(guest_dev.source_archive())) as archive:
            self.assertFalse(any(name.startswith(('.local/', 'tools/')) for name in archive.getnames()))
            self.assertFalse(any('guest-access' in name or 'development-access' in name for name in archive.getnames()))

    def test_refuses_symlink_into_personal_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'flake.nix').write_text('test')
            (root / 'flake.lock').write_text('test')
            (root / 'nix').mkdir()
            (root / 'nix/personal.nix').symlink_to(root / 'flake.nix')
            with patch.object(guest_dev, 'ROOT', root), self.assertRaises(ValueError):
                guest_dev.source_archive()


class DevelopmentAccessTests(unittest.TestCase):
    def test_renders_owner_key_and_marker_without_key_comment(self):
        module = guest_dev.access_module('alice', 'ssh-ed25519 AAAA comment-${danger}')
        self.assertIn('users.users."alice"', module)
        self.assertIn('"ssh-ed25519 AAAA"', module)
        self.assertIn('ohmansy/development-access', module)
        self.assertIn('NOPASSWD', module)
        self.assertNotIn('${', module)
        self.assertNotIn('@USER@', module)

    def test_rejects_root_live_account_and_nix_injection(self):
        for user in ['root', 'nixos', '${bad}', 'alice"; bad', '']:
            with self.subTest(user=user), self.assertRaises(ValueError):
                guest_dev.access_module(user, 'ssh-ed25519 AAAA')
        for key in ['private-key', 'ssh-ed25519 ${bad}', 'ssh-rsa AAAA']:
            with self.subTest(key=key), self.assertRaises(ValueError):
                guest_dev.access_module('alice', key)

    def test_output_stays_local_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            key = root / 'key.pub'
            key.write_text('ssh-ed25519 AAAA')
            with patch.object(guest_dev, 'ROOT', root), patch.object(guest_dev, 'access_module', return_value='overlay'):
                with self.assertRaises(ValueError):
                    guest_dev.write_access_module('alice', key, root / 'nix/access.nix')
                output = guest_dev.write_access_module('alice', key, root / '.local/access.nix')
                self.assertEqual(output.stat().st_mode & 0o777, 0o600)
                with self.assertRaises(FileExistsError):
                    guest_dev.write_access_module('alice', key, output)
                (root / '.local/escape').symlink_to(root, target_is_directory=True)
                with self.assertRaises(ValueError):
                    guest_dev.write_access_module('alice', key, root / '.local/escape/access.nix')


if __name__ == '__main__':
    unittest.main()
