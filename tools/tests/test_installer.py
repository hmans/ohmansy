import importlib.util
import fcntl
from pathlib import Path
import unittest
import tempfile
from unittest.mock import patch
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location('installer', Path(__file__).resolve().parents[2] / 'nix/modules/installer/install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def test_second_installer_stops_before_disk_selection(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(installer, 'LOCK', Path(directory) / 'install.lock'), \
             patch.object(installer.os, 'geteuid', return_value=0), \
             patch.object(installer, 'install') as install:
            with installer.LOCK.open('w') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with self.assertRaisesRegex(SystemExit, 'already running'):
                    installer.main()
            install.assert_not_called()
            installer.main()
            install.assert_called_once()

    def test_install_requires_confirmation_and_defers_account_setup(self):
        disk = {'path': '/dev/vda', 'size': 64 * 1024**3, 'model': 'Test disk'}
        for confirmation in ('cancel', 'ERASE /dev/vda'):
            with self.subTest(confirmation=confirmation), tempfile.TemporaryDirectory() as directory, \
                 patch.object(installer, 'TARGET', Path(directory) / 'target'), \
                 patch.object(installer, 'LOCK', Path(directory) / 'install.lock'), \
                 patch.object(installer.os, 'geteuid', return_value=0), \
                 patch.object(Path, 'exists', autospec=True, side_effect=lambda path: str(path) == '/sys/firmware/efi' or path == installer.PAYLOAD / 'init' or path.is_file() or path.is_dir()), \
                 patch.object(installer, 'list_disks', return_value=[disk]), \
                 patch('builtins.input', side_effect=['1', 'test-pc', confirmation]), \
                 patch('builtins.print'), \
                 patch.object(installer, 'check_labels') as labels, \
                 patch.object(installer, 'write_configuration') as write, \
                 patch.object(installer, 'run') as run:
                if confirmation == 'cancel':
                    with self.assertRaisesRegex(SystemExit, 'Cancelled'):
                        installer.main()
                    run.assert_not_called()
                    write.assert_not_called()
                    labels.assert_not_called()
                else:
                    installer.main()
                    write.assert_called_once_with('test-pc')
                    commands = [call.args[0] for call in run.call_args_list]
                    self.assertIn('nixos-install', commands)
                    invocation = next(call.args for call in run.call_args_list if call.args[0] == 'nixos-install')
                    self.assertIn('--system', invocation)
                    self.assertNotIn('--flake', invocation)
                    self.assertEqual(invocation[-3:], ('--option', 'substituters', ''))
                    self.assertNotIn('nixos-enter', commands)
                    self.assertEqual(commands[-2:], ['sync', 'umount'])
                    mounts = [call.args for call in run.call_args_list if call.args[0] == 'mount']
                    self.assertEqual(mounts[0][1:4], ('-t', 'ext4', '/dev/vda2'))
                    self.assertEqual(mounts[1][1:4], ('-t', 'vfat', '/dev/vda1'))

    def test_installed_configuration_keeps_hardware_and_uses_release_pin(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, target = root / 'source', root / 'target'
            source.mkdir()
            (source / 'flake.nix').write_text('pinned release flake')
            (source / 'flake.lock').write_text('locked dependencies')
            config = target / 'etc/nixos'
            config.mkdir(parents=True)
            (config / 'hardware-configuration.nix').write_text('disk identities')
            with patch.object(installer, 'SOURCE', source), patch.object(installer, 'TARGET', target):
                installer.write_configuration('workstation')
            self.assertEqual((config / 'hardware-configuration.nix').read_text(), 'disk identities')
            self.assertEqual((config / 'flake.nix').read_text(), 'pinned release flake')
            self.assertEqual((config / 'flake.lock').read_text(), 'locked dependencies')
            self.assertEqual((target / 'etc/hostname').read_text(), 'workstation\n')
            self.assertTrue((config / 'preferences.nix').exists())
            self.assertIn('system.stateVersion = "26.05"', (config / 'configuration.nix').read_text())
            self.assertFalse((config / 'ohmansy').exists())

    def test_ambiguous_boot_labels_stop_before_erasure(self):
        for other, expected in [('/dev/vda2\n', False), ('/dev/vdb2\n', True)]:
            with self.subTest(other=other), \
                 patch.object(installer, 'run', return_value=SimpleNamespace(stdout='/dev/vda\n/dev/vda1\n/dev/vda2\n')), \
                 patch.object(installer.subprocess, 'run', return_value=SimpleNamespace(returncode=0, stdout=other)):
                if expected:
                    with self.assertRaisesRegex(SystemExit, 'Another disk'):
                        installer.check_labels('/dev/vda')
                else:
                    installer.check_labels('/dev/vda')

    def test_missing_payload_stops_before_disk_selection(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.object(installer, 'PAYLOAD', Path(directory)), \
             patch.object(Path, 'exists', autospec=True, side_effect=lambda path: str(path) == '/sys/firmware/efi'), \
             patch.object(installer, 'list_disks') as disks:
            with self.assertRaisesRegex(SystemExit, 'payload is missing'):
                installer.install()
            disks.assert_not_called()

    def test_excludes_live_media_mounted_disks_readonly_and_small_disks(self):
        disk = {'path': '/dev/vda', 'type': 'disk', 'size': 32 * 1024**3,
                'ro': False, 'mountpoints': [None]}
        devices = [disk,
                   dict(disk, path='/dev/vdb', children=[{'mountpoints': ['/iso']}]),
                   dict(disk, path='/dev/vdc', ro=True),
                   dict(disk, path='/dev/vdd', size=1024),
                   dict(disk, path='/dev/sr0', type='rom'),
                   dict(disk, path='/dev/vde', children=[{'children': [{'mountpoints': ['/']}]}])]
        self.assertEqual(installer.available_disks(devices), [disk])

    def test_installed_host_has_no_live_account_or_passwordless_login(self):
        configuration = installer.host_config('workstation')
        self.assertIn('ohmansy.nixosModules.firstBoot', configuration)
        self.assertNotIn('users.users', configuration)
        self.assertIn('hardware-configuration.nix', configuration)
        self.assertNotIn('./ohmansy/', configuration)
        self.assertNotIn('live.nix', configuration)
        self.assertNotIn('vm.nix', configuration)
        self.assertNotIn('initialPassword', configuration)
        self.assertNotIn('autoLogin', configuration)
        self.assertNotIn('wheelNeedsPassword', configuration)
        self.assertIn('services.openssh.enable = false', configuration)


if __name__ == '__main__':
    unittest.main()
