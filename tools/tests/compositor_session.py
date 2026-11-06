#!/usr/bin/env python3
"""Exercise the packaged session, launcher, and confirmed logout without a VT switch."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

import compositor_support as trial


def manager_display_environment():
    env = dict(os.environ)
    if address := env.get('OHMANSY_TEST_HOST_DBUS'):
        env['DBUS_SESSION_BUS_ADDRESS'] = address
    if runtime := env.get('OHMANSY_TEST_HOST_RUNTIME'):
        env['XDG_RUNTIME_DIR'] = runtime
    output = subprocess.check_output(['systemctl', '--user', 'show-environment'], text=True, env=env)
    names = {'WAYLAND_DISPLAY', 'DISPLAY', 'XDG_CURRENT_DESKTOP', 'XDG_SESSION_DESKTOP', 'XDG_SESSION_TYPE', 'SSH_AUTH_SOCK'}
    return {key: value for line in output.splitlines()
            for key, _, value in [line.partition('=')] if key in names}


def run():
    trial.ensure_test_display()
    parser = argparse.ArgumentParser(description=__doc__)
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
    command = [str(args.session), '--nested']
    command += ['--test-input', '--config', str(artifacts / 'config.toml'), '--control-socket', control.path, '--close-after', '60', '--report', str(artifacts / 'state.json')]
    environment = os.environ.copy()
    environment['XDG_CACHE_HOME'] = str(artifacts / 'cache')
    shortcut = ('super', 'alt')
    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen(command, env=environment, stdout=log, stderr=log)
        try:
            state = trial.wait_for(control, timeout=25, description='packaged session socket')
            pid = state['pid']
            probe = artifacts / 'child-environment.json'
            code = ('import json,os,pathlib; '
                    f'pathlib.Path({str(probe)!r}).write_text(json.dumps('
                    '{k:os.environ.get(k) for k in ["DBUS_SESSION_BUS_ADDRESS","WAYLAND_DISPLAY","SSH_AUTH_SOCK"]}))')
            control('launch', program=sys.executable, args=['-c', code])
            trial.wait_for(probe.exists, description='nested child environment')
            child = json.loads(probe.read_text())
            assert child['DBUS_SESSION_BUS_ADDRESS'] != os.environ.get('DBUS_SESSION_BUS_ADDRESS'), child
            assert child['DBUS_SESSION_BUS_ADDRESS'] != f'unix:path={os.environ["XDG_RUNTIME_DIR"]}/bus', child
            assert child['WAYLAND_DISPLAY'] == state['wayland_display'], child
            assert child['SSH_AUTH_SOCK'] == os.environ.get('SSH_AUTH_SOCK'), child
            ipc_environment = dict(environment, WAYLAND_DISPLAY=state['wayland_display'])
            def launcher_status():
                instances = json.loads(subprocess.check_output(
                    ['quickshell', 'list', '--all', '--json'], env=ipc_environment, text=True))
                for instance in instances:
                    if 'shine-shell' not in instance['config_path']:
                        continue
                    result = subprocess.run(['quickshell', 'ipc', '--pid', str(instance['pid']),
                        'call', 'launcher', 'status'], env=ipc_environment, text=True, capture_output=True)
                    if result.returncode == 0:
                        return json.loads(result.stdout)
                raise AssertionError('No launcher IPC for the packaged session')
            trial.wait_for(lambda: not launcher_status()['opened'], description='launcher ready')
            terminal = trial.wait_for(lambda: next((window for window in control()['windows'] if window['app_id'] == 'foot'), None), description='normal session terminal')
            # Pixel dimensions round fractional products to whole pixels.
            trial.wait_for(lambda: abs(next(window for window in control()['windows'] if window['id'] == terminal['id'])['render_density'] - control()['display_scale']) < .01, description='monitor-matched session terminal')
            if original_focus is not None:
                trial.focus_parent_window(original_focus)
            trial.keys(control, pid, terminal['id'], [32], shortcut)
            assert not launcher_status()['opened'], 'Mod+D must not open the launcher'
            trial.keys(control, pid, terminal['id'], [57], shortcut)
            trial.wait_for(lambda: launcher_status()['opened'], description='application picker')
            trial.wait_for(lambda: control()['keyboard_focus'] is None, description='overlay receives keyboard focus')
            control.send_keys([1])
            trial.wait_for(lambda: not launcher_status()['opened'], description='picker closing')
            trial.wait_for(lambda: control()['keyboard_focus'] == terminal['id'], description='picker restores app focus')
            trial.keys(control, pid, terminal['id'], [18], shortcut + ('shift',))
            trial.wait_for(lambda: trial.window_for(control, 'wofi'), description='sign-out confirmation')
            control.send_keys([28])
            trial.wait_for(lambda: not trial.window_for(control, 'wofi'), description='cancel sign-out')
            assert process.poll() is None, 'Cancel must keep the session running'
            control('screenshot', path=str(artifacts / 'session.png'))
            trial.wait_for(lambda: (artifacts / 'session.png').exists(), description='session framebuffer')
            trial.keys(control, pid, terminal['id'], [18], shortcut + ('shift',))
            trial.wait_for(lambda: trial.window_for(control, 'wofi'), description='second sign-out confirmation')
            control.send_keys([108])
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
        'backend': 'wayland',
        'normal_terminal': True, 'applications': True, 'cancel_logout': True,
        'confirmed_logout': True, 'original_windows_preserved': True,
        'parent_activation_environment_preserved': True,
        'private_bus_and_inherited_agent': True,
    }, indent=2) + '\n')
    print('PASS: packaged session, monitor-matched terminal, application picker, cancel/confirm sign-out, parent desktop preservation')


if __name__ == '__main__':
    run()
