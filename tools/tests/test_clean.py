import fcntl
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('clean', Path(__file__).resolve().parents[1] / 'dev/clean.py')
clean = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clean)


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()

    def directory(self, name):
        path = self.root / name
        path.mkdir(parents=True)
        (path / 'file').touch()
        return path

    def vm(self, name):
        path = self.directory('.local/' + name)
        for marker in ('disk.raw', 'factory.json', 'lock'):
            (path / marker).touch()
        return path

    @patch.object(clean, 'activity', return_value=('', []))
    def test_cleanup_preserves_guest_keys_current_app_and_factory(self, _):
        keep = [self.vm('current'), self.directory('.local/ssh'),
                self.directory('dist/Ohmansy.app'), self.directory('dist/factory-preview')]
        old = self.directory('dist/Ohmansy-before-test.app')
        clean.clean(self.root, dry_run=True)
        self.assertTrue(old.exists())
        clean.clean(self.root)
        self.assertFalse(old.exists())
        self.assertTrue(all(p.exists() for p in keep))

    @patch.object(clean, 'activity', return_value=('', []))
    def test_locked_vm_survives_explicit_retirement(self, _):
        vm = self.vm('old')
        with (vm / 'lock').open('r+b') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            clean.clean(self.root, ['old'])
            self.assertTrue(vm.exists())
        clean.clean(self.root, ['old'])
        self.assertFalse(vm.exists())

    def test_in_use_artifact_survives(self):
        old = self.directory('dist/Ohmansy-before-test.app')
        with patch.object(clean, 'activity', return_value=('', [str(old / 'file')])):
            clean.clean(self.root)
        self.assertTrue(old.exists())

    def test_paths_cannot_escape_through_names_or_symlinks(self):
        for name in ('../elsewhere', '.', '/tmp/elsewhere', 'a/b'):
            with self.assertRaises(ValueError):
                clean.candidates(self.root, [name])
        (self.root / 'dist').symlink_to(self.root, target_is_directory=True)
        self.directory('Ohmansy-before-test.app')
        with self.assertRaises(ValueError):
            clean.candidates(self.root, [])

    def test_disk_in_artifacts_is_not_deleted(self):
        path = self.directory('dist/check')
        (path / 'disk.raw').touch()
        with self.assertRaises(ValueError):
            clean.candidates(self.root, [])

    @patch.object(clean, 'activity', side_effect=RuntimeError('Cannot inspect'))
    def test_failed_inspection_does_not_delete(self, _):
        old = self.directory('.build')
        with self.assertRaises(RuntimeError):
            clean.clean(self.root)
        self.assertTrue(old.exists())
