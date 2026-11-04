import fcntl
import importlib.util
import json
from pathlib import Path
import socket
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parents[2] / 'nix/modules/installer'
spec = importlib.util.spec_from_file_location('install', ROOT / 'install.py')
install = importlib.util.module_from_spec(spec)
spec.loader.exec_module(install)
spec = importlib.util.spec_from_file_location('installer_backend', ROOT / 'backend.py')
backend = importlib.util.module_from_spec(spec)
with patch.dict(sys.modules, {'install': install}):
    spec.loader.exec_module(backend)


class InstallerBackendTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        for module, name, value in [(backend, 'STATE', root / 'state.json'), (backend, 'LOG', root / 'install.log'),
                                    (install, 'LOCK', root / 'lock')]:
            patcher = patch.object(module, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.request = {'action': 'start', 'device': '/dev/vda', 'hostname': 'test-pc', 'token': 'disk-token', 'confirmation': 'ERASE /dev/vda'}

    def test_confirmation_is_required_before_validation_or_worker(self):
        with patch.object(install, 'validate_target') as validate:
            controller = backend.Installer()
            for confirmation in ['', 'ERASE /dev/vdb', True]:
                response = controller.handle(dict(self.request, confirmation=confirmation))
                self.assertFalse(response['ok'])
            validate.assert_not_called()
            self.assertEqual(controller.state['status'], 'idle')

    def test_existing_cli_lock_prevents_graphical_install(self):
        with install.LOCK.open('w') as lock, patch.object(install, 'validate_target') as validate:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError):
                backend.Installer().handle(self.request)
            validate.assert_not_called()

    def test_start_is_single_and_status_can_reconnect(self):
        with patch.object(install, 'validate_target'), patch.object(backend.threading, 'Thread') as thread:
            controller = backend.Installer()
            self.assertTrue(controller.handle(self.request)['ok'])
            lock = thread.call_args.kwargs['args'][-1]
            self.addCleanup(lock.close)
            self.assertFalse(controller.handle(self.request)['ok'])
            for _ in range(3):
                self.assertEqual(controller.handle({'action': 'status'})['status'], 'running')
            thread.assert_called_once()
            with install.LOCK.open('w') as other:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_changed_disk_fails_before_erase(self):
        disk = {'path': '/dev/vda', 'size': 32 * 1024**3, 'serial': 'replacement'}
        with patch.object(install, 'preflight'), patch.object(install, 'list_disks', return_value=[disk]), \
             patch.object(install, 'check_labels') as labels:
            with self.assertRaisesRegex(RuntimeError, 'changed'):
                backend.Installer().handle(self.request)
            labels.assert_not_called()

    def test_worker_failure_retains_log_and_forbids_erase_retry(self):
        controller = backend.Installer()
        def fail(*args, progress, log, **kwargs):
            progress('format')
            log.write('Useful formatter diagnostics\n')
            raise RuntimeError('Formatting failed')
        lock = install.LOCK.open('w')
        with patch.object(install, 'perform_install', side_effect=fail):
            controller.work('/dev/vda', 'test-pc', 'disk-token', lock)
        self.assertTrue(lock.closed)
        state = controller.snapshot()
        self.assertEqual(state['status'], 'failed')
        self.assertTrue(state['destructive'])
        self.assertIn('Useful formatter diagnostics', state['log'])
        self.assertFalse(controller.handle(self.request)['ok'])
        self.assertEqual(backend.Installer().state['status'], 'failed')

    def test_success_survives_service_restart(self):
        controller = backend.Installer()
        with patch.object(install, 'perform_install'):
            controller.work('/dev/vda', 'test-pc', 'disk-token', install.LOCK.open('w'))
        restarted = backend.Installer()
        self.assertEqual(restarted.state['status'], 'done')
        self.assertFalse(restarted.handle(self.request)['ok'])

    def test_interrupted_service_never_restarts_destructive_work(self):
        backend.STATE.write_text(json.dumps({'status': 'running', 'stage': 'install'}))
        controller = backend.Installer()
        self.assertEqual(controller.state['status'], 'failed')
        self.assertTrue(controller.state['destructive'])
        self.assertFalse(controller.handle(self.request)['ok'])

    def test_shutdown_is_only_available_after_success(self):
        with patch.object(backend.subprocess, 'run') as run:
            controller = backend.Installer()
            self.assertFalse(controller.handle({'action': 'shutdown'})['ok'])
            run.assert_not_called()
            controller.state['status'] = 'done'
            self.assertTrue(controller.handle({'action': 'shutdown'})['ok'])
            run.assert_called_once_with(['systemctl', 'poweroff', '--no-block'], check=True)

    @unittest.skipUnless(sys.platform == 'linux', 'Linux socket peer credentials')
    def test_socket_rejects_wrong_peer_and_oversized_input(self):
        client, server = socket.socketpair()
        with client, server:
            controller = Mock()
            backend.reply(server, controller, 999999)
            controller.handle.assert_not_called()
        client, server = socket.socketpair()
        with client, server:
            import os
            client.sendall(b'x' * 4097 + b'\n')
            backend.reply(server, controller, os.getuid())
            self.assertFalse(json.loads(client.recv(8192))['ok'])
            controller.handle.assert_not_called()


if __name__ == '__main__':
    unittest.main()
