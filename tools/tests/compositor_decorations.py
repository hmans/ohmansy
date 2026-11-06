#!/usr/bin/env python3
"""Check real pixels and input at rounded windows in an isolated Shine session."""
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time
import zlib

import compositor_support as trial


def png_pixels(path):
    """Read the compositor's 8-bit RGBA PNGs without an extra test dependency."""
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    assert data[-12:] == b'\x00\x00\x00\x00IEND\xaeB`\x82', 'Framebuffer is still being written'
    offset, compressed = 8, bytearray()
    while offset < len(data):
        size = struct.unpack_from('>I', data, offset)[0]
        kind, chunk = data[offset + 4:offset + 8], data[offset + 8:offset + 8 + size]
        if kind == b'IHDR':
            width, height, depth, color, _, _, interlace = struct.unpack('>IIBBBBB', chunk)
            assert (depth, color, interlace) == (8, 6, 0)
        elif kind == b'IDAT':
            compressed.extend(chunk)
        offset += size + 12
    raw, stride = zlib.decompress(compressed), width * 4
    rows, previous = [], bytearray(stride)
    def pixel(x, y):
        nonlocal previous
        x, y = int(x), int(y)
        assert 0 <= x < width and 0 <= y < height, (x, y, width, height)
        while len(rows) <= y:
            start = len(rows) * (stride + 1)
            mode, row = raw[start], bytearray(raw[start + 1:start + 1 + stride])
            for column in range(stride):
                left, up, upper_left = (row[column - 4] if column >= 4 else 0), previous[column], (previous[column - 4] if column >= 4 else 0)
                predictor = (0, left, up, (left + up) // 2)[mode] if mode < 4 else min(
                    (left, up, upper_left), key=lambda v: abs(left + up - upper_left - v))
                row[column] = (row[column] + predictor) & 255
            rows.append(row)
            previous = row
        return tuple(rows[y][x * 4:x * 4 + 3])
    return pixel


def run():
    trial.ensure_test_display()
    root = trial.ROOT / '.local/compositor-tests'
    root.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='decorations-', dir=root))
    print(f'Artifacts: {artifacts}', flush=True)
    config = artifacts / 'config.toml'

    def preferences(radius=14, width=2, color='[0.67,0.57,0.78,1.0]'):
        temporary = config.with_suffix('.new')
        temporary.write_text(f'''# Decoration fixture
[layout]
default_column_width={{pixels=300}}
[animations]
enabled=false
[decorations]
corner_radius={radius}
focus_ring_width={width}
focus_ring_color={color}
[decorations.shadow]
enabled=false
''')
        temporary.replace(config)

    preferences()
    original = {w['id']: w['pid'] for w in trial.parent_windows()}
    (artifacts / 'parent-before.json').write_text(json.dumps(original))
    control = trial.Control(artifacts / 'control.sock')
    clear = (9, 9, 14)

    def window(ident):
        return next(w for w in control()['windows'] if w['id'] == ident)

    def screenshot(label):
        path = artifacts / f'{label}.png'
        (artifacts / f'{label}.json').write_text(json.dumps(control(), indent=2))
        control('screenshot', path=str(path))
        trial.wait_for(path.exists, description=f'{label} framebuffer')
        return trial.wait_for(lambda: png_pixels(path), description=f'{label} complete PNG')

    def color_at(pixel, ident, x, y):
        state = control()
        w = window(ident)
        output = next(o for o in state['outputs'] if o['name'] == w['output'])
        canvas = sum(o['physical_size'][0] for o in state['outputs'][:state['outputs'].index(output)])
        return pixel(canvas + (w['geometry'][0] - output['position'][0] + x) * output['scale'],
                     (w['geometry'][1] - output['position'][1] + y) * output['scale'])

    def near(actual, expected, tolerance=4):
        return all(abs(a - b) <= tolerance for a, b in zip(actual, expected))

    def check_corner_coverage(pixel, ident):
        # Compare actual outer-edge pixels with circle/pixel intersection area.
        # A narrow smoothstep can pass solid-edge checks while visibly stair-stepping.
        state = control()
        w = window(ident)
        output = next(o for o in state['outputs'] if o['name'] == w['output'])
        scale = output['scale']
        canvas = sum(o['physical_size'][0] for o in state['outputs'][:state['outputs'].index(output)])
        gx, gy, width, height = w['geometry']
        origin = (canvas + (gx - output['position'][0]) * scale,
                  (gy - output['position'][1]) * scale)
        radius, outer = 14 * scale, 16 * scale
        errors = []
        for y in range(-int(2 * scale), int(radius)):
            for x in range(-int(2 * scale), int(radius)):
                if abs(math.hypot(x + .5 - radius, y + .5 - radius) - outer) > .7:
                    continue
                coverage = sum((x + (sx + .5) / 32 - radius) ** 2 +
                               (y + (sy + .5) / 32 - radius) ** 2 < outer ** 2
                               for sx in range(32) for sy in range(32)) / 1024
                for right, bottom in [(False, False), (True, False), (False, True), (True, True)]:
                    px = origin[0] + (width * scale - 1 - x if right else x)
                    py = origin[1] + (height * scale - 1 - y if bottom else y)
                    actual = (pixel(px, py)[0] - clear[0]) / (171 - clear[0])
                    errors.append(abs(actual - coverage))
        assert errors and max(errors) < .03, f'Jagged corner coverage at {scale}x: {max(errors)}'

    def click(ident, x, y):
        geometry = window(ident)['geometry']
        control('pointer', x=geometry[0] + x, y=geometry[1] + y)
        control('button', pressed=True)
        control('button', pressed=False)

    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--test-input', '--outputs', '2',
            '--scale', '1', '--config', str(config), '--control-socket', control.path, '--close-after', '180'],
            stdout=log, stderr=log)
        try:
            trial.wait_for(control, description='decorated compositor')
            ids = []
            for index in range(3):
                if index == 2:
                    control('output', 2)
                app = f'shine-decor-{index}'
                control('launch', program='foot', args=['--config=/dev/null', f'--app-id={app}', '-o', 'csd.size=0', '-o', 'csd.border-width=0',
                        '-o', 'colors-dark.background=235e6f', sys.executable, '-c',
                        'import sys,time; sys.stdout.write("\\x1b[?25l"); sys.stdout.flush(); time.sleep(170)'])
                w = trial.wait_for(lambda: trial.window_for(control, app), description=app)
                ids.append(w['id'])
                trial.wait_for(lambda: window(w['id'])['surface_size'] is not None)
            control('pointer', x=800, y=700)  # Keep the cursor off sampled edges.
            control('focus', ids[0])
            pixel = screenshot('initial')
            assert near(color_at(pixel, ids[0], 1, 1), clear), 'Rounded corner was not clipped'
            assert not near(color_at(pixel, ids[0], 14, 1), clear), 'Window interior was clipped'
            assert near(color_at(pixel, ids[0], -1, 50), (171, 145, 199)), 'Missing lavender focus ring'
            assert near(color_at(pixel, ids[1], -1, 50), clear), 'Inactive window has a ring'
            check_corner_coverage(pixel, ids[0])
            control('focus', ids[1])
            pixel = screenshot('focus-moved')
            assert near(color_at(pixel, ids[0], -1, 50), clear), 'Stale focus ring'
            assert near(color_at(pixel, ids[1], -1, 50), (171, 145, 199))
            click(ids[0], 1, 1)
            assert control()['keyboard_focus'] != ids[0], 'Invisible corner received input'
            control('pointer', x=800, y=700)
            pixel = screenshot('corner-unfocused')
            assert near(color_at(pixel, ids[1], -1, 50), clear), 'Ring survived losing keyboard focus'
            click(ids[0], 20, 20)
            assert control()['keyboard_focus'] == ids[0]
            control('pointer', x=800, y=700)
            for scale in [125, 150, 175, 200, 100]:
                control('scale', scale)
                time.sleep(.25)
                pixel = screenshot(f'scale-{scale}')
                assert near(color_at(pixel, ids[0], 1, 1), clear), f'Corner failed at {scale}%'
                # Fractional scales may place this sample on a partially covered edge.
                assert near(color_at(pixel, ids[0], -1, 50), (171, 145, 199), tolerance=20), f'Ring failed at {scale}%'
                if scale in [100, 200]:
                    check_corner_coverage(pixel, ids[0])
            control('focus', ids[2])
            pixel = screenshot('second-monitor')
            assert near(color_at(pixel, ids[2], 1, 1), clear)
            assert near(color_at(pixel, ids[2], -1, 50), (171, 145, 199)), 'Second monitor mask offset is wrong'
            control('focus', ids[0])
            control('fullscreen')
            time.sleep(.25)
            pixel = screenshot('fullscreen')
            assert near(color_at(pixel, ids[0], 1, 1), (35, 94, 111)), 'Fullscreen is rounded or bordered'
            control('fullscreen')
            revision = control()['config_revision']
            preferences(0, 0)
            trial.wait_for(lambda: control()['config_revision'] > revision and
                           control()['preferences']['decorations']['corner_radius'] == 0)
            pixel = screenshot('disabled')
            assert near(color_at(pixel, ids[0], 1, 1), (35, 94, 111))
            assert near(color_at(pixel, ids[0], -1, 50), clear)
            click(ids[0], 1, 1)
            assert control()['keyboard_focus'] == ids[0], 'Square corner did not receive input'
            control('pointer', x=800, y=700)
            revision = control()['config_revision']
            preferences(30, 4, '[0.2,0.8,0.4,1.0]')
            trial.wait_for(lambda: control()['config_revision'] > revision and
                           control()['preferences']['decorations']['corner_radius'] == 30)
            pixel = screenshot('reloaded')
            assert near(color_at(pixel, ids[0], -2, 50), (51, 204, 102))
            assert near(color_at(pixel, ids[0], 3, 3), clear)
            control('save-config')
            assert '[decorations]' in config.read_text() and '# Decoration fixture' in config.read_text()
            control('workspace', 4)
            time.sleep(.4)
            before = control()['rendered_frames']
            time.sleep(.5)
            assert control()['rendered_frames'] - before <= 1, 'Decorations cause idle repaints'
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
    print('PASS: rounded pixels, corner area coverage, focused ring transfer, corner input, 100–200% scaling, '
          'second output, square fullscreen, live reload/disable/save, idle and parent preservation')


if __name__ == '__main__':
    run()
