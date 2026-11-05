#!/usr/bin/env python3
"""Exercise Quickshell panels inside a disposable Shine compositor."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

import compositor_integration as trial


def run():
    root = trial.ROOT / '.local/compositor-tests'
    root.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='shell-', dir=root))
    print(f'Artifacts: {artifacts}', flush=True)
    config = artifacts / 'config.toml'
    config.write_text('[animations]\nenabled=false\n')
    control = trial.Control(artifacts / 'control.sock')
    original = {w['id']: w['pid'] for w in trial.parent_windows()}
    shell = None
    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--test-input',
            '--outputs', '2', '--config', str(config), '--control-socket', control.path,
            '--close-after', '120'], stdout=log, stderr=log)
        try:
            state = trial.wait_for(control, description='Shine')
            environment = dict(os.environ, WAYLAND_DISPLAY=state['wayland_display'],
                               OHMANSY_COMPOSITOR_CONTROL=os.path.relpath(control.path),
                               PWD=str(Path.cwd()), QT_QPA_PLATFORM='wayland')
            environment.pop('WAYLAND_SOCKET', None)
            environment.pop('NIRI_SOCKET', None)
            shell = subprocess.Popen([os.environ['OHMANSY_COMPOSITOR_SHELL']],
                                     env=environment, stdout=log, stderr=log)
            trial.wait_for(lambda: all(o['work_area'][1] == 44 and len(o['layers']) == 1
                                      for o in control()['outputs']), description='two panels')
            control('launch', program='foot', args=['--app-id=shine-shell-test', 'sleep', '100'])
            window = trial.wait_for(lambda: trial.window_for(control, 'shine-shell-test'))
            trial.wait_for(lambda: trial.window_for(control, 'shine-shell-test')['geometry'][1] == 56,
                           description='reserved panel space')
            focused = control()['keyboard_focus']

            def click(output, x):
                control('pointer', x=output['position'][0] + x, y=output['position'][1] + 22)
                control('button', pressed=True)
                control('button', pressed=False)

            first, second = control()['outputs']
            # Brand, four workspace buttons, then Terminal in the left row.
            click(first, 95)
            assert control()['keyboard_focus'] == focused, 'Panel stole keyboard focus'
            click(second, 135)
            trial.wait_for(lambda: control()['outputs'][1]['workspace'] == 2,
                           description='workspace button targets its monitor')
            assert control()['outputs'][0]['workspace'] == 1
            click(second, 260)
            trial.wait_for(lambda: len(control()['windows']) == 2, description='panel terminal')
            assert next(w for w in control()['windows'] if w['id'] != window['id'])['output'] == second['name']
            control('focus', window['id'])
            control('fullscreen')
            assert trial.window_for(control, 'shine-shell-test')['geometry'] == [
                *first['position'], *first['logical_size']]
            control('fullscreen')
            control('output', 1)
            control('scale', 150)
            trial.wait_for(lambda: control()['outputs'][0]['layers'][0]['geometry'][2] ==
                           control()['outputs'][0]['logical_size'][0], description='panel follows scale')
            control('screenshot', path=str(artifacts / 'panel.png'))
            trial.wait_for((artifacts / 'panel.png').exists, description='panel screenshot')
            (artifacts / 'status.json').write_text(json.dumps(control(), indent=2))
            shell.terminate()
            shell.wait(timeout=10)
            trial.wait_for(lambda: all(o['work_area'][1] == 0 and not o['layers']
                                      for o in control()['outputs']), description='panel space released')
            assert trial.window_for(control, 'shine-shell-test')['geometry'][1] == 12
            shell = subprocess.Popen([os.environ['OHMANSY_COMPOSITOR_SHELL']],
                                     env=environment, stdout=log, stderr=log)
            trial.wait_for(lambda: all(len(o['layers']) == 1 for o in control()['outputs']),
                           description='panels restart')
            control('quit')
            process.wait(timeout=10)
            shell.wait(timeout=10)
            assert process.returncode == 0
        finally:
            if shell and shell.poll() is None:
                shell.terminate()
                shell.wait(timeout=10)
            if process.poll() is None:
                control('quit')
                process.wait(timeout=10)
    remaining = {w['id']: w['pid'] for w in trial.parent_windows()}
    assert all(remaining.get(ident) == pid for ident, pid in original.items())
    print('PASS: two panels, reserved space, workspace/terminal clicks, keyboard focus, '
          'fullscreen, scale, clean panel exit and parent windows preserved')


if __name__ == '__main__':
    run()
