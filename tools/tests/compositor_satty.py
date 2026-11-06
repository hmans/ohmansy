#!/usr/bin/env python3
"""Check that Satty's copied PNG survives closing the editor in Shine."""
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile

from PIL import Image
import compositor_support as trial


def run():
    trial.ensure_test_display()
    root = trial.ROOT / '.local/compositor-tests'
    root.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='satty-', dir=root))
    print(f'Artifacts: {artifacts}', flush=True)
    home = artifacts / 'home'
    config = home / '.config/satty'
    config.mkdir(parents=True)
    # Exercise Satty's native Copy action and immediate editor shutdown.
    # The screenshot launcher must supply the persistent clipboard helper.
    (config / 'config.toml').write_text('[general]\nearly-exit = true\n')
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'))
    control = trial.Control(artifacts / 'control.sock')
    original = {w['id']: w.get('pid') for w in trial.parent_windows()}
    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen(['dbus-run-session', '--', str(trial.BINARY),
            '--no-clients', '--test-input', '--config', str(artifacts / 'shine.toml'),
            '--control-socket', control.path, '--close-after', '60'],
            env=env, stdout=log, stderr=log)
        try:
            trial.wait_for(control, description='disposable Shine')
            control('screenshot-screen', path=str(artifacts / 'input.png'), annotate=True)
            shot = trial.wait_for(lambda: control().get('screenshot'), description='screenshot saved')
            assert not shot.get('error') and not shot.get('annotation_error'), shot
            editor = trial.wait_for(lambda: trial.window_for(control, 'com.gabm.satty'),
                                    description='Satty editor')
            trial.wait_for(lambda: control()['keyboard_focus'] == editor['id'], description='Satty focus')
            control.send_keys([46], modifiers=['ctrl'])  # Satty's Copy action.
            trial.wait_for(lambda: not trial.window_for(control, 'com.gabm.satty'),
                           description='Satty exits after Copy')
            clipboard_env = dict(env, WAYLAND_DISPLAY=control()['wayland_display'])
            clipboard_env.pop('WAYLAND_SOCKET', None)
            def pasted():
                result = subprocess.run(['wl-paste', '--no-newline', '--type', 'image/png'],
                    env=clipboard_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
                assert result.returncode == 0, result.stderr.decode()
                with Image.open(io.BytesIO(result.stdout)) as image:
                    image.load()
                    assert image.size == (shot['width'], shot['height']), image.size
                return result.stdout
            data = trial.wait_for(pasted, description='PNG paste after Satty exits')
            (artifacts / 'pasted.png').write_bytes(data)
            (artifacts / 'status.json').write_text(json.dumps(control(), indent=2))
        finally:
            if process.poll() is None:
                control('quit')
                process.wait(timeout=10)
    remaining = {w['id']: w.get('pid') for w in trial.parent_windows()}
    assert all(remaining.get(ident) == pid for ident, pid in original.items())
    print('PASS: Satty Copy serves a complete PNG after editor exit; parent windows preserved')


if __name__ == '__main__':
    run()
