#!/usr/bin/env python3
"""Exercise user screenshots, image clipboard, and annotation in isolated Shine."""
import os
import json
import shlex
import shutil
from pathlib import Path
import subprocess
import tempfile
import time

import compositor_integration as trial
from compositor_decorations import png_pixels


def run():
    root = trial.ROOT / '.local/compositor-tests'
    root.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='screenshots-', dir=root))
    print(f'Artifacts: {artifacts}', flush=True)
    home = artifacts / 'home'
    home.mkdir()
    config_dir = home / '.config'
    config_dir.mkdir()
    pictures = home / 'My Pictures'
    (config_dir / 'user-dirs.dirs').write_text(f'XDG_PICTURES_DIR="{pictures}"\n')
    config = artifacts / 'shine.toml'
    config.write_text('[animations]\nenabled=false\n')
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config_dir))
    helpers = artifacts / 'bin'
    helpers.mkdir()
    clipboard_failure = artifacts / 'fail-clipboard'
    clipboard = helpers / 'wl-copy'
    clipboard.write_text('#!/bin/sh\nif [ -e ' + shlex.quote(str(clipboard_failure))
        + ' ]; then exit 1; fi\nexec ' + shlex.quote(shutil.which('wl-copy')) + ' "$@"\n')
    clipboard.chmod(0o755)
    env['PATH'] = str(helpers) + ':' + env['PATH']
    control = trial.Control(artifacts / 'control.sock')
    trial.TEST_CONTROL = control
    original = {w['id']: w['pid'] for w in trial.parent_windows()}

    def capture(path=None, **options):
        before = control()
        control('screenshot-screen', **({'path': str(path)} if path else {}), **options)
        result = trial.wait_for(lambda: control().get('screenshot'), description='screenshot completion')
        assert 'error' not in result, result
        assert result['clipboard'], result
        destination = Path(result['path'])
        clipboard_env = dict(env, WAYLAND_DISPLAY=control()['wayland_display'])
        clipboard_env.pop('WAYLAND_SOCKET', None)
        copied = subprocess.check_output(['wl-paste', '--no-newline', '--type', 'image/png'], env=clipboard_env, timeout=10)
        assert copied == destination.read_bytes(), result
        if not options.get('annotate'):
            try:
                trial.wait_for(lambda: any(layer['namespace'] == 'ohmansy-screenshot-result'
                    for output in control()['outputs'] if output['name'] == result['output']
                    for layer in output['layers']), description='screenshot result popup')
            except AssertionError:
                (artifacts / 'failed-state.json').write_text(json.dumps(control(), indent=2))
                raise
            after = control()
            assert after['keyboard_focus'] == before['keyboard_focus'], (before, after)
        return result, png_pixels(destination)

    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen(['dbus-run-session', '--', str(trial.BINARY), '--no-clients',
            '--test-input', '--outputs', '2', '--config', str(config),
            '--control-socket', control.path, '--close-after', '120'], env=env, stdout=log, stderr=log)
        try:
            trial.wait_for(control, description='screenshot compositor')
            control('launch', program=os.environ['OHMANSY_COMPOSITOR_SHELL'], args=[])
            trial.wait_for(lambda: all(any(layer['namespace'] == 'ohmansy-shine-bar' for layer in o['layers'])
                for o in control()['outputs']), description='Shine shell')
            capture(artifacts / 'empty.png')
            time.sleep(.3)
            frames = control()['rendered_frames']
            time.sleep(.3)
            assert control()['rendered_frames'] <= frames + 1, 'Capture kept an idle desktop rendering'
            control('launch', program='foot', args=['--app-id=shine-shot-first', '--override=colors.background=226644', 'sleep', '90'])
            first = trial.wait_for(lambda: trial.window_for(control, 'shine-shot-first'))
            control('pointer', x=1000, y=500)
            control('screenshot', path=str(artifacts / 'reference.png'))
            reference = trial.wait_for(lambda: png_pixels(artifacts / 'reference.png'))
            result, pixels = capture()
            assert Path(result['path']).parent == pictures / 'Screenshots', result
            assert result['output'] == 'SHINE-1', result
            assert (result['width'], result['height']) == tuple(control()['outputs'][0]['physical_size']), result
            for y in range(5, 120, 7):
                for x in range(5, 400, 13):
                    assert all(abs(a - b) <= 2 for a, b in zip(pixels(x, y), reference(x, y))), (x, y, pixels(x, y), reference(x, y))
            assert control()['focused'] == first['id'], 'Capture changed focus'
            control('pointer', x=100, y=100)
            _, without_pointer = capture(artifacts / 'without-pointer.png')
            for y in range(110, 145):
                for x in range(110, 145):
                    assert pixels(x, y) == without_pointer(x, y), 'Cursor appeared in screenshot'
            for scale in (100, 150, 200):
                control('scale', scale)
                capture(artifacts / f'scale-{scale}.png')
            control('focus-output-next')
            control('launch', program='foot', args=['--app-id=shine-shot-second', '--override=colors.background=335588', 'sleep', '90'])
            second = trial.wait_for(lambda: trial.window_for(control, 'shine-shot-second'))
            result, _ = capture(artifacts / 'second.png')
            assert result['output'] == 'SHINE-2', result
            assert control()['focused'] == second['id']
            # The notification's transparent area on the other monitor must
            # pass clicks through to the application beneath it.
            state = control()
            output = state['outputs'][0]
            toast = next(layer['geometry'] for layer in output['layers'] if layer['namespace'] == 'ohmansy-screenshot-result')
            window = next(w['geometry'] for w in state['windows'] if w['id'] == first['id'])
            left, top = max(toast[0], window[0]), max(toast[1], window[1])
            right, bottom = min(toast[0] + toast[2], window[0] + window[2]), min(toast[1] + toast[3], window[1] + window[3])
            assert right > left and bottom > top
            control('pointer', x=(left + right) / 2, y=(top + bottom) / 2)
            control('button', pressed=True)
            control('button', pressed=False)
            assert control()['focused'] == first['id'], 'Hidden screenshot popup intercepted a click'
            control('focus', second['id'])
            control('fullscreen')
            capture(artifacts / 'fullscreen.png')
            control('fullscreen')
            # Print uses the same action as the CLI and updates the image selection.
            trial.send_keys([99])
            result = trial.wait_for(lambda: control().get('screenshot'), description='Print screenshot')
            assert result.get('clipboard') and result['output'] == 'SHINE-2', result
            # Refuse replacement, preserve the existing file, then recover.
            existing = artifacts / 'existing.png'
            existing.write_bytes(b'keep this file')
            control('screenshot-screen', path=str(existing))
            error = trial.wait_for(lambda: control().get('screenshot'))
            assert 'error' in error and existing.read_bytes() == b'keep this file', error
            capture(artifacts / 'recovered.png')
            clipboard_failure.touch()
            control('screenshot-screen', path=str(artifacts / 'clipboard-failed.png'))
            result = trial.wait_for(lambda: control().get('screenshot'))
            assert 'error' not in result and not result['clipboard'] and result['clipboard_error'], result
            assert Path(result['path']).exists()
            clipboard_failure.unlink()
            capture(artifacts / 'clipboard-recovered.png')
            capture(artifacts / 'annotate.png', annotate=True)
            trial.wait_for(lambda: any(w['app_id'] == 'com.gabm.satty' for w in control()['windows']), description='Satty annotation window')
            print('PASS: pixels/orientation, two outputs, scaling, fullscreen, PNG clipboard, Print, no overwrite, error recovery, Satty', flush=True)
        finally:
            if process.poll() is None:
                control('quit')
                process.wait(timeout=10)
    remaining = {w['id']: w['pid'] for w in trial.parent_windows()}
    assert all(remaining.get(ident) == pid for ident, pid in original.items())


if __name__ == '__main__':
    run()
