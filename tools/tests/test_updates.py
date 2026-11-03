import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('updates', Path(__file__).resolve().parents[2] / 'nix/modules/updates/update.py')
updates = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updates)


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name).resolve()
        self.config, self.state, self.store = root / 'config', root / 'updates', root / 'store'
        for path in (self.config, self.state, self.store):
            path.mkdir()
        (self.config / 'flake.nix').write_text('{\n  inputs.ohmansy.url = "path:/old-release";\n}\n')
        (self.config / 'flake.lock').write_text('{}')
        (self.config / 'preferences.nix').write_text('{ pkgs, ... }: { environment.systemPackages = [ pkgs.hello ]; }')
        (self.config / 'owner.nix').write_text('owner configuration')
        (self.config / 'configuration.nix').write_text('system.stateVersion = "26.05";')
        self.old, self.new = self.store / 'old-system', self.store / 'new-system'
        self.old.mkdir()
        self.new.mkdir()
        self.profile = root / 'profile'
        self.profile.symlink_to(self.old)
        self.calls = []
        self.fail_boot = False

    def command(self, *args, **kwargs):
        self.calls.append(tuple(map(str, args)))
        if args[:3] == ('nix', 'flake', 'lock'):
            (Path(str(args[3]).removeprefix('path:')) / 'flake.lock').write_text('{"updated": true}')
        elif args[:2] == ('nix', 'build'):
            Path(args[args.index('--out-link') + 1]).symlink_to(self.new)
        elif args[0] == 'nix-env':
            self.profile.unlink()
            self.profile.symlink_to(args[-1])
        elif args[0] == self.new / 'bin/switch-to-configuration' and self.fail_boot:
            raise subprocess.CalledProcessError(1, args)

    def prepare(self):
        with patch.object(updates, 'run', self.command):
            return updates.prepare('v0.2.0', self.config, self.state)

    def apply(self, transaction):
        with patch.object(updates, 'run', self.command):
            updates.apply(transaction.name, self.config, self.state, self.profile, self.store)

    def test_build_then_boot_preserves_local_files(self):
        before = {p.name: p.read_bytes() for p in self.config.iterdir()}
        transaction = self.prepare()
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.config.iterdir()})
        self.apply(transaction)
        self.assertEqual(self.profile.resolve(), self.new)
        for name in ('owner.nix', 'preferences.nix', 'configuration.nix'):
            self.assertEqual((self.config / name).read_bytes(), before[name])
        self.assertIn('github:hmans/ohmansy/v0.2.0', (self.config / 'flake.nix').read_text())
        self.assertEqual(self.calls[-1], (str(self.new / 'bin/switch-to-configuration'), 'boot'))
        self.assertTrue((transaction / 'previous/flake.lock').exists())
        with self.assertRaisesRegex(ValueError, 'already applied'):
            self.apply(transaction)

    def test_local_edit_blocks_apply(self):
        transaction = self.prepare()
        (self.config / 'preferences.nix').write_text('new local preference')
        with self.assertRaisesRegex(ValueError, 'Local configuration changed'):
            self.apply(transaction)
        self.assertEqual(self.profile.resolve(), self.old)

    def test_candidate_edit_blocks_apply(self):
        transaction = self.prepare()
        (transaction / 'configuration/owner.nix').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'Prepared configuration changed'):
            self.apply(transaction)

    def test_boot_failure_restores_pin_and_profile(self):
        before = updates.fingerprint(self.config)
        transaction = self.prepare()
        self.fail_boot = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.apply(transaction)
        self.assertEqual(updates.fingerprint(self.config), before)
        self.assertEqual(self.profile.resolve(), self.old)
        self.assertEqual(self.calls[-1], (str(self.old / 'bin/switch-to-configuration'), 'boot'))

    def test_build_failure_never_changes_live_config(self):
        before = updates.fingerprint(self.config)
        with patch.object(updates, 'run', side_effect=subprocess.CalledProcessError(1, ['nix'])):
            with self.assertRaises(subprocess.CalledProcessError):
                updates.prepare('v0.2.0', self.config, self.state)
        self.assertEqual(updates.fingerprint(self.config), before)
        self.assertFalse(list(self.state.glob('*/manifest.json')))

    def test_rejects_unpinned_or_injected_releases(self):
        for value in ('main', '../main', 'v1.0.0"; abort "x', 'abc123', 'https://example.com'):
            with self.assertRaises(ValueError):
                updates.release_url(value)
        self.assertTrue(updates.release_url('a' * 40).endswith('a' * 40))

    def test_symlink_cannot_redirect_candidate_writes_to_live_config(self):
        original = self.config / 'original.nix'
        (self.config / 'flake.nix').rename(original)
        (self.config / 'flake.nix').symlink_to(original)
        before = original.read_bytes()
        with self.assertRaisesRegex(ValueError, 'not symlinks'):
            self.prepare()
        self.assertEqual(original.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
