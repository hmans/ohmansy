#!/usr/bin/env python3
"""Send only the official flake to an existing SSH-accessible ARM builder."""
import argparse
from datetime import datetime, timezone
import io
from pathlib import Path
import shlex
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['sync', 'check', 'build', 'fetch'])
    parser.add_argument('--host', required=True, help='SSH destination, e.g. user@127.0.0.1')
    parser.add_argument('--port', type=int, default=2222)
    parser.add_argument('--identity', type=Path, default=ROOT / '.local/ssh/id_ed25519')
    parser.add_argument('--known-hosts', type=Path, default=ROOT / '.local/ssh/known_hosts')
    parser.add_argument('--directory', help='Guest checkout path printed by sync (required except for sync)')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/iso')
    parser.add_argument('--target', choices=['vm-image', 'iso', 'installer-iso'], default='vm-image')
    args = parser.parse_args()
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
