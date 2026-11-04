"""Live-only installer service. The UI may disconnect; installation continues."""
import fcntl
import json
import os
from pathlib import Path
import pwd
import socket
import struct
import subprocess
import threading

import install

STATE = Path('/run/ohmansy-installer/state.json')
LOG = Path('/var/log/ohmansy-install.log')


class Installer:
    def __init__(self):
        self.mutex = threading.RLock()
        self.state = {'status': 'idle', 'stage': '', 'device': '', 'hostname': '', 'error': '', 'destructive': False}
        if STATE.exists():
            self.state.update(json.loads(STATE.read_text()))
            if self.state['status'] == 'running':
                self.state.update(status='failed', destructive=True,
                                  error='Installation was interrupted. Keep the disk intact and inspect the log before attempting recovery.')
                self.save()

    def save(self):
        STATE.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        temporary = STATE.with_suffix('.tmp')
        temporary.write_text(json.dumps(self.state))
        temporary.replace(STATE)

    def snapshot(self):
        with self.mutex:
            result = dict(self.state)
        result['log'] = ''
        if LOG.exists():
            with LOG.open('rb') as stream:
                stream.seek(max(0, LOG.stat().st_size - 24000))
                result['log'] = stream.read(24000).decode(errors='replace')
        return result

    def progress(self, stage):
        with self.mutex:
            self.state.update(stage=stage, destructive=True)
            self.save()

    def work(self, device, hostname, token, lock):
        try:
            with LOG.open('w') as log:
                log.write(f'Ohmansy installation: {device}\nComputer name: {hostname}\n')
                log.flush()
                install.perform_install(device, hostname, token=token, progress=self.progress, log=log)
            with self.mutex:
                self.state.update(status='done', stage='done')
                self.save()
        except (Exception, SystemExit) as error:
            message = (f'{Path(error.cmd[0]).name} stopped with exit code {error.returncode}. Open the installation log for details.'
                       if isinstance(error, subprocess.CalledProcessError) else str(error))
            with self.mutex:
                self.state.update(status='failed', error=message or 'Installation could not finish.')
                self.save()
            with LOG.open('a') as log:
                log.write('\nInstallation stopped: ' + str(error) + '\n')
        finally:
            lock.close()

    def handle(self, request):
        action = request.get('action')
        if action == 'status':
            return {'ok': True, **self.snapshot()}
        with self.mutex:
            if action == 'disks':
                if self.state['status'] == 'running':
                    return {'ok': False, 'error': 'Installation is already running.'}
                if self.state['status'] == 'failed' and not self.state['destructive']:
                    self.state.update(status='idle', error='')
                    self.save()
                install.preflight()
                return {'ok': True, 'disks': [
                    {'path': d['path'], 'size': d['size'], 'model': (d.get('model') or 'Disk').strip(),
                     'token': install.disk_token(d)} for d in install.list_disks()]}
            if action == 'shutdown':
                if self.state['status'] != 'done':
                    return {'ok': False, 'error': 'Finish installation before shutting down here.'}
                subprocess.run(['systemctl', 'poweroff', '--no-block'], check=True)
                return {'ok': True}
            if action != 'start':
                return {'ok': False, 'error': 'Unknown installer request.'}
            if self.state['status'] in ('running', 'done') or self.state['destructive']:
                return {'ok': False, 'error': 'This installation already started. Reopen its progress or inspect its log.'}
            device, hostname, token = (request.get(k) for k in ('device', 'hostname', 'token'))
            if not all(isinstance(v, str) for v in (device, hostname, token)) or not token:
                return {'ok': False, 'error': 'Select a disk again.'}
            if request.get('confirmation') != f'ERASE {device}':
                return {'ok': False, 'error': 'Confirm erasure of the selected disk before installing. No changes made.'}
            lock = install.LOCK.open('w')
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                install.validate_target(device, hostname, token)
                self.state.update(status='running', stage='prepare', device=device, hostname=hostname, error='', destructive=False)
                self.save()
                threading.Thread(target=self.work, args=(device, hostname, token, lock), daemon=True).start()
            except BaseException:
                lock.close()
                raise
            return {'ok': True, **self.snapshot()}


def reply(connection, controller, allowed_uid):
    _, uid, _ = struct.unpack('3i', connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
    if uid != allowed_uid:
        return
    connection.settimeout(3)
    try:
        payload = bytearray()
        while b'\n' not in payload and len(payload) <= 4096:
            chunk = connection.recv(4096)
            if not chunk:
                break
            payload.extend(chunk)
        if len(payload) > 4096 or b'\n' not in payload:
            raise ValueError('Invalid installer request.')
        request = json.loads(payload.split(b'\n', 1)[0])
        if not isinstance(request, dict):
            raise ValueError('Invalid installer request.')
        response = controller.handle(request)
    except BlockingIOError:
        response = {'ok': False, 'error': 'Another installer is already running. Return to its window.'}
    except (Exception, SystemExit) as error:
        response = {'ok': False, 'error': str(error) or 'The installer service could not complete this request.'}
    try:
        connection.sendall((json.dumps(response) + '\n').encode())
    except OSError:
        pass


def serve():
    if os.environ.get('LISTEN_PID') != str(os.getpid()) or os.environ.get('LISTEN_FDS') != '1':
        raise RuntimeError('Start through the installer systemd socket.')
    controller = Installer()
    allowed_uid = pwd.getpwnam('nixos').pw_uid
    with socket.socket(fileno=3) as listener:
        while True:
            connection, _ = listener.accept()
            with connection:
                reply(connection, controller, allowed_uid)


if __name__ == '__main__':
    serve()
