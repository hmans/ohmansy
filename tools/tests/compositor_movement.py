#!/usr/bin/env python3
"""Exercise animated column swaps with real clients on a private Shine socket."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from compositor_decorations import png_pixels
import compositor_support as trial


def run():
    trial.ensure_test_display()
    root = trial.ROOT / '.local/compositor-tests'
    root.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='movement-', dir=root))
    print(f'Artifacts: {artifacts}', flush=True)
    config = artifacts / 'config.toml'

    def preferences(enabled=True, duration=1000):
        temporary = config.with_suffix('.new')
        temporary.write_text(f'''[layout]
default_column_width={{pixels=200}}
[animations]
enabled={str(enabled).lower()}
duration_ms={duration}
[decorations.frame]
active_color=[0.67,0.57,0.78,1.0]
''')
        temporary.replace(config)

    preferences()
    control = trial.Control(artifacts / 'control.sock')
    original = {w['id']: w['pid'] for w in trial.parent_windows()}
    (artifacts / 'parent-before.json').write_text(json.dumps(original))

    def window(ident):
        return next(w for w in control()['windows'] if w['id'] == ident)

    def settled():
        state = control()
        return state if not any(w['moving'] for w in state['windows']) and state['viewport'] == state['viewport_target'] else None

    def wait_settled():
        return trial.wait_for(settled, description='settled columns and viewport')

    def launch(index):
        app = f'shine-move-{index}'
        control('launch', program='foot', args=['--config=/dev/null', f'--app-id={app}',
            '-o', 'csd.size=0', '-o', 'csd.border-width=0', '-o', 'colors-dark.background=235e6f',
            sys.executable, '-c', 'import sys,time; sys.stdout.write("\\x1b[?25l"); sys.stdout.flush(); time.sleep(170)'])
        w = trial.wait_for(lambda: trial.window_for(control, app), description=app)
        trial.wait_for(lambda: window(w['id'])['surface_size'] is not None)
        return w['id']

    def screenshot(label):
        path = artifacts / f'{label}.png'
        (artifacts / f'{label}.json').write_text(json.dumps(control(), indent=2))
        control('screenshot', path=str(path))
        return trial.wait_for(lambda: png_pixels(path), description=f'{label} complete framebuffer')

    def configure(enabled=True, duration=1000):
        preferences(enabled, duration)
        trial.wait_for(lambda: control()['preferences']['animations'] == {'enabled': enabled, 'duration_ms': duration})

    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--test-input', '--scale', '1',
            '--config', str(config), '--control-socket', control.path, '--close-after', '180'], stdout=log, stderr=log)
        try:
            trial.wait_for(control, description='movement compositor')
            ids = [launch(i) for i in range(3)]
            control('focus', ids[0])
            wait_settled()
            control('pointer', x=800, y=700)
            sizes = {w['id']: w['client_geometry'][2:] for w in control()['windows']}
            start = window(ids[0])['geometry']
            screenshot('baseline')  # Wait through the nested capture startup delay.
            # Use the actual nested shortcut profile: Super+Alt+Shift+Right.
            control.send_keys([106], ('super', 'alt', 'shift'))
            mid = control()
            selected = next(w for w in mid['windows'] if w['id'] == ids[0])
            assert selected['moving'] and start[0] < selected['geometry'][0] < selected['target_geometry'][0], mid
            assert sum(w['moving'] for w in mid['windows']) == 2, mid
            assert mid['focused'] == mid['keyboard_focus'] == ids[0]
            pixel = screenshot('mid-swap')
            # Only the focused frame has this color, at an intermediate position.
            row = start[1] + 50
            ring = [x for x in range(mid['viewport_size'][0])
                    if all(abs(a - b) < 5 for a, b in zip(pixel(x, row), (171, 145, 199)))]
            assert ring and start[0] < min(ring) < selected['target_geometry'][0], ring
            assert abs(max(ring) - min(ring) + 1 - start[2]) <= 2, ring
            wait_settled()
            assert {w['id']: w['client_geometry'][2:] for w in control()['windows']} == sizes, 'Moving resized a client'
            assert all(w['geometry'] == w['target_geometry'] for w in control()['windows'])

            # Reverse twice before settling; no jump to a finished position.
            control('move-prev')
            time.sleep(.12)
            before = window(ids[0])['geometry'][0]
            reply = control('move-next')
            selected = next(w for w in reply['windows'] if w['id'] == ids[0])
            assert abs(selected['geometry'][0] - before) <= 35, (before, selected)
            assert selected['moving'] and reply['focused'] == ids[0]
            wait_settled()

            # Hit the visible selected window where its final position is absent.
            control('move-prev')
            wait_settled()
            control('move-next')
            time.sleep(.1)
            visible = window(ids[0])
            x = visible['geometry'][0] + 90
            assert x < visible['target_geometry'][0], visible
            control('pointer', x=x, y=visible['geometry'][1] + 100)
            control('button', pressed=True)
            control('button', pressed=False)
            assert control()['keyboard_focus'] == ids[0], 'Pointer used the destination instead of the visible window'
            wait_settled()

            control('move-prev')
            configure(False)
            assert all(not w['moving'] and w['geometry'] == w['target_geometry'] for w in control()['windows'])
            configure(True, 0)
            control('move-next')
            assert all(not w['moving'] and w['geometry'] == w['target_geometry'] for w in control()['windows'])
            configure()
            control('move-prev')
            control('fullscreen')
            assert not window(ids[0])['moving'] and control()['fullscreen'] == ids[0]
            control('fullscreen')
            control('move-next')
            control('workspace', 2)
            control('workspace', 1)
            assert not any(w['moving'] for w in control()['windows'])

            # Two wide columns force an animated viewport adjustment on a swap.
            wide = []
            available = control()['viewport_size'][0] - 24
            for i in range(3, 5):
                ident = launch(i)
                control('focus', ident)
                target_width = max(200, int(available * .6))
                while window(ident)['width'] != target_width:
                    control('resize', max(-2000, min(2000, target_width - window(ident)['width'])))
                wide.append(ident)
            control('focus', wide[0])
            state = wait_settled()
            old_scroll = state['viewport']
            control('move-next')
            time.sleep(.15)
            state = control()
            assert state['viewport'] != old_scroll and state['viewport'] != state['viewport_target'], state
            assert window(wide[0])['moving']
            assert state['focused'] == state['keyboard_focus'] == wide[0]
            wait_settled()
            assert all(w['geometry'] == w['target_geometry'] for w in control()['windows'])
            control('move-prev')
            control('close')
            trial.wait_for(lambda: all(w['id'] != wide[0] for w in control()['windows']))
            trial.wait_for(lambda: not any(w['moving'] for w in control()['windows']))
            control('workspace', 4)
            wait_settled()
            time.sleep(.25)
            frames = control()['rendered_frames']
            time.sleep(.4)
            assert control()['rendered_frames'] - frames <= 1, 'Animation continued rendering after it finished'
            (artifacts / 'status.json').write_text(json.dumps(control(), indent=2))
            control('quit')
            process.wait(timeout=10)
            assert process.returncode == 0
        finally:
            if process.poll() is None:
                control('quit')
                process.wait(timeout=10)
    remaining = {w['id']: w['pid'] for w in trial.parent_windows()}
    (artifacts / 'parent-after.json').write_text(json.dumps(remaining))
    assert all(remaining.get(ident) == pid for ident, pid in original.items()), (original, remaining)
    print('PASS: real Shift+Mod+Right swaps, intermediate ring pixels, unchanged client sizes/focus, '
          'interrupted moves, visible-position clicks, disabled/zero duration, fullscreen/workspace/close cleanup, '
          'coordinated viewport, idle and parent preservation')


if __name__ == '__main__':
    run()
