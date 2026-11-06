#!/usr/bin/env python3
"""Two advertised outputs, independent workspaces and mixed-scale pointer input."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
import time
from compositor_support import BINARY, ROOT, Control, ensure_test_display, parent_windows, wait_for


def main():
    ensure_test_display()
    base = ROOT / '.local/compositor-monitors'
    base.mkdir(parents=True, exist_ok=True)
    base = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    path = base / f'{os.getpid()}.sock'
    config = base / 'config.toml'
    config.write_text('[[outputs]]\nname="unplugged-fixture"\nid="edid:fixture:unplugged"\nscale=1.5\n')
    original = {w['id'] for w in parent_windows()}
    with (base / 'compositor.log').open('w') as log:
        process = subprocess.Popen([str(BINARY), '--outputs', '2', '--no-clients',
            '--test-input', '--config', str(config), '--control-socket', str(path), '--close-after', '120'],
            cwd=ROOT, stdout=log, stderr=log)
        control = Control(path)
        def matched_density():
            state = control()
            scales = {o['name']: o['scale'] for o in state['outputs']}
            return state if all(w['render_density'] is not None and
                               abs(w['render_density'] - scales[w['output']]) < .01
                               for w in state['windows']) else None
        def msg(*args, success=True):
            result = subprocess.run([str(BINARY), 'msg', '--socket', str(path), *map(str, args)],
                                    text=True, capture_output=True)
            assert (result.returncode == 0) == success, result.stdout + result.stderr
            return json.loads(result.stdout) if result.stdout else None
        try:
            state = wait_for(lambda: control(), description='two-monitor preview')
            assert len(state['outputs']) == 2, state
            first, second = [o['name'] for o in state['outputs']]
            control('launch', program='foot', args=['--app-id=shine-monitor-one', 'sleep', '90'])
            state = wait_for(lambda: (s if len((s := control())['windows']) == 1 else None))
            ident = state['focused']
            width = state['windows'][0]['width']
            control('fullscreen')
            control('output', 2)
            assert control()['fullscreen'] is None
            control('launch', program='foot', args=['--app-id=shine-monitor-two', 'sleep', '90'])
            state = wait_for(lambda: (s if len((s := control())['windows']) == 2 else None))
            assert {w['output'] for w in state['windows']} == {first, second}, state
            wait_for(matched_density, description='both terminals match their monitors')
            control('workspace', 2)
            assert control()['focused'] is None
            control('output', 1)
            assert control()['focused'] == ident
            assert control()['fullscreen'] == ident
            control('fullscreen')
            control('move-output-next')
            state = control()
            assert next(w for w in state['windows'] if w['id'] == ident)['width'] == width
            assert state['workspace'] == 2
            control('scale', 175)
            state = control()
            assert [o['scale'] for o in state['outputs']] == [1.25, 1.75], state
            # Hidden clients can defer rendering until callbacks resume. Reveal
            # both workspaces before checking their submitted buffer densities.
            control('workspace', 1)
            wait_for(lambda: abs(next(w for w in control()['windows'] if w['app_id'] == 'shine-monitor-two')['render_density'] - 1.75) < .01,
                     description='hidden terminal renders at 175% after workspace reveal')
            control('workspace', 2)
            wait_for(matched_density, description='both terminals use their monitor scale')
            control('move-output-prev')
            wait_for(matched_density, description='moved terminal returns to 125%')
            control('scale', 135)
            wait_for(matched_density, description='135% fractional terminal density')
            control('scale', 125)
            wait_for(matched_density, description='125% fractional terminal density restored')
            control('output', 2)
            control('workspace', 1)
            time.sleep(1)
            screenshot = base / 'two-monitors.png'
            control('screenshot', path=str(screenshot))
            wait_for(screenshot.exists, description='two-monitor screenshot')
            state = control()
            assert state['dmabuf_failures'] == 0, state
            identities = {w['id'] for w in state['windows']}
            # Exercise the public CLI, including one atomic monitor swap.
            width_second = state['outputs'][1]['logical_size'][0]
            msg('output', 'layout', first, width_second, 0, second, 0, 0)
            msg('output', 'primary', second)
            msg('output', 'scale', second, 150)
            state = control()
            assert state['outputs'][0]['position'][0] == state['outputs'][1]['logical_size'][0], state
            assert state['outputs'][1]['primary'], state
            first_output = state['outputs'][0]
            control('pointer', x=first_output['position'][0]+20, y=40)
            msg('output', 'layout', first, 0, -first_output['logical_size'][1], second, 0, 0)
            state = control()
            assert state['pointer_position'] == [20, 40-first_output['logical_size'][1]], state
            positions = [o['position'] for o in state['outputs']]
            msg('output', 'layout', first, 0, 0, second, 0, 0, success=False)
            msg('output', 'scale', first, 'NaN', success=False)
            msg('output', 'mode', first, '1280x720', success=False)
            assert [o['position'] for o in control()['outputs']] == positions
            assert {w['id'] for w in control()['windows']} == identities
            msg('config', 'save')
            saved = tomllib.loads(config.read_text())
            assert any(o['name'] == 'unplugged-fixture' for o in saved['outputs'])
            assert all('id' in o for o in saved['outputs'])
            # An editor's atomic rename must reload without changing window identities.
            good = config.read_text()
            temporary = config.with_suffix('.new')
            temporary.write_text(good.replace('scale = 1.5', 'scale = 1.75'))
            temporary.replace(config)
            wait_for(lambda: control()['outputs'][1]['scale'] == 1.75, description='automatic file reload')
            before_invalid = control()
            config.write_text('[[outputs]]\nname="SHINE-1"\nscale=0.0\n')
            wait_for(lambda: control()['config_error'], description='invalid configuration rejection')
            assert control()['outputs'] == before_invalid['outputs']
            config.write_text(good)
            wait_for(lambda: control()['config_error'] is None and control()['outputs'][1]['scale'] == 1.5,
                     description='recovery after corrected configuration')
            msg('config', 'reload')
            expected = control()['outputs']
            assert {w['id'] for w in control()['windows']} == identities
            (base / 'status.json').write_text(json.dumps(state, indent=2))
            control('quit')
            assert process.wait(timeout=10) == 0
            process = subprocess.Popen([str(BINARY), '--outputs', '2', '--no-clients', '--test-input',
                '--config', str(config), '--control-socket', str(path), '--close-after', '30'],
                cwd=ROOT, stdout=log, stderr=log)
            state = wait_for(lambda: control(), description='restart with saved monitor layout')
            assert [(o['position'], o['scale'], o['primary']) for o in state['outputs']] == [
                (o['position'], o['scale'], o['primary']) for o in expected], state
            assert state['active_output'] == second, state
            control('quit')
            assert process.wait(timeout=10) == 0
        finally:
            if process.poll() is None:
                control('quit')
                process.wait(timeout=10)
    assert {w['id'] for w in parent_windows()} == original
    print('PASS: independent outputs, atomic arrangement, mixed scales, primary, pointer anchoring, saved/reloaded configuration, invalid-edit recovery and restart persistence; original desktop preserved')


if __name__ == '__main__':
    main()
