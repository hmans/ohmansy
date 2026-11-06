#!/usr/bin/env python3
"""Verify frame pixels, titles, focus, dragging and fullscreen privately."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import tomllib

from PIL import Image
import compositor_support as trial


def run():
    trial.ensure_test_display()
    base = trial.ROOT / '.local/compositor-tests'
    base.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='frames-', dir=base))
    print(f'Artifacts: {artifacts}', flush=True)
    control = trial.Control(artifacts / 'control.sock')
    config = artifacts / 'config.toml'
    base_config = '''[layout]
gap=40
default_column_width={pixels=360}
[animations]
enabled=false
[decorations.shadow]
enabled=false
[decorations.inactive]
enabled=false
'''
    def fixture(extra=''):
        values = dict(width=3, titlebar_height=26, title_font_size=13.0, icon_width=16, icon_height=16,
            title_padding=8, icon_title_gap=7, outer_corner_radius=14, inner_corner_radius=11,
            active_color=[81/255,64/255,95/255,1.0], inactive_color=[37/255,40/255,53/255,1.0])
        values.update(tomllib.loads(extra).get('decorations', {}).get('frame', {}))
        return base_config + '\n[decorations.frame]\n' + '\n'.join(f'{key}={json.dumps(value)}' for key,value in values.items()) + '\n[decorations.frame.glass]\nenabled=false\n'
    config.write_text(fixture())
    data = artifacts / 'data'
    (data / 'applications').mkdir(parents=True)
    icon = data / 'icon.png'
    Image.new('RGBA', (32, 32), (255, 200, 0, 255)).save(icon)
    (data / 'applications/frame-probe.desktop').write_text(
        f'[Desktop Entry]\nType=Application\nName=Frame probe\nIcon={icon}\n')
    env = dict(os.environ, XDG_DATA_HOME=str(data))

    def window(app='frame-probe'):
        return trial.window_for(control, app)

    def capture(label):
        path = artifacts / f'{label}.png'
        control('screenshot', path=str(path))
        def read():
            with Image.open(path) as source:
                return source.convert('RGB')
        return trial.wait_for(read, description=label)

    def pixel(image, x, y, app='frame-probe'):
        state, win = control(), window(app)
        output = next(o for o in state['outputs'] if o['name'] == win['output'])
        canvas = sum(o['physical_size'][0] for o in state['outputs'][:state['outputs'].index(output)])
        return image.getpixel((int(canvas + (win['geometry'][0] - output['position'][0] + x) * output['scale']),
                               int((win['geometry'][1] - output['position'][1] + y) * output['scale'])))

    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--test-input', '--scale', '1',
            '--config', str(config), '--control-socket', control.path, '--close-after', '180'],
            env=env, stdout=log, stderr=log)
        try:
            trial.wait_for(control)
            code = '''import os, select, sys, tty
tty.setraw(sys.stdin.fileno())
sys.stdout.write("\\x1b[?25l\\x1b]2;A title with Ελληνικά and 日本語\\x07")
sys.stdout.flush()
while True:
    if select.select([sys.stdin], [], [], .1)[0]:
        if not os.read(sys.stdin.fileno(), 1): break
        sys.stdout.write("\\x1b]2;Updated window title\\x07")
        sys.stdout.flush()
'''
            control('launch', program='foot', args=['--config=/dev/null', '--app-id=frame-probe',
                '-o', 'colors.background=112233', sys.executable, '-c', code])
            trial.wait_for(lambda: window() and window()['surface_size'] and window()['title'].startswith('A title'))
            control('pointer', x=1000, y=700)
            time.sleep(.3)
            for scale in [1.0, 1.25, 2.0]:
                control('scale', round(scale * 100))
                time.sleep(.3)
                win = window()
                x, y, w, h = win['geometry']
                assert win['content_geometry'] == [x+3, y+26, w-6, h-29], win
                image = capture(f'frame-{scale}')
                for px, py in [(1, 100), (w-2, 100), (100, h-2), (w-20, 12)]:
                    assert pixel(image, px, py) == (81, 64, 95), (scale, px, py, pixel(image, px, py))
                assert pixel(image, 5, 100) == (17, 34, 51), 'Frame covers client content'
                assert pixel(image, 4, 27) == (81, 64, 95), 'Frame missing around inner rounded corner'
                assert pixel(image, 15, 13) == (255, 200, 0), 'Desktop icon missing'
                assert any(min(pixel(image, px, py)) > 150 for px in range(32, int(w)-20) for py in range(6, 21)), 'Title text missing'
                assert pixel(image, -2, 100) == (9, 9, 14), 'Decoration leaks outside frame'
            control('scale', 100)
            time.sleep(.3)
            previous_title = capture('previous-title')
            control('key', code=30, pressed=True)
            control('key', code=30, pressed=False)
            trial.wait_for(lambda: window()['title'] == 'Updated window title')
            updated = capture('updated-title')
            x, y, w, _ = window()['geometry']
            assert previous_title.crop((x+31,y+3,x+w-10,y+23)).tobytes() != updated.crop((x+31,y+3,x+w-10,y+23)).tobytes(), 'Title pixels did not update'
            control('launch', program='foot', args=['--config=/dev/null', '--app-id=frame-other', 'sleep', '120'])
            trial.wait_for(lambda: window('frame-other') and window('frame-other')['surface_size'])
            time.sleep(.3)
            assert pixel(capture('inactive'), 1, 100) == (37, 40, 53), 'Inactive frame color missing'
            x, y, w, h = window()['geometry']
            control('pointer', x=x+w-20, y=y+12)
            control('button', pressed=True)
            control('button', pressed=False)
            assert control()['focused'] == window()['id'], 'Titlebar click did not focus'
            assert pixel(capture('focused'), 1, 100) == (81, 64, 95)
            control('toggle-floating')
            time.sleep(.2)
            before = window()['geometry']
            control('pointer', x=before[0]+before[2]-20, y=before[1]+12)
            control('button', pressed=True)
            control('pointer', x=before[0]+before[2]+30, y=before[1]+42)
            control('button', pressed=False)
            trial.wait_for(lambda: window()['geometry'][:2] == [before[0]+50, before[1]+30], description='frame drag moves floating window')
            control('fullscreen')
            time.sleep(.2)
            assert window()['geometry'] == window()['content_geometry'], 'Fullscreen retains frame'
            control('fullscreen')
            time.sleep(.2)
            defaults = fixture()
            temporary = config.with_suffix('.new')
            temporary.write_text(fixture('[decorations.frame]\nenabled=false\n'))
            temporary.replace(config)
            trial.wait_for(lambda: not control()['preferences']['decorations']['frame']['enabled'] and window()['geometry'] == window()['content_geometry'], description='live frame disable')
            temporary.write_text(fixture('[decorations.frame]\nwidth=4\ntitlebar_height=30\n'))
            temporary.replace(config)
            trial.wait_for(lambda: control()['preferences']['decorations']['frame']['width'] == 4 and window()['content_geometry'][1] == window()['geometry'][1]+30, description='live frame dimensions')
            measurements = '''\n[decorations.frame]
width=6
titlebar_height=44
title_font_size=21.0
icon_width=24
icon_height=12
title_padding=12
icon_title_gap=10
outer_corner_radius=0
inner_corner_radius=18
'''
            def measure(settings, label):
                temporary.write_text(fixture(settings))
                temporary.replace(config)
                trial.wait_for(lambda: all(control()['preferences']['decorations']['frame'][key.strip()] == float(value.strip())
                    for key, value in (line.split('=') for line in settings.splitlines() if '=' in line)), description=label)
                time.sleep(.2)
                return capture(label)

            def text_height(image):
                x, y, width, _ = window()['geometry']
                points = [(px, py) for px in range(46, min(300, width-12)) for py in range(44)
                          if min(image.getpixel((x+px, y+py))) > 180]
                assert points, 'Configured title text missing'
                return max(y for _, y in points)-min(y for _, y in points)+1

            custom = measure(measurements, 'custom-measurements')
            _, _, w, h = window()['geometry']
            assert pixel(custom, 0, 0) == (81,64,95), 'Outer radius zero did not square frame'
            assert pixel(custom, 5, 100) == (81,64,95) and pixel(custom, 7, 100) == (17,34,51), 'Configured border width missing'
            assert pixel(custom, 13, 17) == (255,200,0) and pixel(custom, 34, 26) == (255,200,0), 'Configured rectangular icon missing'
            assert pixel(custom, 10, 22) == (81,64,95) and pixel(custom, 36,22) == (81,64,95), 'Icon padding or width incorrect'
            assert pixel(custom, 8, 46) == (81,64,95), 'Independent inner radius missing'
            large_height = text_height(custom)
            smaller = measure(measurements.replace('title_font_size=21.0', 'title_font_size=10.5'), 'font-only-reload')
            assert text_height(smaller) < large_height-3, 'Font-only edit did not invalidate caption cache'
            wider = measure(measurements.replace('icon_width=24', 'icon_width=32'), 'icon-only-reload')
            assert pixel(wider, 40, 22) == (255,200,0), 'Icon-only edit did not invalidate caption cache'
            rounded = measure(measurements.replace('outer_corner_radius=0', 'outer_corner_radius=32').replace('inner_corner_radius=18', 'inner_corner_radius=0'), 'independent-outer-radius')
            assert pixel(rounded, 1, 1) == pixel(rounded, -2, 1), 'Outer silhouette not rounded'
            assert pixel(rounded, w-7, h-7) == (9,9,14), 'Square client leaked through rounded outer frame'
            x, y, _, _ = window()['geometry']
            control('focus', window('frame-other')['id'])
            control('pointer', x=x+w-7, y=y+h-7)
            control('button', pressed=True)
            control('button', pressed=False)
            assert control()['focused'] != window()['id'], 'Transparent outer corner accepts client input'
            control('focus', window()['id'])
            temporary.write_text(defaults)
            temporary.replace(config)
            trial.wait_for(lambda: control()['preferences']['decorations']['frame']['width'] == 3)
            time.sleep(.2)
            capture('final')
            time.sleep(.3)
            frames = control()['rendered_frames']
            time.sleep(.4)
            assert control()['rendered_frames'] == frames, 'Frame repaints while idle'
            (artifacts / 'verification.json').write_text(json.dumps({'frame_pixels': True, 'scales': [1, 1.25, 2], 'icon': True,
                'title_update': True, 'focus': True, 'floating_drag': True, 'fullscreen': True, 'idle': True}, indent=2))
        finally:
            if process.poll() is None:
                try:
                    control('quit')
                    process.wait(timeout=5)
                except (OSError, ValueError, AssertionError, subprocess.TimeoutExpired):
                    process.terminate()
                    process.wait(timeout=5)
    print('PASS: frames, icons, titles, focus, dragging, fullscreen and idle damage')


if __name__ == '__main__':
    run()
