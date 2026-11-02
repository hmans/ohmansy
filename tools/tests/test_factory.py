import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


setup = load('first_boot', ROOT / 'nix/modules/first-boot/setup.py')
factory = load('factory_vm', ROOT / 'app/runtime/factory-vm.py')


class FactoryTests(unittest.TestCase):
    def test_manifest_rejects_paths_and_wrong_architecture(self):
        manifest = dict(schemaVersion=1, product='ohmansy', kind='factory',
                        format='raw.zst', architecture='aarch64-linux')
        for filename in ['../disk.raw.zst', '/disk.raw.zst', 'disk.iso', '']:
            with self.assertRaises(ValueError):
                factory.validate_manifest(dict(manifest, image={'file': filename}))
        manifest['image'] = {'file': 'ohmansy.raw.zst'}
        self.assertEqual(factory.validate_manifest(manifest), 'ohmansy.raw.zst')
        manifest['architecture'] = 'x86_64-linux'
        with self.assertRaises(ValueError):
            factory.validate_manifest(manifest)

    def test_account_setup_retries_password_and_declares_owner(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(setup, 'STATE', root / 'state'), patch.object(setup, 'CONFIG', root), \
                 patch.object(setup.pwd, 'getpwnam', side_effect=KeyError), \
                 patch('builtins.input', side_effect=['root', 'alice']), \
                 patch.object(setup.subprocess, 'run', side_effect=[Mock(returncode=0), Mock(returncode=1), Mock(returncode=0)]) as run:
                setup.main('/run/current-system/sw/bin/fish')
            self.assertEqual((root / 'state/provisioned').read_text(), 'alice\n')
            self.assertFalse((root / 'state/pending-owner').exists())
            owner = (root / 'owner.nix').read_text()
            self.assertIn('users.users."alice"', owner)
            self.assertNotIn('Password', owner)
            self.assertEqual(run.call_args_list[0].args[0][-3:],
                             ['--shell', '/run/current-system/sw/bin/fish', 'alice'])
            self.assertEqual(run.call_args_list[-1].args[0], ['passwd', 'alice'])

    def test_interrupted_setup_resumes_without_recreating_account(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'pending-owner').write_text('alice\n')
            with patch.object(setup, 'STATE', root), patch.object(setup, 'CONFIG', root), \
                 patch.object(setup.pwd, 'getpwnam', return_value=Mock()), \
                 patch('builtins.input', side_effect=AssertionError('Must reuse pending account')), \
                 patch.object(setup.subprocess, 'run', return_value=Mock(returncode=0)) as run:
                setup.main('/run/current-system/sw/bin/fish')
            run.assert_called_once_with(['passwd', 'alice'])


if __name__ == '__main__':
    unittest.main()
