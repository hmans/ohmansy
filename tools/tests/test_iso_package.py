import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('package_iso', Path(__file__).resolve().parents[1] / 'release/package-iso.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class IsoPackageTests(unittest.TestCase):
    def package(self, *options):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        iso = root / 'test.iso'
        iso.write_bytes(b'\0' * 0x8001 + b'CD001')
        output = root / 'package'
        with patch('sys.argv', ['package-iso', '--iso', str(iso), '--output', str(output), *options]), \
             patch.object(package.guest_dev, 'source_archive', return_value=b'source'), \
             patch.object(package.subprocess, 'check_output', side_effect=['a' * 40, '']):
            package.main()
        return json.loads((output / 'manifest.json').read_text()), output

    def test_pc_live_manifest_does_not_advertise_disk_installation(self):
        manifest, output = self.package('--architecture', 'x86_64-linux', '--kind', 'live', '--graphics', 'nvidia')
        self.assertEqual(manifest['architecture'], 'x86_64-linux')
        self.assertEqual(manifest['channel'], 'live-preview')
        self.assertEqual(manifest['graphics'], 'nvidia')
        self.assertFalse(manifest['persistentInstallation'])
        self.assertNotIn('installer', manifest)
        self.assertIn(manifest['image']['sha256'], (output / 'SHA256SUMS').read_text())

    def test_existing_installer_defaults_remain_compatible(self):
        manifest, _ = self.package()
        self.assertEqual(manifest['architecture'], 'aarch64-linux')
        self.assertTrue(manifest['persistentInstallation'])
        self.assertEqual(manifest['installer']['mode'], 'whole-disk')
