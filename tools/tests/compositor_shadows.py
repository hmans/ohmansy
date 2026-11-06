#!/usr/bin/env python3
"""Check Shine shadow pixels, transparency, scaling and live preferences."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from PIL import Image
import compositor_support as trial


def run():
    trial.ensure_test_display()
    base = trial.ROOT / '.local/compositor-tests'
    base.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='shadows-', dir=base))
    print(f'Artifacts: {artifacts}', flush=True)
    control = trial.Control(artifacts / 'control.sock')
    config = artifacts / 'config.toml'
    original = {w['id']: w['pid'] for w in trial.parent_windows()}

    def configure(enabled=False, softness=12, spread=2, offset='[0,6]',
                  color='[1.0,0.0,0.0,0.8]', radius=14):
        temporary = config.with_suffix('.new')
        temporary.write_text(f'''# Shadow fixture
[layout]
gap=64
default_column_width={{pixels=300}}
[animations]
enabled=false
[decorations]
corner_radius={radius}
focus_ring_width=0
[decorations.shadow]
enabled={str(enabled).lower()}
softness={softness}
spread={spread}
offset={offset}
color={color}
''')
        temporary.replace(config)
        if enabled:
            trial.wait_for(lambda: control()['preferences']['decorations']['shadow']['enabled']
                           and control()['preferences']['decorations']['shadow']['softness'] == softness
                           and control()['preferences']['decorations']['shadow']['spread'] == spread
                           and control()['preferences']['decorations']['shadow']['offset'] == json.loads(offset)
                           and control()['preferences']['decorations']['corner_radius'] == radius,
                           description='shadow preferences reload')

    def capture(label):
        path = artifacts / f'{label}.png'
        control('screenshot', path=str(path))
        def read():
            with Image.open(path) as source:
                return source.convert('RGB')
        return trial.wait_for(read, description=label)

    def window(ident):
        return next(w for w in control()['windows'] if w['id'] == ident)

    def pixel(image, ident, x, y):
        state = control()
        win = window(ident)
        output = next(o for o in state['outputs'] if o['name'] == win['output'])
        canvas = sum(o['physical_size'][0] for o in state['outputs'][:state['outputs'].index(output)])
        return image.getpixel((round(canvas + (win['geometry'][0] - output['position'][0] + x) * output['scale']),
                               round((win['geometry'][1] - output['position'][1] + y) * output['scale'])))

    configure()
    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--test-input',
            '--outputs', '2', '--scale', '1', '--config', str(config),
            '--control-socket', control.path, '--close-after', '180'], stdout=log, stderr=log)
        try:
            trial.wait_for(control, description='Shine shadow trial')
            ids = []
            for index in range(3):
                if index == 2:
                    control('output', 2)
                app = f'shine-shadow-{index}'
                control('launch', program='foot', args=['--config=/dev/null', f'--app-id={app}',
                    '-o', 'csd.size=0', '-o', 'csd.border-width=0',
                    '-o', 'colors-dark.alpha=0.5', '-o', 'colors-dark.background=235e6f',
                    sys.executable, '-c',
                    'import sys,time; sys.stdout.write("\\x1b[?25l"); sys.stdout.flush(); time.sleep(170)'])
                win = trial.wait_for(lambda: trial.window_for(control, app), description=app)
                ids.append(win['id'])
                trial.wait_for(lambda: window(win['id'])['surface_size'] is not None)
            control('focus', ids[0])
            control('pointer', x=1000, y=700)
            before = capture('disabled')
            state = control()
            geometry = {w['id']: w['geometry'] for w in state['windows']}
            interior = pixel(before, ids[0], 150, 150)
            clear = pixel(before, ids[0], -6, 100)
            configure(True)
            image = capture('enabled')
            for ident in ids:
                assert pixel(image, ident, -6, 100)[0] > clear[0] + 40, 'Missing shadow'
                assert pixel(image, ident, -6, 100)[0] > pixel(image, ident, -30, 100)[0] + 20, 'Shadow lacks soft falloff'
            assert pixel(image, ids[0], 150, 150) == interior, 'Shadow darkened the translucent interior'
            assert geometry == {w['id']: w['geometry'] for w in control()['windows']}, 'Shadow changed layout'
            assert control()['keyboard_focus'] == state['keyboard_focus'], 'Shadow stole focus'
            # Increasing softness/spread and shifting down affects actual pixels.
            configure(True, softness=20, spread=5, offset='[0,18]')
            image = capture('offset-spread')
            height = window(ids[0])['geometry'][3]
            assert pixel(image, ids[0], 150, height + 8)[0] > pixel(image, ids[0], 150, -8)[0] + 10
            for scale in [125, 150, 200, 100]:
                control('scale', scale)
                time.sleep(.2)
                image = capture(f'scale-{scale}')
                assert pixel(image, ids[0], -6, 100)[0] > clear[0] + 40, f'Shadow scaling at {scale}%'
            # Even a large, shifted shadow at the output edge must not leak
            # onto the neighbouring monitor's empty workspace.
            control('focus', ids[2])
            control('workspace', 4)
            control('focus', ids[0])
            control('maximize')
            configure(True, softness=64, spread=64, offset='[128,0]')
            image = capture('output-clipping')
            edge = control()['outputs'][0]['physical_size'][0]
            assert image.getpixel((edge + 10, 200)) == clear, 'Shadow leaked onto another monitor'
            control('maximize')
            control('output', 2)
            control('workspace', 1)
            control('focus', ids[0])
            configure(True, softness=20, spread=5, offset='[0,18]', radius=0)
            image = capture('square')
            assert pixel(image, ids[0], -6, 100)[0] > clear[0] + 40, 'Square windows lost shadows'
            control('fullscreen')
            image = capture('fullscreen')
            assert pixel(image, ids[0], 1, 1)[0] < 40, 'Fullscreen retained a shadow'
            control('fullscreen')
            control('save-config')
            assert '[decorations.shadow]' in config.read_text() and '# Shadow fixture' in config.read_text()
            configure(False)
            trial.wait_for(lambda: not control()['preferences']['decorations']['shadow']['enabled'])
            image = capture('disabled-again')
            assert pixel(image, ids[0], -6, 100) == clear, 'Stale shadow after disable'
            configure(True)
            control('workspace', 4)
            image = capture('empty-workspace')
            assert image.getpixel((60, 200)) == clear, 'Shadow survived a workspace change'
            time.sleep(.3)
            frames = control()['rendered_frames']
            time.sleep(.4)
            assert control()['rendered_frames'] <= frames + 1, 'Shadows caused idle repaints'
            (artifacts / 'status.json').write_text(json.dumps(control(), indent=2))
            control('quit')
            process.wait(timeout=10)
            assert process.returncode == 0
        finally:
            if process.poll() is None:
                control('quit')
                process.wait(timeout=10)
    remaining = {w['id']: w['pid'] for w in trial.parent_windows()}
    assert all(remaining.get(ident) == pid for ident, pid in original.items())
    print('PASS: shadows, soft falloff, translucent interiors, two monitors, output clipping, scale, '
          'offset/spread, square windows, fullscreen, live reload/disable/save, idle and parent preservation')


if __name__ == '__main__':
    run()
