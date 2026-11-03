#!/usr/bin/env python3
"""Remove unused host artifacts. Guest disks require --retire-vm NAME."""

import argparse
from contextlib import ExitStack
import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PATTERNS = ('.build', 'dist/Ohmansy-before-*.app', 'dist/Ohmansy.before-*.app',
            'dist/*-check', 'dist/*-update', 'dist/check', 'dist/releases', 'dist/images')


def checked_path(root, path):
    if not path.is_relative_to(root) or path == root:
        raise ValueError(f'Outside cleanup scope: {path}')
    for part in (path, *path.parents):
        if part == root:
            break
        if part.is_symlink():
            raise ValueError(f'Refusing symlink: {part}')
    if not path.is_dir():
        raise ValueError(f'Not a directory: {path}')
    return path


def candidates(root, retired):
    result = {}
    for pattern in PATTERNS:
        for path in root.glob(pattern):
            checked_path(root, path)
            if any(path.rglob('disk.raw')):
                raise ValueError(f'Guest disk inside build artifacts: {path}')
            result[path] = False
    for name in retired:
        if not name or name.startswith('.') or Path(name).name != name:
            raise ValueError('--retire-vm requires a directory name directly under .local')
        path = checked_path(root, root / '.local' / name)
        for marker in ('disk.raw', 'factory.json', 'lock'):
            if (path / marker).is_symlink() or not (path / marker).is_file():
                raise ValueError(f'Not a recognized factory VM: {path}')
        result[path] = True
    return result


def activity():
    processes = subprocess.run(['ps', '-axo', 'command='], check=True,
                               capture_output=True, text=True).stdout
    files = subprocess.run(['lsof', '-nP', '-a', '-u', str(os.getuid()),
                            '-p', f'^{os.getpid()}', '-Fn'],
                           capture_output=True, text=True)
    # Fail closed: restricted process visibility must not permit deletion.
    if files.returncode != 0 or files.stderr:
        raise RuntimeError('Cannot inspect open files: ' + files.stderr.strip())
    return processes, [line[1:] for line in files.stdout.splitlines() if line.startswith('n/')]


def in_use(path, processes, files):
    name = str(path)
    return name in processes or any(p == name or p.startswith(name + '/') for p in files)


def allocated(path):
    # Do not follow symlinks or count sparse disks by their logical capacity.
    return sum(p.lstat().st_blocks * 512 for p in path.rglob('*') if not p.is_symlink())


def clean(root, retired=(), dry_run=False):
    targets = candidates(root, retired)
    removed = 0
    with ExitStack() as locks:
        ready = []
        processes, files = activity()
        for path, vm in targets.items():
            if in_use(path, processes, files):
                print(f'Skip in use: {path.relative_to(root)}')
                continue
            if vm:
                # Match the runtime lock and keep it until deletion completes.
                lock = locks.enter_context((path / 'lock').open('r+b'))
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    print(f'Skip running VM: {path.relative_to(root)}')
                    continue
            ready.append(path)
        before = shutil.disk_usage(root).free
        for path in ready:
            size = allocated(path)
            print(f'{"Would remove" if dry_run else "Remove"}: '
                  f'{path.relative_to(root)} ({size / 1024**3:.2f} GiB allocated)', flush=True)
            if not dry_run:
                # Recheck activity immediately before each removal.
                if in_use(path, *activity()):
                    print('  Skip: now in use')
                    continue
                checked_path(root, path)
                shutil.rmtree(path)
            removed += size
        print(f'{"Selected" if dry_run else "Removed"}: {removed / 1024**3:.2f} GiB allocated')
        if not dry_run:
            delta = shutil.disk_usage(root).free - before
            print(f'Host free-space change: {delta / 1024**3:+.2f} GiB '
                  '(APFS shared blocks and snapshots can affect this)')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true', help='list candidates without deletion')
    parser.add_argument('--retire-vm', action='append', default=[], metavar='NAME',
                        help='permanently delete this stopped factory VM under .local (repeatable)')
    args = parser.parse_args()
    try:
        clean(ROOT, args.retire_vm, args.dry_run)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))


if __name__ == '__main__':
    main()
