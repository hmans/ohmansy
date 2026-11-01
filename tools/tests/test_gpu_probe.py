import fcntl
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('gpu_probe', Path(__file__).resolve().parents[2] / 'app/runtime/gpu-probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class GPUProbeTests(unittest.TestCase):
    def test_live_session_only_attaches_readonly_iso(self):
        args = probe.launch_arguments(Path('/Applications/Try Omarchy.app'),
                                      Path('/tmp/NixOS, ARM.iso'), Path('/tmp/probe'))
        drives = [args[i + 1] for i, arg in enumerate(args) if arg == '-drive']
        self.assertEqual(drives, ['if=none,id=installer,format=raw,readonly=on,file=/tmp/NixOS,, ARM.iso'])
        self.assertIn('virtio-gpu-gl-pci,max_outputs=1,xres=1920,yres=1200,romfile=', args)
        self.assertNotIn('-fsdev', args)
        self.assertFalse(any('hostfwd=' in arg for arg in args))
        self.assertIn('cocoa,gl=on,show-cursor=off,zoom-to-fit=on,full-grab=on', args)

    def test_owned_helper_uses_its_firmware_and_selected_resources(self):
        state = Path('/tmp/probe')
        helper = Path('/tmp/try ohmansy.app/Contents/Helpers/try ohmansy.app')
        args = probe.launch_arguments(Path('/unused'), None, state, state / 'disk.raw',
                                      helper, cpus=6, memory_mib=12288)
        self.assertEqual(args[0], str(helper / 'Contents/MacOS/try ohmansy'))
        self.assertEqual(args[args.index('-smp') + 1], '6')
        self.assertEqual(args[args.index('-m') + 1], '12288')
        self.assertTrue(any(str(helper / 'Contents/Resources/firmware') in arg for arg in args))
        self.assertFalse(any('/unused' in arg for arg in args))
        self.assertIn('-S', args)
        self.assertIn('-no-shutdown', args)
        self.assertIn('user,id=net,hostfwd=tcp:127.0.0.1:2222-:22', args)

    def test_running_source_is_not_cloned(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, target = root / 'source', root / 'target'
            source.mkdir()
            target.mkdir()
            (source / 'disk.raw').write_bytes(b'original')
            with (source / 'lock').open('w') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with self.assertRaisesRegex(RuntimeError, 'Shut down'):
                    probe.prepare_vm_copy(source, target)
            self.assertEqual((source / 'disk.raw').read_bytes(), b'original')
            self.assertFalse((target / 'disk.raw').exists())

    def test_live_helper_can_run_without_exposing_ssh_or_attaching_a_disk(self):
        args = probe.launch_arguments(Path('/unused'), Path('/tmp/live.iso'), Path('/tmp/live-test'),
                                      helper=Path('/tmp/helper.app'), ssh_port=0)
        self.assertFalse(any('hostfwd=' in arg for arg in args))
        drives = [args[i + 1] for i, arg in enumerate(args) if arg == '-drive']
        self.assertEqual(len(drives), 1)
        self.assertIn('readonly=on', drives[0])

    def test_installer_only_attaches_the_explicit_test_disk(self):
        args = probe.launch_arguments(Path('/unused'), Path('/tmp/live.iso'), Path('/tmp/test'),
                                      helper=Path('/tmp/helper.app'), ssh_port=0,
                                      install_disk=Path('/tmp/test/target.raw'))
        drives = [args[i + 1] for i, arg in enumerate(args) if arg == '-drive']
        self.assertEqual(len(drives), 2)
        self.assertIn('readonly=on', drives[0])
        self.assertEqual(drives[1], 'if=none,id=install-target,format=raw,file=/tmp/test/target.raw')

    def test_copy_is_independent_and_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, target = root / 'source', root / 'target'
            source.mkdir()
            target.mkdir()
            (source / 'lock').touch()
            (source / 'disk.raw').write_bytes(b'original')
            disk = probe.prepare_vm_copy(source, target)
            self.assertEqual(disk.read_bytes(), b'original')
            disk.write_bytes(b'guest changes')
            probe.prepare_vm_copy(source, target)
            self.assertEqual(disk.read_bytes(), b'guest changes')
            self.assertEqual((source / 'disk.raw').read_bytes(), b'original')
            self.assertEqual((target / 'efi-vars.fd').stat().st_size, 64 * 1024 * 1024)

    def test_symlink_disk_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'outside').write_bytes(b'do not change')
            (root / 'disk.raw').symlink_to(root / 'outside')
            with self.assertRaisesRegex(RuntimeError, 'regular file'):
                probe.prepare_vm_copy(root / 'unused', root)
            self.assertEqual((root / 'outside').read_bytes(), b'do not change')


if __name__ == '__main__':
    unittest.main()
