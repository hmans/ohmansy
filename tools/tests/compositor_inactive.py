#!/usr/bin/env python3
"""Check focus effects, unchanged client sizes and transformed input privately."""
import json
from pathlib import Path
import re
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
    artifacts = Path(tempfile.mkdtemp(prefix='inactive-', dir=base))
    print(f'Artifacts: {artifacts}', flush=True)
    config = artifacts / 'config.toml'
    control = trial.Control(artifacts / 'control.sock')
    original = {w['id']: w['pid'] for w in trial.parent_windows()}

    def configure(enabled=True, scale=.99, saturation=.85, fog=.08, duration=160, animations=False,
                  easing='ease-out'):
        temporary = config.with_suffix('.new')
        temporary.write_text(f'''[layout]
gap=40
default_column_width={{pixels=300}}
[animations]
enabled={str(animations).lower()}
duration_ms=0
[decorations]
focus_ring_width=0
[decorations.shadow]
enabled=false
[decorations.inactive]
enabled={str(enabled).lower()}
scale={scale}
saturation={saturation}
fog={fog}
duration_ms={duration}
easing="{easing}"
''')
        temporary.replace(config)

    def window(ident):
        return next(w for w in control()['windows'] if w['id'] == ident)

    def settled():
        return all(w['inactive_amount'] == (0 if w['focused'] or control()['fullscreen'] == w['id'] else 1)
                   for w in control()['windows'])

    def capture(label):
        path = artifacts / f'{label}.png'
        control('screenshot', path=str(path))
        def read():
            with Image.open(path) as source:
                source.load()
                return source.convert('RGB')
        return trial.wait_for(read, description=label)

    def pixel(image, ident, x, y):
        state = control()
        win = window(ident)
        output = next(o for o in state['outputs'] if o['name'] == win['output'])
        canvas = sum(o['physical_size'][0] for o in state['outputs'][:state['outputs'].index(output)])
        return image.getpixel((round(canvas + (win['geometry'][0] - output['position'][0] + x) * output['scale']),
                               round((win['geometry'][1] - output['position'][1] + y) * output['scale'])))

    def near(actual, expected, tolerance=3):
        assert all(abs(a-b) <= tolerance for a, b in zip(actual, expected)), (actual, expected)

    configure()
    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--test-input', '--outputs', '2',
            '--scale', '1', '--config', str(config), '--control-socket', control.path,
            '--close-after', '180'], stdout=log, stderr=log)
        try:
            trial.wait_for(control, description='focus effect compositor')
            ids = []
            for index in range(3):
                if index == 2:
                    control('output', 2)
                mouse = artifacts / f'mouse-{index}'
                code = f'''import os, pathlib, sys, tty
tty.setraw(sys.stdin.fileno())
sys.stdout.write("\\x1b[?25l\\x1b[?1002h\\x1b[?1006h")
sys.stdout.flush()
while True:
    data = os.read(sys.stdin.fileno(), 1024)
    with open({str(mouse)!r}, 'ab') as f: f.write(data)
'''
                app = f'shine-inactive-{index}'
                control('launch', program='foot', args=['--config=/dev/null', f'--app-id={app}',
                    '-o', 'csd.size=0', '-o', 'csd.border-width=0', '-o', 'pad=0x0',
                    '-o', 'colors-dark.background=d02040', sys.executable, '-c', code])
                win = trial.wait_for(lambda: trial.window_for(control, app), description=app)
                ids.append(win['id'])
                trial.wait_for(lambda: window(win['id'])['surface_size'])
            control('focus', ids[0])
            trial.wait_for(settled)
            control('pointer', x=1000, y=700)
            sizes = {w['id']: w['surface_size'] for w in control()['windows']}
            geometry = {w['id']: w['geometry'] for w in control()['windows']}
            image = capture('default')
            near(pixel(image, ids[0], 150, 100), (208, 32, 64))
            luma = 208*.2126 + 32*.7152 + 64*.0722
            muted = [(.85*c + .15*luma)*.92 + .08*f*255
                     for c, f in zip((208, 32, 64), (.5, .5, .55))]
            for ident in ids[1:]:
                near(pixel(image, ident, 150, 100), muted)
                assert pixel(image, ident, 0, 100) == (9, 9, 14), 'Unfocused window did not shrink'
            # Exaggerate the scale to make bad inverse pointer mapping obvious.
            configure(scale=.8, saturation=1.0, fog=0.0)
            trial.wait_for(lambda: window(ids[1])['visual_scale'] == .8)
            image = capture('exaggerated')
            assert pixel(image, ids[1], 15, 150) == (9, 9, 14)
            near(pixel(image, ids[1], 35, 150), (208, 32, 64))
            # The visually empty inset must not focus its former owner.
            gx, gy, width, height = window(ids[1])['geometry']
            control('pointer', x=gx+10, y=gy+height/2)
            control('button', pressed=True)
            control('button', pressed=False)
            assert control()['focused'] != ids[1], 'Invisible window margin accepted input'
            # Compare a click in a full-sized window with the same point after scaling.
            def click(ident, x, y):
                gx, gy, _, _ = window(ident)['geometry']
                control('pointer', x=gx+x, y=gy+y)
                control('button', pressed=True)
                control('button', pressed=False)
            control('focus', ids[1])
            trial.wait_for(lambda: window(ids[1])['visual_scale'] == 1)
            click(ids[1], 60, height/2)
            path = artifacts / 'mouse-1'
            trial.wait_for(path.exists)
            first = re.findall(rb'\x1b\[<0;(\d+);(\d+)M', path.read_bytes())[-1]
            control('focus', ids[0])
            trial.wait_for(lambda: window(ids[1])['visual_scale'] == .8)
            click(ids[1], width/2 + (60-width/2)*.8, height/2)
            trial.wait_for(lambda: len(re.findall(rb'\x1b\[<0;(\d+);(\d+)M', path.read_bytes())) >= 2)
            second = re.findall(rb'\x1b\[<0;(\d+);(\d+)M', path.read_bytes())[-1]
            assert first == second, (first, second, 'Scaled click reached the wrong client coordinate')
            for scale in (125, 150, 200, 100):
                control('focus', ids[1])
                control('scale', scale)
                control('focus', ids[2])
                time.sleep(.2)
                image = capture(f'scale-{scale}')
                near(pixel(image, ids[1], 150, window(ids[1])['geometry'][3]/2), (208, 32, 64))
            # A static app must animate, and rapid reversal must not jump.
            configure(animations=True, duration=1000)
            trial.wait_for(lambda: control()['preferences']['decorations']['inactive']['duration_ms'] == 1000)
            control('focus', ids[0])
            trial.wait_for(settled)
            control('focus', ids[1])
            time.sleep(.2)
            middle = window(ids[0])['inactive_amount']
            assert 0 < middle < 1, middle
            capture('transition')
            control('focus', ids[0])
            after = window(ids[0])['inactive_amount']
            assert abs(after-middle) < .3, (middle, after)
            trial.wait_for(settled)
            for easing in ('linear', 'ease-in', 'ease-in-out', 'ease-out'):
                configure(animations=True, duration=1000, easing=easing)
                trial.wait_for(lambda: control()['preferences']['decorations']['inactive']['easing'] == easing)
                control('focus', ids[1])
                time.sleep(.1)
                assert 0 < window(ids[0])['inactive_amount'] < 1
                control('focus', ids[0])
                trial.wait_for(settled)
            frames = control()['rendered_frames']
            time.sleep(.3)
            assert control()['rendered_frames'] <= frames+2, 'Effect kept repainting after settling'
            # The implicit grab must update its coordinates while the clicked
            # window grows, and keep delivering motion outside its bounds.
            configure(scale=.8, animations=True, duration=500)
            trial.wait_for(lambda: window(ids[1])['visual_scale'] == .8)
            gx, gy, width, height = window(ids[1])['geometry']
            control('pointer', x=gx+width/2+(60-width/2)*.8, y=gy+height/2)
            control('button', pressed=True)
            trial.wait_for(lambda: window(ids[1])['visual_scale'] == 1)
            control('pointer', x=gx+60, y=gy+height/2)
            def drag_position():
                events = re.findall(rb'\x1b\[<32;(\d+);(\d+)M', path.read_bytes())
                return events and events[-1] == first
            trial.wait_for(drag_position, description='drag coordinate after focus animation')
            control('pointer', x=gx+width+20, y=gy+height/2)
            trial.wait_for(lambda: re.findall(rb'\x1b\[<32;(\d+);(\d+)M', path.read_bytes())[-1] != first,
                           description='grab motion beyond the window')
            control('button', pressed=False)
            control('focus', ids[0])
            control('fullscreen')
            assert window(ids[0])['visual_scale'] == 1
            control('fullscreen')
            configure(enabled=False)
            trial.wait_for(lambda: not control()['preferences']['decorations']['inactive']['enabled'])
            image = capture('disabled')
            near(pixel(image, ids[1], 1, 150), (208, 32, 64))
            assert all(w['visual_scale'] == 1 for w in control()['windows'])
            # Out-of-range numbers clamp while other changes still apply.
            configure(scale=.2)
            trial.wait_for(lambda: control()['config_error'] is None and
                           control()['preferences']['decorations']['inactive']['scale'] == 0.8,
                           description='inactive scale clamped')
            assert control()['preferences']['decorations']['inactive']['enabled']
            assert {w['id']: w['surface_size'] for w in control()['windows']} == sizes
            assert {w['id']: w['geometry'] for w in control()['windows']} == geometry
            print('Focus pixels, scaling, pointer coordinates, transitions, reload, idle and unchanged client sizes passed.', flush=True)
        finally:
            try:
                control('quit')
            except (OSError, AssertionError):
                process.terminate()
            process.wait(timeout=10)
    assert {w['id']: w['pid'] for w in trial.parent_windows()} == original


if __name__ == '__main__':
    run()
