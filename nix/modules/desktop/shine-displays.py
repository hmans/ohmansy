"""Shine display choices with a confirmed, reversible preview."""
import argparse
import fcntl
import json
import math
import os
from pathlib import Path
import select
import signal
import socket
import sys
import time


def control(action='status', **fields):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(5)
        connection.connect(os.environ['OHMANSY_COMPOSITOR_CONTROL'])
        connection.sendall((json.dumps(dict(action=action, **fields)) + '\n').encode())
        with connection.makefile() as stream:
            reply = json.loads(stream.readline())
    if not reply.get('ok'):
        raise RuntimeError(reply.get('error', 'Shine could not change the display.'))
    return reply['state']


def mode_name(mode):
    return f'{mode["width"]}x{mode["height"]}@{mode["refresh"] / 1000:.3f}'


def display_list():
    result = []
    for output in control()['outputs']:
        mode = output['mode']
        if not mode:
            continue
        modes = {mode_name(item): item for item in output['modes']
                 if (item['width'], item['height']) == (mode['width'], mode['height'])}
        result.append(dict(name=output['name'],
                           label=' '.join(filter(None, [output['make'], output['model']])) or output['name'],
                           scale=output['scale'], mode=mode_name(mode),
                           resolution=f'{mode["width"]} × {mode["height"]}',
                           rates=[dict(mode=key, label=f'{value["refresh"] / 1000:.3f} Hz')
                                  for key, value in sorted(modes.items(), key=lambda pair: pair[1]['refresh'])]))
    return result


def emit(**state):
    print(json.dumps(state), flush=True)


def matching(state, snapshot):
    return next((o for o in state['outputs'] if o['name'] == snapshot['name']
                 and o['id'] == snapshot['id']), None)


def wait_applied(snapshot, scale, mode):
    deadline = time.monotonic() + 5
    while True:
        state = control()
        output = matching(state, snapshot)
        if output is None:
            raise ValueError('The display was disconnected. Refresh the display list.')
        if state['config_error']:
            raise RuntimeError(state['config_error'])
        if mode_name(output['mode']) == mode and abs(output['scale'] - scale) < 0.001:
            return
        if time.monotonic() >= deadline:
            raise RuntimeError('The display did not accept those settings.')
        time.sleep(.05)


def preview(name, scale, mode, decision=None):
    before = control()
    snapshot = next((o for o in before['outputs'] if o['name'] == name), None)
    if snapshot is None:
        raise ValueError('The display was disconnected. Refresh the display list.')
    if not math.isfinite(scale) or not 0.5 <= scale <= 2:
        raise ValueError('Choose a scale between 50% and 200%.')
    if not any(mode_name(m) == mode and (m['width'], m['height']) ==
               (snapshot['mode']['width'], snapshot['mode']['height']) for m in snapshot['modes']):
        raise ValueError('That refresh rate is no longer available. Refresh the display list.')
    kept = False
    try:
        change = dict(name=name, scale=scale)
        if mode != mode_name(snapshot['mode']):
            change['mode'] = mode
        control('configure-outputs', outputs=[change])
        wait_applied(snapshot, scale, mode)
        emit(status='preview', seconds=15)
        if decision is None:
            decision = sys.stdin.readline().strip() if select.select([sys.stdin], [], [], 15)[0] else 'revert'
        if decision == 'keep':
            wait_applied(snapshot, scale, mode)
            control('save-config')
            kept = True
            emit(status='kept')
    finally:
        if not kept:
            live = control()
            # Scale changes can move neighbouring outputs. Restore their
            # positions atomically too, but never configure a replacement panel.
            changes = []
            for output in before['outputs']:
                current = matching(live, output)
                if current is None:
                    continue
                change = dict(name=output['name'], scale=output['scale'],
                              position=output['position'], primary=output['primary'])
                if live.get('backend') != 'winit' or current['mode'] != output['mode']:
                    change['mode'] = mode_name(output['mode'])
                changes.append(change)
            if changes:
                control('configure-outputs', outputs=changes)
                for output in before['outputs']:
                    if matching(live, output):
                        wait_applied(output, output['scale'], mode_name(output['mode']))
            emit(status='reverted')


def interrupted(_signum, _frame):
    raise RuntimeError('Display preview interrupted.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('list')
    test = sub.add_parser('preview')
    test.add_argument('output')
    test.add_argument('scale', type=float)
    test.add_argument('mode')
    args = parser.parse_args()
    try:
        if args.action == 'list':
            print(json.dumps(display_list()))
        else:
            lock_path = Path(os.environ['XDG_RUNTIME_DIR']) / 'ohmansy-shine-displays.lock'
            with lock_path.open('w') as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise RuntimeError('Another display change is in progress.') from None
                signal.signal(signal.SIGTERM, interrupted)
                preview(args.output, args.scale, args.mode)
    except (ValueError, RuntimeError, OSError, KeyError) as error:
        emit(status='error', message=str(error))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
