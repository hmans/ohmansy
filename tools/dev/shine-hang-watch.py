#!/usr/bin/env python3
"""Observe an existing Shine process; save diagnostics on IPC stalls, never restart it."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import socket
import subprocess
import time


def identity(pid):
    # The command name can contain spaces; field 22 follows the closing ')'.
    fields = (Path('/proc') / str(pid) / 'stat').read_text().rsplit(')', 1)[1].split()
    return fields[19]


def status(path, pid):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(4)
        connection.connect(path)
        connection.sendall(b'{"action":"status"}\n')
        with connection.makefile('rb') as stream:
            reply = json.loads(stream.readline(2 * 1024 * 1024))
    if not reply.get('ok'):
        raise RuntimeError(reply.get('error', 'Unsuccessful IPC response'))
    state = reply['state']
    if state['pid'] != pid:
        raise RuntimeError('Socket belongs to a different process; refusing to follow it')
    return {key: state.get(key) for key in (
        'pid', 'backend', 'rendered_frames', 'surface_commits', 'config_revision', 'config_error')}


def threads(pid):
    result = {}
    for thread in sorted((Path('/proc') / str(pid) / 'task').glob('*')):
        item = {}
        for name in ('comm', 'wchan', 'stat', 'syscall', 'stack'):
            try:
                item[name] = (thread / name).read_text().strip()
            except OSError as error:
                item[name] = str(error)
        result[thread.name] = item
    return result


def capture(directory, pid, error, last):
    path = directory / datetime.now(timezone.utc).strftime('stall-%Y%m%dT%H%M%SZ')
    path.mkdir(mode=0o700)
    samples = [threads(pid)]
    time.sleep(1)
    samples.append(threads(pid))
    report = {'pid': pid, 'error': str(error), 'last_response': last, 'threads': samples}
    with (path / 'report.json').open('w') as output:
        json.dump(report, output, indent=2)
        output.flush()
        os.fsync(output.fileno())
    for name, extra in [('session', ['-t', 'ohmansy-session']), ('kernel', ['-k'])]:
        with (path / f'{name}.log').open('w') as output:
            try:
                subprocess.run(['journalctl', '-b', '--since=-2 minutes', '--no-pager', '-n', '100', *extra],
                               stdout=output, stderr=subprocess.STDOUT, timeout=5, check=False)
            except (OSError, subprocess.TimeoutExpired) as exception:
                output.write(str(exception))
    print(f'Shine stalled; diagnostics saved to {path}. No process was restarted.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--socket', required=True)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--once', action='store_true', help='Check once; capture diagnostics on failure')
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    original = identity(args.pid)
    print(f'Watching Shine PID {args.pid} through {args.socket}', flush=True)
    last = None
    failures = 0
    while True:
        try:
            if identity(args.pid) != original:
                return 0
        except OSError:
            return 0
        try:
            last = {'time': datetime.now(timezone.utc).isoformat(), **status(args.socket, args.pid)}
            temporary = args.directory / 'latest.new'
            temporary.write_text(json.dumps(last, indent=2))
            temporary.replace(args.directory / 'latest.json')
            failures = 0
        except (OSError, ValueError, KeyError, RuntimeError) as error:
            failures += 1
            if args.once or failures >= 2:
                capture(args.directory, args.pid, error, last)
                return 1
        if args.once:
            print('Shine responded.', flush=True)
            return 0
        time.sleep(5)


if __name__ == '__main__':
    raise SystemExit(main())
