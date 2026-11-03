"""Local first-boot account service. Activated through a restricted Unix socket."""
import json
import os
from pathlib import Path
import pwd
import socket
import struct
import subprocess
import sys

from setup import valid_username

STATE = Path('/var/lib/ohmansy')
CONFIG = Path('/etc/nixos')


def atomic_write(path, text):
    temporary = path.with_name(path.name + '.tmp')
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        stream.write(text)
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def account_exists(username):
    try:
        pwd.getpwnam(username)
        return True
    except KeyError:
        return False


def handle(request, shell):
    if (STATE / 'provisioned').exists():
        return {'ok': True, 'complete': True}
    pending = STATE / 'pending-owner'
    username = pending.read_text().strip() if pending.exists() else ''
    if request.get('action') == 'status':
        return {'ok': True, 'pending': username}
    if request.get('action') != 'create':
        return {'ok': False, 'error': 'Unknown setup request.'}
    user = request.get('username', '')
    name = request.get('name', '')
    password = request.get('password', '')
    if not isinstance(user, str) or not valid_username(user):
        return {'ok': False, 'error': 'Use a lowercase letter, then letters, digits, - or _ (up to 31 characters).'}
    if not isinstance(name, str) or not name.strip() or len(name) > 80 or any(ord(c) < 32 or c in ':,' for c in name):
        return {'ok': False, 'error': 'Enter a name without colons, commas, or control characters.'}
    if not isinstance(password, str) or not 8 <= len(password) <= 1024 or any(c in password for c in '\n\r\0'):
        return {'ok': False, 'error': 'Use a password with 8–1024 characters and no line breaks.'}
    if username and username != user:
        return {'ok': False, 'error': 'Finish setting up the account from your previous attempt.'}
    if not username and account_exists(user):
        return {'ok': False, 'error': 'That username is already taken.'}
    STATE.mkdir(mode=0o755, parents=True, exist_ok=True)
    if not username:
        atomic_write(pending, user + '\n')
    # Only a root-owned pending record permits resuming an existing account.
    if not account_exists(user):
        subprocess.run(['useradd', '--create-home', '--groups', 'wheel,networkmanager',
                        '--shell', shell, '--comment', name.strip(), user],
                       check=True, capture_output=True)
    # Never put credentials in argv or forward command output into the journal.
    subprocess.run(['chpasswd'], input=user + ':' + password + '\n',
                   text=True, check=True, capture_output=True)
    subprocess.run(['usermod', '--comment', name.strip(), user], check=True, capture_output=True)
    CONFIG.mkdir(parents=True, exist_ok=True)
    nix_name = json.dumps(name.strip(), ensure_ascii=False).replace('${', '\\${')
    atomic_write(CONFIG / 'owner.nix', '{ ... }: { users.users.' + json.dumps(user) + ' = {\n'
                 '  isNormalUser = true; extraGroups = [ "wheel" "networkmanager" ];\n'
                 '  description = ' + nix_name + ';\n}; }\n')
    atomic_write(STATE / 'provisioned', user + '\n')
    pending.unlink(missing_ok=True)
    return {'ok': True}


def serve(shell):
    if os.environ.get('LISTEN_PID') != str(os.getpid()) or os.environ.get('LISTEN_FDS') != '1':
        raise RuntimeError('Start this service through its systemd socket')
    listener = socket.socket(fileno=3)
    allowed_uid = pwd.getpwnam('greeter').pw_uid
    while True:
        connection, _ = listener.accept()
        with connection:
            connection.settimeout(10)
            _, uid, _ = struct.unpack('3i', connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
            if uid != allowed_uid:
                continue
            try:
                payload = bytearray()
                while b'\n' not in payload and len(payload) <= 16384:
                    chunk = connection.recv(4096)
                    if not chunk:
                        break
                    payload.extend(chunk)
                if len(payload) > 16384 or b'\n' not in payload:
                    raise ValueError('Invalid request')
                request = json.loads(payload.split(b'\n', 1)[0])
                if not isinstance(request, dict):
                    raise ValueError('Invalid request')
                response = handle(request, shell)
            except (ValueError, OSError, subprocess.SubprocessError):
                response = {'ok': False, 'error': 'Could not finish setup. Please try again. Your account can be resumed.'}
            try:
                connection.sendall((json.dumps(response) + '\n').encode())
            except OSError:
                pass


if __name__ == '__main__':
    serve(sys.argv[1])
