import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch, Mock

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
            self.assertIn('nix/modules/development.nix', archive.getnames())
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
        self.assertIn('user = "alice"', module)
        self.assertIn('"ssh-ed25519 AAAA"', module)
        self.assertIn('ohmansy.nixosModules.development', module)
        self.assertIn('passwordlessSudo = true', module)
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


class BridgeTests(unittest.TestCase):
    def test_forward_parser_requires_loopback_and_guest_ssh(self):
        self.assertTrue(guest_dev.forwarded('TCP[HOST_FORWARD] 9 127.0.0.1 2223 10.0.2.15 22 0 0', 2223))
        for row in ['TCP[HOST_FORWARD] 9 0.0.0.0 2223 10.0.2.15 22 0 0',
                    'TCP[HOST_FORWARD] 9 127.0.0.1 2223 10.0.2.15 80 0 0']:
            self.assertFalse(guest_dev.forwarded(row, 2223))

    def test_bridge_persists_opt_in_and_updates_running_vm(self):
        factory = guest_dev.runtime_module('factory-vm')
        qmp = Mock(side_effect=['', '', 'TCP[HOST_FORWARD] 9 127.0.0.1 2223 10.0.2.15 22 0 0'])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / '.local/vm'
            state.mkdir(parents=True)
            for name in ['factory.json', 'disk.raw', 'qmp.sock']: (state / name).touch()
            with patch.object(guest_dev, 'ROOT', root), patch.object(guest_dev, 'runtime_module',
                    side_effect=lambda name: factory if name == 'factory-vm' else Mock(qmp_command=qmp)):
                guest_dev.bridge(state, 2223)
                self.assertEqual(factory.development_ssh_port(state), 2223)
                self.assertEqual((state / 'development.json').stat().st_mode & 0o777, 0o600)
                qmp.assert_any_call(state.resolve(), 'human-monitor-command',
                                    {'command-line': 'hostfwd_add net tcp:127.0.0.1:2223-:22'})
                qmp.side_effect = ['TCP[HOST_FORWARD] 9 127.0.0.1 2223 10.0.2.15 22 0 0', '', '']
                guest_dev.bridge(state, 2223, False)
                self.assertFalse((state / 'development.json').exists())

    def test_failed_forward_is_not_persisted_and_external_paths_are_rejected(self):
        factory = guest_dev.runtime_module('factory-vm')
        qmp = Mock(side_effect=['', 'Could not set up host forwarding rule'])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / '.local/vm'
            state.mkdir(parents=True)
            for name in ['factory.json', 'disk.raw', 'qmp.sock']: (state / name).touch()
            with patch.object(guest_dev, 'ROOT', root), patch.object(guest_dev, 'runtime_module',
                    side_effect=lambda name: factory if name == 'factory-vm' else Mock(qmp_command=qmp)):
                with self.assertRaises(ValueError): guest_dev.bridge(root, 2223)
                with self.assertRaises(ValueError): guest_dev.bridge(state, 22)
                with self.assertRaisesRegex(ValueError, 'Could not enable'): guest_dev.bridge(state, 2223)
                self.assertFalse((state / 'development.json').exists())


if __name__ == '__main__':
    unittest.main()
