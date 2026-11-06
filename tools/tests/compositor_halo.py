#!/usr/bin/env python3
"""Verify content-colored halos on the private display."""
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
    artifacts = Path(tempfile.mkdtemp(prefix='halo-', dir=base))
    print(f'Artifacts: {artifacts}', flush=True)
    control = trial.Control(artifacts / 'control.sock')
    config = artifacts / 'config.toml'

    def configure(enabled, width=32, opacity=.7):
        temporary = config.with_suffix('.new')
        temporary.write_text(f'''[layout]
gap=80
default_column_width={{pixels=300}}
[animations]
enabled=false
[decorations]
focus_ring_width=0
inactive_ring_width=0
[decorations.shadow]
enabled=false
[decorations.inactive]
enabled=false
[decorations.halo]
enabled={str(enabled).lower()}
width={width}
opacity={opacity}
''')
        temporary.replace(config)

    def capture(label):
        path = artifacts / f'{label}.png'
        control('screenshot', path=str(path))
        def read():
            with Image.open(path) as source:
                return source.convert('RGB')
        return trial.wait_for(read, description=label)

    def window():
        return trial.window_for(control, 'shine-halo')

    def pixel(image, x, y, app='shine-halo'):
        state = control()
        win = trial.window_for(control, app)
        output = next(o for o in state['outputs'] if o['name'] == win['output'])
        canvas = sum(o['physical_size'][0] for o in state['outputs'][:state['outputs'].index(output)])
        return image.getpixel((round(canvas + (win['geometry'][0] - output['position'][0] + x) * output['scale']),
                               round((win['geometry'][1] - output['position'][1] + y) * output['scale'])))

    configure(False)
    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--test-input',
            '--outputs', '2', '--scale', '1', '--config', str(config), '--control-socket', control.path,
            '--close-after', '180'], stdout=log, stderr=log)
        try:
            trial.wait_for(control)
            code = '''import os, select, sys, tty
tty.setraw(sys.stdin.fileno())
def paint(top):
    width, height = os.get_terminal_size()
    sys.stdout.write("\\x1b[?25l\\x1b[H")
    for row in range(height):
        color = top if row < height//2 else "0;0;255"
        sys.stdout.write(f"\\x1b[{row+1};1H\\x1b[48;2;{color}m" + " "*width)
    sys.stdout.flush()
current = "255;0;0"
size = None
while True:
    latest = os.get_terminal_size()
    if latest != size:
        size = latest
        paint(current)
    if select.select([sys.stdin], [], [], .05)[0]:
        if not os.read(sys.stdin.fileno(), 1): break
        current = "0;255;0"
        paint(current)
'''
            control('launch', program='foot', args=['--config=/dev/null', '--app-id=shine-halo',
                '-o', 'csd.size=0', '-o', 'csd.border-width=0', '-o', 'pad=0x0',
                sys.executable, '-c', code])
            trial.wait_for(lambda: window() and window()['surface_size'])
            control('pointer', x=1000, y=700)
            time.sleep(.3)
            before = capture('disabled')
            clear = pixel(before, -8, 100)
            geometry = window()['geometry']
            height = geometry[3]
            configure(True)
            trial.wait_for(lambda: control()['preferences']['decorations']['halo']['enabled'])
            image = capture('enabled')
            red = pixel(image, -8, height*.2)
            blue = pixel(image, -8, height*.8)
            assert red[0] > red[2]+50, ('Missing red halo at top', red)
            assert blue[2] > blue[0]+50, ('Missing blue halo at bottom', blue)
            assert pixel(image, -8, height*.2)[0] > pixel(image, -28, height*.2)[0]+30
            assert pixel(image, 100, 100) == pixel(before, 100, 100), 'Changed client interior'
            assert window()['geometry'] == geometry, 'Changed window geometry'
            control.send_keys([30])
            trial.wait_for(lambda: pixel(capture('updated'), -8, height*.2)[1] > 100,
                           description='halo follows new client pixels')
            for scale in [125, 150, 200, 100]:
                control('scale', scale)
                time.sleep(.2)
                image = capture(f'scale-{scale}')
                height = window()['geometry'][3]
                assert pixel(image, -8, height*.2)[1] > 100, f'Incorrect halo scale {scale}'
            configure(True, width=64, opacity=.35)
            trial.wait_for(lambda: control()['preferences']['decorations']['halo']['width'] == 64)
            assert pixel(capture('wider'), -40, height*.2)[1] > clear[1]+10
            control('output', 2)
            control('launch', program='foot', args=['--config=/dev/null', '--app-id=shine-halo-alpha',
                '-o', 'csd.size=0', '-o', 'csd.border-width=0', '-o', 'colors-dark.alpha=0.5',
                '-o', 'colors-dark.background=ff0000', sys.executable, '-c',
                'import sys,time; sys.stdout.write("\\x1b[?25l"); sys.stdout.flush(); time.sleep(150)'])
            trial.wait_for(lambda: trial.window_for(control, 'shine-halo-alpha'))
            time.sleep(.2)
            image = capture('translucent-enabled')
            interior = pixel(image, 100, 100, 'shine-halo-alpha')
            assert pixel(image, -8, 100, 'shine-halo-alpha')[0] > clear[0]+10
            configure(False)
            trial.wait_for(lambda: not control()['preferences']['decorations']['halo']['enabled'])
            assert pixel(capture('translucent-disabled'), 100, 100, 'shine-halo-alpha') == interior
            control('workspace', 4)
            control('focus', window()['id'])
            control('maximize')
            configure(True, width=128)
            trial.wait_for(lambda: control()['preferences']['decorations']['halo']['width'] == 128)
            image = capture('output-clipping')
            edge = control()['outputs'][0]['physical_size'][0]
            assert image.getpixel((edge+10, 200)) == clear, 'Halo leaked onto another output'
            control('maximize')
            time.sleep(.2)
            control('fullscreen')
            time.sleep(.25)
            image = capture('fullscreen')
            assert image.getpixel((100, 100))[1] > 200, 'Fullscreen client changed'
            control('fullscreen')
            time.sleep(.25)
            configure(False)
            trial.wait_for(lambda: not control()['preferences']['decorations']['halo']['enabled'])
            assert pixel(capture('disabled-again'), -8, 100) == clear
            configure(True)
            trial.wait_for(lambda: control()['preferences']['decorations']['halo']['enabled'])
            capture('idle')
            time.sleep(.3)
            frames = control()['rendered_frames']
            time.sleep(.5)
            assert control()['rendered_frames'] <= frames+1, 'Halo causes idle repaints'
            control('workspace', 4)
            assert capture('hidden').getpixel((60, 100)) == clear, 'Stale halo'
            control('quit')
            process.wait(timeout=10)
            assert process.returncode == 0
        finally:
            if process.poll() is None:
                control('quit')
                process.wait(timeout=10)
    print('PASS: content colors, orientation, fade, client updates, unchanged interior/layout, '
          '100–200% scale, translucent client, two outputs, output clipping, live width/opacity/disable, '
          'fullscreen, hidden workspace and idle')


if __name__ == '__main__':
    run()
