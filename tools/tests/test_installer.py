import importlib.util
from pathlib import Path
import unittest
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('installer', Path(__file__).resolve().parents[2] / 'nix/modules/installer/install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
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
                installer.write_configuration('alex', 'workstation')
            self.assertEqual((config / 'hardware-configuration.nix').read_text(), 'disk identities')
            self.assertEqual((config / 'flake.nix').read_text(), 'pinned release flake')
            self.assertEqual((config / 'flake.lock').read_text(), 'locked dependencies')
            self.assertTrue((config / 'preferences.nix').exists())
            self.assertIn('system.stateVersion = "26.05"', (config / 'configuration.nix').read_text())
            self.assertFalse((config / 'ohmansy').exists())

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

    def test_rejects_reserved_and_injected_account_names(self):
        for name in ['root', 'nixos', 'greeter', 'nixbld2', 'systemd-foo', 'user; reboot', 'user"', '../root', '']:
            self.assertFalse(installer.valid_username(name), name)
        self.assertTrue(installer.valid_username('alex'))

    def test_installed_host_has_no_live_account_or_passwordless_login(self):
        configuration = installer.host_config('alex', 'workstation')
        self.assertIn('users.users."alex"', configuration)
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
