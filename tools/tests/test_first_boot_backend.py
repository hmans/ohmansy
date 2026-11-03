import importlib.util
import json
import os
from pathlib import Path
import subprocess
import socket
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

SOURCE = Path(__file__).resolve().parents[2] / 'nix/modules/first-boot'
sys.path.insert(0, str(SOURCE))
spec = importlib.util.spec_from_file_location('first_boot_backend', SOURCE / 'backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)
sys.path.pop(0)


class FirstBootBackendTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.state = root / 'state'
        self.config = root / 'config'
        for name, value in [('STATE', self.state), ('CONFIG', self.config)]:
            p = patch.object(backend, name, value)
            p.start()
            self.addCleanup(p.stop)
        self.request = {'action': 'create', 'username': 'alice', 'name': 'Alice', 'password': 'correct horse'}

    @patch.object(backend, 'account_exists', return_value=False)
    @patch.object(backend.subprocess, 'run', return_value=Mock(returncode=0))
    def test_creates_owner_without_password_in_arguments_or_files(self, run, exists):
        self.assertTrue(backend.handle(self.request, '/bin/fish')['ok'])
        self.assertEqual((self.state / 'provisioned').read_text(), 'alice\n')
        self.assertIn('description = "Alice"', (self.config / 'owner.nix').read_text())
        self.assertFalse((self.state / 'pending-owner').exists())
        self.assertEqual(run.call_args_list[1].args[0], ['chpasswd'])
        self.assertEqual(run.call_args_list[1].kwargs['input'], 'alice:correct horse\n')
        for call in run.call_args_list:
            self.assertNotIn('correct horse', str(call.args))
        for file in Path(self.directory.name).rglob('*'):
            if file.is_file():
                self.assertNotIn('correct horse', file.read_text())

    @patch.object(backend.subprocess, 'run')
    def test_rejects_bad_input_and_existing_accounts(self, run):
        for changes in [{'username': 'root'}, {'username': 'bad:name'}, {'password': 'short'},
                        {'password': 'validlength\nroot:other'}, {'name': 'name:bad'}]:
            self.assertFalse(backend.handle(self.request | changes, '/bin/fish')['ok'])
        with patch.object(backend, 'account_exists', return_value=True):
            self.assertFalse(backend.handle(self.request, '/bin/fish')['ok'])
        run.assert_not_called()

    def test_password_failure_resumes_same_account(self):
        with patch.object(backend, 'account_exists', return_value=False), \
             patch.object(backend.subprocess, 'run', side_effect=[Mock(), subprocess.CalledProcessError(1, 'chpasswd')]):
            with self.assertRaises(subprocess.CalledProcessError):
                backend.handle(self.request, '/bin/fish')
        self.assertEqual(backend.handle({'action': 'status'}, '/bin/fish')['pending'], 'alice')
        self.assertFalse(backend.handle(self.request | {'username': 'bob'}, '/bin/fish')['ok'])
        with patch.object(backend, 'account_exists', return_value=True), \
             patch.object(backend.subprocess, 'run', return_value=Mock()) as run:
            self.assertTrue(backend.handle(self.request, '/bin/fish')['ok'])
            self.assertFalse(any(c.args[0][0] == 'useradd' for c in run.call_args_list))
        with patch.object(backend.subprocess, 'run') as run:
            self.assertTrue(backend.handle({'action': 'status'}, '/bin/fish')['complete'])
            backend.handle(self.request, '/bin/fish')
            run.assert_not_called()

    @patch.object(backend, 'account_exists', return_value=False)
    @patch.object(backend.subprocess, 'run', return_value=Mock())
    def test_display_name_cannot_inject_nix_expression(self, run, exists):
        backend.handle(self.request | {'name': '${builtins.abort "oops"}'}, '/bin/fish')
        self.assertIn('\\${builtins.abort', (self.config / 'owner.nix').read_text())

    @unittest.skipUnless(hasattr(socket, 'SO_PEERCRED'), 'Linux peer credentials')
    def test_socket_checks_peer_before_handling_request(self):
        for allowed in (True, False):
            server, client = socket.socketpair()
            listener = Mock()
            listener.accept.side_effect = [(server, None), KeyboardInterrupt()]
            with client, patch.object(backend.socket, 'socket', return_value=listener), \
                 patch.object(backend.pwd, 'getpwnam', return_value=Mock(pw_uid=os.getuid() if allowed else os.getuid() + 1)), \
                 patch.dict(os.environ, {'LISTEN_PID': str(os.getpid()), 'LISTEN_FDS': '1'}), \
                 patch.object(backend, 'handle', return_value={'ok': True}) as handle:
                client.sendall(json.dumps({'action': 'status'}).encode() + b'\n')
                with self.assertRaises(KeyboardInterrupt):
                    backend.serve('/bin/fish')
                if allowed:
                    self.assertTrue(json.loads(client.recv(4096))['ok'])
                    handle.assert_called_once()
                else:
                    handle.assert_not_called()


if __name__ == '__main__':
    unittest.main()
