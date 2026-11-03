#!/usr/bin/env python3
"""Send only the official flake to an existing SSH-accessible ARM builder."""
import argparse
from datetime import datetime, timezone
import io
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def access_module(user, public_key):
    """Render a private, opt-in overlay; never include it in source_archive()."""
    if not re.fullmatch(r'[a-z_][a-z0-9_-]*', user) or user in {'root', 'nixos'}:
        raise ValueError('Use the existing, non-root installed owner account')
    fields = public_key.strip().split()
    if len(fields) < 2 or fields[0] != 'ssh-ed25519' or not re.fullmatch(r'[A-Za-z0-9+/]+={0,2}', fields[1]):
        raise ValueError('Expected an OpenSSH Ed25519 public key')
    # Drop the optional comment; neither value can contain Nix interpolation.
    key = ' '.join(fields[:2])
    template = (ROOT / 'tools/dev/guest-access.nix.in').read_text()
    return template.replace('@USER@', json.dumps(user)).replace('@KEY@', json.dumps(key))


def write_access_module(user, key_path, output):
    output = output.resolve()
    if not output.is_relative_to((ROOT / '.local').resolve()):
        raise ValueError('Development overlays must be written under .local/')
    content = access_module(user, key_path.read_text())
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('x') as stream:
        output.chmod(0o600)
        stream.write(content)
    return output


def source_archive():
    data = io.BytesIO()
    with tarfile.open(fileobj=data, mode='w:gz') as archive:
        for name in ['flake.nix', 'flake.lock', 'nix']:
            path = ROOT / name
            paths = [path] if path.is_file() else sorted(path.rglob('*'))
            for item in paths:
                if '__pycache__' in item.parts or item.suffix == '.pyc':
                    continue
                if item.is_symlink():
                    raise ValueError(f'Refusing source symlink: {item}')
                if item.is_file():
                    archive.add(item, arcname=str(item.relative_to(ROOT)), recursive=False)
    return data.getvalue()


def runtime_module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'app/runtime' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def forwarded(usernet, port):
    for line in usernet.splitlines():
        fields = line.split()
        if (len(fields) >= 6 and fields[0] == 'TCP[HOST_FORWARD]'
                and fields[2] == '127.0.0.1' and fields[3] == str(port) and fields[5] == '22'):
            return True
    return False


def bridge(state, port, enable=True):
    state = state.resolve()
    if not state.is_relative_to((ROOT / '.local').resolve()):
        raise ValueError('Development bridge state must be under this checkout\'s .local/')
    if not (state / 'factory.json').is_file() or not (state / 'disk.raw').is_file():
        raise ValueError('Select an existing factory VM; this command never creates a disk')
    if not 1024 <= port <= 65535:
        raise ValueError('Use an unprivileged SSH port between 1024 and 65535')
    settings = state / 'development.json'
    previous = runtime_module('factory-vm').development_ssh_port(state)
    if previous and enable and previous != port:
        raise ValueError('Disable the existing bridge before changing its port')
    if not enable:
        if not previous:
            print('No development bridge is configured.')
            return
        port = previous
    live = False
    if (state / 'qmp.sock').exists():
        qmp = runtime_module('gpu-probe').qmp_command
        try:
            usernet = qmp(state, 'human-monitor-command', {'command-line': 'info usernet'})
        except (ConnectionRefusedError, FileNotFoundError):
            pass  # A stopped VM can leave a stale socket.
        else:
            live = True
            present = forwarded(usernet, port)
            if enable != present:
                operation = (f'hostfwd_add net tcp:127.0.0.1:{port}-:22' if enable
                             else f'hostfwd_remove net tcp:127.0.0.1:{port}')
                reply = qmp(state, 'human-monitor-command', {'command-line': operation})
                if enable and reply.strip():
                    raise ValueError('Could not enable SSH forwarding: ' + reply.strip())
                updated = qmp(state, 'human-monitor-command', {'command-line': 'info usernet'})
                if forwarded(updated, port) != enable:
                    raise ValueError('SSH forwarding did not reach the requested state')
    if enable:
        fd, temporary = tempfile.mkstemp(prefix='.development-', dir=state)
        try:
            with os.fdopen(fd, 'w') as output:
                json.dump({'schemaVersion': 1, 'sshPort': port}, output)
            os.replace(temporary, settings)
        finally:
            Path(temporary).unlink(missing_ok=True)
    else:
        settings.unlink(missing_ok=True)
    print(f'Development SSH forward {"enabled" if enable else "disabled"}: 127.0.0.1:{port}'
          + (' (running VM updated)' if live else ' (takes effect on next launch)'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare-access', 'bridge', 'unbridge', 'sync', 'check', 'build', 'fetch'])
    parser.add_argument('--state', type=Path, help='Existing .local/ factory VM for bridge/unbridge')
    parser.add_argument('--host', help='SSH destination, e.g. user@127.0.0.1')
    parser.add_argument('--guest-user', help='Existing guest owner for prepare-access')
    parser.add_argument('--public-key', type=Path, help='Ed25519 public key for prepare-access')
    parser.add_argument('--access-output', type=Path, default=ROOT / '.local/development-access.nix')
    parser.add_argument('--port', type=int, default=2222)
    parser.add_argument('--identity', type=Path, default=ROOT / '.local/ssh/id_ed25519')
    parser.add_argument('--known-hosts', type=Path, default=ROOT / '.local/ssh/known_hosts')
    parser.add_argument('--directory', help='Guest checkout path printed by sync (required except for sync)')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/iso')
    parser.add_argument('--target', choices=['vm-image', 'iso', 'installer-iso'], default='vm-image')
    args = parser.parse_args()
    if args.action in ('bridge', 'unbridge'):
        if not args.state:
            parser.error('--state is required for bridge/unbridge')
        try:
            key = None
            if args.action == 'bridge' and args.public_key:
                fields = args.public_key.read_text().strip().split()
                access_module('developer', ' '.join(fields))
                key = ' '.join(fields[:2])
            bridge(args.state, args.port, args.action == 'bridge')
        except (OSError, ValueError, RuntimeError) as error:
            parser.error(str(error))
        if key:
            print('Run once in the guest: sudo ohmansy-dev enable --public-key ' + shlex.quote(key))
        return
    if args.action == 'prepare-access':
        if not args.guest_user or not args.public_key:
            parser.error('prepare-access requires --guest-user and --public-key')
        try:
            print(write_access_module(args.guest_user, args.public_key, args.access_output))
        except (ValueError, OSError) as error:
            parser.error(str(error))
        return
    if not args.host:
        parser.error('--host is required for SSH actions')
    if args.host.startswith('-'):
        parser.error('Invalid SSH destination')
    ssh = ['ssh', '-p', str(args.port), '-i', str(args.identity),
           '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes',
           '-o', 'StrictHostKeyChecking=yes', '-o', f'UserKnownHostsFile={args.known_hosts}', args.host]
    if args.action == 'sync':
        # Each sync creates a new writable snapshot; guest edits are never overwritten.
        snapshot = 'ohmansy-dev/' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        command = f'umask 077; mkdir -p {shlex.quote(snapshot)} && tar -xzf - -C {shlex.quote(snapshot)} && realpath {shlex.quote(snapshot)}'
        subprocess.run(ssh + [command], input=source_archive(), check=True)
        return
    if not args.directory or not args.directory.startswith('/'):
        parser.error('--directory must be the absolute guest checkout path printed by sync')
    directory = shlex.quote(args.directory)
    commands = {
        'check': f'cd {directory} && nix flake check --no-update-lock-file path:.',
        'build': f'cd {directory} && nix build --no-update-lock-file --out-link result path:.#{args.target}',
        'fetch': (f'cd {directory}/result && tar -cf - -- *.raw.zst' if args.target == 'vm-image'
                  else f'cd {directory}/result/iso && tar -cf - -- *.iso'),
    }
    if args.action != 'fetch':
        subprocess.run(ssh + [commands[args.action]], check=True)
        return
    args.output.mkdir(parents=True, exist_ok=True)
    # Stream multi-gigabyte images without retaining the archive in RAM.
    with subprocess.Popen(ssh + [commands['fetch']], stdout=subprocess.PIPE) as process:
        with tarfile.open(fileobj=process.stdout, mode='r|') as archive:
            for member in archive:
                suffix = '.raw.zst' if args.target == 'vm-image' else '.iso'
                if not member.isfile() or '/' in member.name or not member.name.endswith(suffix):
                    raise ValueError(f'Unexpected build artifact: {member.name}')
                target = args.output / member.name
                with target.open('xb') as destination, archive.extractfile(member) as source:
                    import shutil
                    shutil.copyfileobj(source, destination)
                print(target)
        if process.wait() != 0:
            raise RuntimeError('Guest artifact transfer failed')


if __name__ == '__main__':
    main()
