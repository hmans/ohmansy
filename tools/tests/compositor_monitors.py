#!/usr/bin/env python3
"""Two advertised outputs, independent workspaces and mixed-scale pointer input."""
import json
import os
from pathlib import Path
import subprocess
import time
from compositor_integration import BINARY, ROOT, Control, parent_windows, wait_for


def main():
    base = ROOT / '.local/compositor-monitors'
    base.mkdir(parents=True, exist_ok=True)
    path = base / f'{os.getpid()}.sock'
    original = {w['id'] for w in parent_windows()}
    with (base / 'compositor.log').open('w') as log:
        process = subprocess.Popen([str(BINARY), '--outputs', '2', '--no-clients',
            '--test-input', '--control-socket', str(path), '--close-after', '90'],
            cwd=ROOT, stdout=log, stderr=log)
        control = Control(path)
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
            control('move-output-prev')
            control('output', 2)
            control('workspace', 1)
            time.sleep(1)
            screenshot = base / 'two-monitors.png'
            control('screenshot', path=str(screenshot))
            wait_for(screenshot.exists, description='two-monitor screenshot')
            state = control()
            assert state['dmabuf_failures'] == 0, state
            (base / 'status.json').write_text(json.dumps(state, indent=2))
            control('quit')
            assert process.wait(timeout=10) == 0
        finally:
            if process.poll() is None:
                control('quit')
                process.wait(timeout=10)
    assert {w['id'] for w in parent_windows()} == original
    print('PASS: two outputs, independent workspaces/fullscreen, window moves, per-output scaling; original desktop preserved')


if __name__ == '__main__':
    main()
