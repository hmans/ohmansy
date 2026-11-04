"""Per-user Niri display preferences and reversible output previews."""
import argparse
import fcntl
import json
import math
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile


def niri(*args):
    result = subprocess.run(['niri', 'msg', *args], capture_output=True, text=True, timeout=5)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or 'Niri could not change the display.')
    return result.stdout


def outputs():
    return json.loads(niri('--json', 'outputs'))


def mode_name(mode):
    return f'{mode["width"]}x{mode["height"]}@{mode["refresh_rate"] / 1000:.3f}'


def identity(output):
    return [output.get(key, '') for key in ('make', 'model', 'serial')]


def current(output):
    index = output.get('current_mode')
    if index is None or not output.get('logical'):
        raise ValueError('This display is disabled or disconnected. Refresh the display list.')
    return output['modes'][index]


def display_list():
    result = []
    for name, output in sorted(outputs().items()):
        if output.get('current_mode') is None or not output.get('logical'):
            continue
        mode = current(output)
        modes = {mode_name(item): item for item in output['modes']
                 if (item['width'], item['height']) == (mode['width'], mode['height'])}
        result.append(dict(name=name, label=' '.join(filter(None, [output.get('make'), output.get('model')])) or name,
                           scale=output['logical']['scale'], mode=mode_name(mode),
                           resolution=f'{mode["width"]} × {mode["height"]}',
                           rates=[dict(mode=key, label=f'{value["refresh_rate"] / 1000:.3f} Hz')
                                  for key, value in sorted(modes.items(), key=lambda pair: pair[1]['refresh_rate'])]))
    return result


def preferences_path():
    return Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'ohmansy/displays.json'


def read_preferences(path):
    return json.loads(path.read_text()) if path.exists() else {}


def save_preferences(path, name, output, scale, mode):
    preferences = read_preferences(path)
    preferences[name] = dict(identity=identity(output), scale=scale, mode=mode)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix='.displays-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(preferences, stream, indent=2)
            stream.write('\n')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def validate(output, scale, mode, same_resolution=True):
    old = current(output)
    if not math.isfinite(scale) or not 0.5 <= scale <= 4:
        raise ValueError('Choose a scale between 50% and 400%.')
    candidates = [item for item in output['modes'] if mode_name(item) == mode]
    if not candidates or (same_resolution and any(
            (item['width'], item['height']) != (old['width'], old['height']) for item in candidates)):
        raise ValueError('That refresh rate is no longer available. Refresh the display list.')


def apply(name, scale, mode):
    niri('output', name, 'mode', mode)
    niri('output', name, 'scale', str(scale))


def emit(**state):
    print(json.dumps(state), flush=True)


def preview(name, scale, mode, path, decision=None):
    snapshot = outputs().get(name)
    if snapshot is None:
        raise ValueError('The display was disconnected. Refresh the display list.')
    validate(snapshot, scale, mode)
    old_scale, old_mode = snapshot['logical']['scale'], mode_name(current(snapshot))
    kept = False
    try:
        apply(name, scale, mode)
        emit(status='preview', seconds=15)
        # EOF (including a closed panel process) and timeout both revert.
        if decision is None:
            decision = sys.stdin.readline().strip() if select.select([sys.stdin], [], [], 15)[0] else 'revert'
        if decision == 'keep':
            live = outputs().get(name)
            if live is None or identity(live) != identity(snapshot):
                raise ValueError('The display changed while applying settings.')
            if mode_name(current(live)) != mode or abs(live['logical']['scale'] - scale) > 0.01:
                raise ValueError('The display did not accept those settings.')
            save_preferences(path, name, snapshot, scale, mode)
            kept = True
            emit(status='kept')
    finally:
        if not kept:
            # Do not apply the previous display's settings to a replacement.
            live = outputs().get(name)
            if live is not None and identity(live) == identity(snapshot):
                errors = []
                for action, value in [('mode', old_mode), ('scale', str(old_scale))]:
                    try:
                        niri('output', name, action, value)
                    except (RuntimeError, subprocess.SubprocessError) as error:
                        errors.append(str(error))
                if errors:
                    raise RuntimeError('Could not restore display settings: ' + '; '.join(errors))
            emit(status='reverted')


def restore(path):
    available = outputs()
    for name, preference in read_preferences(path).items():
        output = available.get(name)
        if output is None or identity(output) != preference['identity']:
            continue
        try:
            validate(output, preference['scale'], preference['mode'], same_resolution=False)
            apply(name, preference['scale'], preference['mode'])
        except (ValueError, RuntimeError, subprocess.SubprocessError) as error:
            print(f'{name}: {error}', file=sys.stderr)


def interrupted(_signum, _frame):
    raise RuntimeError('Display preview interrupted.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('list')
    sub.add_parser('restore')
    test = sub.add_parser('preview')
    test.add_argument('output')
    test.add_argument('scale', type=float)
    test.add_argument('mode')
    args = parser.parse_args()
    try:
        if args.action == 'list':
            print(json.dumps(display_list()))
        else:
            # Serialize all writers, including login restoration and other panels.
            lock_path = Path(os.environ['XDG_RUNTIME_DIR']) / 'ohmansy-displays.lock'
            with lock_path.open('w') as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise RuntimeError('Another display change is in progress.') from None
                if args.action == 'restore':
                    restore(preferences_path())
                else:
                    signal.signal(signal.SIGTERM, interrupted)
                    preview(args.output, args.scale, args.mode, preferences_path())
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        emit(status='error', message=str(error))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
