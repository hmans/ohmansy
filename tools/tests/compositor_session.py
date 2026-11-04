#!/usr/bin/env python3
"""Exercise the packaged session, launcher, and confirmed logout without a VT switch."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

import compositor_integration as trial


def manager_display_environment():
    output = subprocess.check_output(['systemctl', '--user', 'show-environment'], text=True)
    names = {'WAYLAND_DISPLAY', 'DISPLAY', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_DESKTOP'}
    return {key: value for line in output.splitlines()
            for key, _, value in [line.partition('=')] if key in names}


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--headless', action='store_true')
    parser.add_argument('--session', type=Path, default=trial.ROOT / '.local/compositor-session/bin/ohmansy-compositor-session')
    args = parser.parse_args()
    base = trial.ROOT / '.local/compositor-tests'
    base.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='session-', dir=base))
    print(f'Artifacts: {artifacts}', flush=True)
    original = {window['id']: window['pid'] for window in trial.parent_windows()}
    original_focus = next((window['id'] for window in trial.parent_windows() if window['is_focused']), None)
    original_environment = manager_display_environment()
    control = trial.Control(artifacts / 'control.sock')
    trial.TEST_CONTROL = control
    command = [str(args.session)] + ([] if args.headless else ['--nested'])
    command += ['--test-input', '--control-socket', control.path, '--close-after', '60', '--report', str(artifacts / 'state.json')]
    environment = os.environ.copy()
    environment['XDG_CACHE_HOME'] = str(artifacts / 'cache')
    if args.headless:
        environment.update(WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='1', WLR_RENDERER='pixman', LIBGL_ALWAYS_SOFTWARE='1')
    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen(command, env=environment, stdout=log, stderr=log)
        try:
            state = trial.wait_for(control, timeout=25, description='packaged session socket')
            pid = state['pid']
            terminal = trial.wait_for(lambda: next((window for window in control()['windows'] if window['app_id'] == 'foot'), None), description='normal session terminal')
            trial.wait_for(lambda: next(window for window in control()['windows'] if window['id'] == terminal['id'])['render_density'] == 2, description='2x session terminal')
            if not args.headless and original_focus is not None:
                subprocess.run(['niri', 'msg', 'action', 'focus-window', '--id', str(original_focus)], check=True, stdout=subprocess.DEVNULL)
            trial.keys(control, pid, terminal['id'], [32], ('ctrl', 'alt'))
            trial.wait_for(lambda: trial.window_for(control, 'wofi'), description='application picker')
            trial.send_keys([1])
            trial.wait_for(lambda: not trial.window_for(control, 'wofi'), description='picker closing')
            trial.keys(control, pid, terminal['id'], [18], ('ctrl', 'alt', 'shift'))
            trial.wait_for(lambda: trial.window_for(control, 'wofi'), description='sign-out confirmation')
            trial.send_keys([28])
            trial.wait_for(lambda: not trial.window_for(control, 'wofi'), description='cancel sign-out')
            assert process.poll() is None, 'Cancel must keep the session running'
            control('screenshot', path=str(artifacts / 'session.png'))
            trial.wait_for(lambda: (artifacts / 'session.png').exists(), description='session framebuffer')
            trial.keys(control, pid, terminal['id'], [18], ('ctrl', 'alt', 'shift'))
            trial.wait_for(lambda: trial.window_for(control, 'wofi'), description='second sign-out confirmation')
            trial.send_keys([108])
            # Confirming ends the server; there is no key release to deliver.
            control('key', code=28, pressed=True)
            process.wait(timeout=12)
            assert process.returncode == 0, f'Session exited with {process.returncode}'
        finally:
            if process.poll() is None:
                try:
                    control('quit')
                except (OSError, AssertionError):
                    pass
                process.wait(timeout=65)
            remaining = {window['id']: window['pid'] for window in trial.parent_windows()}
            assert all(remaining.get(ident) == pid for ident, pid in original.items()), 'Original desktop windows changed'
            assert manager_display_environment() == original_environment, 'Parent activation environment changed'
    (artifacts / 'verification.json').write_text(json.dumps({
        'backend': 'headless' if args.headless else 'wayland',
        'normal_terminal': True, 'applications': True, 'cancel_logout': True,
        'confirmed_logout': True, 'original_windows_preserved': True,
        'parent_activation_environment_preserved': True,
    }, indent=2) + '\n')
    print('PASS: packaged session, 2x terminal, application picker, cancel/confirm sign-out, parent desktop preservation')


if __name__ == '__main__':
    run()
