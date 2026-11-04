"""Exercise the real Quickshell greetd client against an isolated IPC server."""
import json
import os
from pathlib import Path
import socket
import shutil
import select
import struct
import subprocess
import tempfile
import unittest


class GreeterAuthTests(unittest.TestCase):
    def run_flow(self, cancel=False, session='niri'):
        with tempfile.TemporaryDirectory() as directory:
            server = socket.socket(socket.AF_UNIX)
            self.addCleanup(server.close)
            address = str(Path(directory) / 'greetd.sock')
            server.bind(address)
            server.listen(1)
            server.settimeout(15)
            env = dict(os.environ, GREETD_SOCK=address, QT_QPA_PLATFORM='offscreen',
                       TEST_CANCEL='1' if cancel else '0', TEST_SESSION=session, XDG_RUNTIME_DIR=directory)
            fixture = Path(directory) / 'shell.qml'
            shutil.copyfile(Path(__file__).with_suffix('.qml'), fixture)
            shutil.copyfile(Path(__file__).parents[1] / 'modules/greeter/Auth.qml', Path(directory) / 'Auth.qml')
            process = subprocess.Popen(['quickshell', '--path', str(fixture)],
                                       env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            try:
                connection, _ = server.accept()
                connection.settimeout(10)
                with connection, connection.makefile('rwb', buffering=0) as stream:
                    def receive():
                        header = stream.read(4)
                        self.assertEqual(len(header), 4, 'greetd client disconnected')
                        size, = struct.unpack('<I', header)
                        return json.loads(stream.read(size))

                    def send(message):
                        payload = json.dumps(message).encode()
                        stream.write(struct.pack('<I', len(payload)) + payload)

                    def challenge(message='Password:', secret=True):
                        send({'type': 'auth_message', 'auth_message_type': 'secret' if secret else 'visible',
                              'auth_message': message})

                    self.assertEqual(receive(), {'type': 'create_session', 'username': 'test-user'})
                    challenge()
                    if cancel:
                        self.assertEqual(receive()['type'], 'cancel_session')
                        self.assertFalse(select.select([connection], [], [], 0.3)[0],
                                         'Wait for cancellation acknowledgement before creating another session')
                        send({'type': 'success'})
                        self.assertEqual(receive(), {'type': 'create_session', 'username': 'other-user'})
                        challenge()
                    self.assertEqual(receive(), {'type': 'post_auth_message_response', 'response': 'test-response'})
                    # A failed password must return to a fresh conversation.
                    send({'type': 'error', 'error_type': 'auth_error', 'description': 'test failure'})
                    self.assertEqual(receive()['type'], 'cancel_session')
                    send({'type': 'success'})
                    request = receive()
                    self.assertEqual(request['type'], 'create_session')
                    self.assertEqual(request['username'], 'other-user' if cancel else 'test-user')
                    challenge()
                    self.assertEqual(receive()['response'], 'test-response')
                    # Additional PAM prompts must honor echoResponse and wait for input.
                    challenge('Verification code:', secret=False)
                    self.assertEqual(receive()['response'], 'test-code')
                    send({'type': 'success'})
                    request = receive()
                    self.assertEqual(request['type'], 'start_session')
                    self.assertEqual(request['cmd'], [f'/test/{session}-session'])
                    self.assertIn('XDG_SESSION_TYPE=wayland', request['env'])
                    self.assertIn(f'XDG_CURRENT_DESKTOP={session}', request['env'])
                    self.assertIn(f'XDG_SESSION_DESKTOP={session}', request['env'])
                    send({'type': 'success'})
                output = process.communicate(timeout=10)[0].decode()
                self.assertEqual(process.returncode, 0, output)
                self.assertNotIn('ERROR', output, output)
                self.assertNotIn('test-response', output, 'Never log authentication responses')
                self.assertNotIn('test-code', output, 'Never log authentication responses')
            finally:
                if process.poll() is None:
                    process.kill()
                output = process.communicate()[0]
                if process.returncode:
                    print(output.decode())

    def test_retry_and_additional_prompt(self):
        self.run_flow()

    def test_switch_account_cancels_conversation(self):
        self.run_flow(cancel=True)

    def test_experimental_session_survives_auth_retry(self):
        self.run_flow(session='ohmansy')


if __name__ == '__main__':
    unittest.main()
