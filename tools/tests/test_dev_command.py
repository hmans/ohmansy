import base64
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('dev_command', ROOT / 'nix/modules/development/dev.py')
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)
KEY = 'ssh-ed25519 ' + base64.b64encode(b'\0\0\0\x0bssh-ed25519\0\0\0\x20' + b'x' * 32).decode()


class DevCommandTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name).resolve()
        self.config, self.state = root / 'config', root / 'state'
        self.config.mkdir(); self.state.mkdir()
        self.flake = b'{\n  modules = [ ./configuration.nix ./owner.nix ];\n}\n'
        (self.config / 'flake.nix').write_bytes(self.flake)
        (self.config / 'flake.lock').write_bytes(b'unchanged lock')
        (self.config / 'owner.nix').write_bytes(b'existing owner and settings')
        self.old, self.new = root / 'old', root / 'new'
        self.old.mkdir(); self.new.mkdir()
        self.profile, self.current = root / 'profile', root / 'current'
        self.profile.symlink_to(self.old); self.current.symlink_to(self.old)
        self.content = dev.overlay('alice', KEY)
        self.calls = []
        self.fail_switch = False
        self.fail_build = False
        self.edit_during_build = False

    def command(self, *args, **kwargs):
        args = tuple(str(arg) for arg in args)
        self.calls.append(args)
        if args[:2] == ('nix', 'build'):
            if self.fail_build:
                raise subprocess.CalledProcessError(1, args)
            Path(args[args.index('--out-link') + 1]).symlink_to(self.new)
            if self.edit_during_build:
                (self.config / 'owner.nix').write_text('user edit')
        if args[0] == 'nix-env':
            self.profile.unlink(); self.profile.symlink_to(args[-1])
        if args == (str(self.new / 'bin/switch-to-configuration'), 'switch') and self.fail_switch:
            raise subprocess.CalledProcessError(1, args)
        return Mock(returncode=0)

    def activate(self, action):
        with patch.object(dev, 'run', side_effect=self.command):
            dev.activate(action, self.content if action == 'enable' else None,
                         self.config, self.state, self.profile, self.current)

    def test_enable_then_disable_preserves_owner_lock_and_original_flake(self):
        self.activate('enable')
        self.assertEqual((self.config / 'development.nix').read_bytes(), self.content)
        self.assertIn(dev.IMPORT.encode(), (self.config / 'flake.nix').read_bytes())
        self.assertEqual(self.profile.resolve(), self.new)
        self.activate('disable')
        self.assertEqual((self.config / 'flake.nix').read_bytes(), self.flake)
        self.assertFalse((self.config / 'development.nix').exists())
        self.assertFalse((self.state / 'managed.json').exists())
        self.assertEqual((self.config / 'owner.nix').read_bytes(), b'existing owner and settings')
        self.assertEqual((self.config / 'flake.lock').read_bytes(), b'unchanged lock')

    def test_build_failure_leaves_live_configuration_and_profile_untouched(self):
        self.fail_build = True
        with self.assertRaises(subprocess.CalledProcessError): self.activate('enable')
        self.assertEqual((self.config / 'flake.nix').read_bytes(), self.flake)
        self.assertFalse((self.config / 'development.nix').exists())
        self.assertEqual(self.profile.resolve(), self.old)

    def test_switch_failure_restores_configuration_profile_and_runtime(self):
        self.fail_switch = True
        with self.assertRaises(subprocess.CalledProcessError): self.activate('enable')
        self.assertEqual((self.config / 'flake.nix').read_bytes(), self.flake)
        self.assertFalse((self.config / 'development.nix').exists())
        self.assertEqual(self.profile.resolve(), self.old)
        self.assertIn((str(self.old / 'bin/switch-to-configuration'), 'test'), self.calls)
        self.assertIn((str(self.old / 'bin/switch-to-configuration'), 'boot'), self.calls)

    def test_disable_failure_restores_enabled_overlay_and_ownership_record(self):
        self.activate('enable')
        record = (self.state / 'managed.json').read_bytes()
        self.fail_switch = True
        with self.assertRaises(subprocess.CalledProcessError): self.activate('disable')
        self.assertEqual((self.config / 'development.nix').read_bytes(), self.content)
        self.assertEqual((self.state / 'managed.json').read_bytes(), record)

    def test_concurrent_edit_is_preserved_and_prevents_activation(self):
        self.edit_during_build = True
        with self.assertRaisesRegex(ValueError, 'changed during'): self.activate('enable')
        self.assertEqual((self.config / 'owner.nix').read_text(), 'user edit')
        self.assertEqual((self.config / 'flake.nix').read_bytes(), self.flake)
        self.assertEqual(self.profile.resolve(), self.old)

    def test_manual_overlay_and_edited_managed_overlay_are_not_overwritten(self):
        (self.config / 'development.nix').write_text('my custom config')
        with self.assertRaisesRegex(ValueError, 'not managed'): self.activate('enable')
        (self.config / 'development.nix').unlink()
        self.activate('enable')
        (self.config / 'development.nix').write_text('my edited config')
        with self.assertRaisesRegex(ValueError, 'was edited'): self.activate('disable')

    def test_symlinks_and_unrecognized_flake_are_rejected(self):
        (self.config / 'external').symlink_to(self.old)
        with self.assertRaisesRegex(ValueError, 'regular'): self.activate('enable')
        (self.config / 'external').unlink()
        (self.config / 'flake.nix').write_text('custom flake without modules list')
        with self.assertRaisesRegex(ValueError, 'modules list'): self.activate('enable')

    def test_key_and_account_validation(self):
        self.assertEqual(dev.public_key(KEY + ' comment-${ignored}'), KEY)
        for value in ['ssh-ed25519 AAAA', 'ssh-rsa AAAA', 'PRIVATE KEY', 'ssh-ed25519 !!!!']:
            with self.assertRaises(ValueError): dev.public_key(value)
        for value in ['root', 'nixos', '', 'alice"']:
            with self.assertRaises(ValueError): dev.owner(value)
        with patch.object(dev.pwd, 'getpwnam', return_value=Mock(pw_uid=1000)):
            self.assertEqual(dev.owner('alice'), 'alice')


if __name__ == '__main__':
    unittest.main()
