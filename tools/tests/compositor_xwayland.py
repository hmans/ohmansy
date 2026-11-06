#!/usr/bin/env python3
"""Verify session-owned X11 displays, rendering, input and clean shutdown."""
import ctypes as C
import ctypes.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import shutil
from PIL import Image

import compositor_support as trial


def probe(result):
    """A real Xlib client; events must arrive through satellite and Shine."""
    x = C.CDLL(ctypes.util.find_library('X11') or 'libX11.so.6')
    pointer, ulong = C.c_void_p, C.c_ulong
    signatures = {
        'XOpenDisplay': (pointer, [C.c_char_p]),
        'XDefaultRootWindow': (ulong, [pointer]),
        'XCreateSimpleWindow': (ulong, [pointer, ulong, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_uint, ulong, ulong]),
        'XStoreName': (C.c_int, [pointer, ulong, C.c_char_p]),
        'XSelectInput': (C.c_int, [pointer, ulong, C.c_long]),
        'XMapWindow': (C.c_int, [pointer, ulong]),
        'XNextEvent': (C.c_int, [pointer, pointer]),
        'XFlush': (C.c_int, [pointer]),
    }
    for name, (restype, argtypes) in signatures.items():
        function = getattr(x, name)
        function.restype, function.argtypes = restype, argtypes
    display = x.XOpenDisplay(None)
    assert display, 'XOpenDisplay failed'
    window = x.XCreateSimpleWindow(display, x.XDefaultRootWindow(display), 0, 0, 400, 300, 0, 0, 0x24A878)
    x.XStoreName(display, window, b'Shine X11 input probe')
    x.XSelectInput(display, window, 1 | 4 | 32768)  # key, button, expose
    x.XMapWindow(display, window)
    x.XFlush(display)
    events = set()
    while True:
        event = (C.c_long * 24)()
        x.XNextEvent(display, C.byref(event))
        events.add(C.cast(event, C.POINTER(C.c_int))[0])
        result.write_text(json.dumps(sorted(events)))


def run():
    trial.ensure_test_display()
    artifacts = Path(tempfile.mkdtemp(prefix='xwayland-', dir=trial.ROOT / '.local/compositor-tests'))
    print(f'Artifacts: {artifacts}', flush=True)
    original = {w['id']: w['pid'] for w in trial.parent_windows()}
    control = trial.Control(artifacts / 'control.sock')
    setup = artifacts / 'setup'
    setup.write_text('#!/bin/sh\nprintf "DISPLAY=%s\\nWAYLAND_DISPLAY=%s\\n" "$DISPLAY" "$WAYLAND_DISPLAY" > "'
                     + str(artifacts / 'environment') + '"\n')
    setup.chmod(0o700)
    env = dict(os.environ, DISPLAY=':199', OHMANSY_COMPOSITOR_SESSION_SETUP=str(setup),
               OHMANSY_COMPOSITOR_SHELL=shutil.which('true'),
               OHMANSY_COMPOSITOR_TERMINAL=shutil.which('true'))
    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--session', '--no-clients', '--test-input',
            '--control-socket', control.path, '--close-after', '40'], env=env, stdout=log, stderr=log)
        try:
            trial.wait_for(lambda: (artifacts / 'environment').exists(), timeout=25, description='satellite readiness and session setup')
            child_env = dict(line.split('=', 1) for line in (artifacts / 'environment').read_text().splitlines() if '=' in line)
            display = child_env['DISPLAY']
            assert display and display != ':199'
            state = control()
            assert child_env['WAYLAND_DISPLAY'] == state['wayland_display']
            events = artifacts / 'events.json'
            control('launch', program=sys.executable, args=[str(Path(__file__).resolve()), '--probe', str(events)])
            window = trial.wait_for(lambda: next((w for w in control()['windows'] if w['title'] == 'Shine X11 input probe'), None), description='mapped X11 window')
            trial.wait_for(lambda: 12 in json.loads(events.read_text()), description='X11 expose')
            assert window['logical_buffer_size'][0] > 0, window
            trial.keys(control, state['pid'], window['id'], [30])
            window = next(w for w in control()['windows'] if w['id'] == window['id'])
            x, y, width, height = window['geometry']
            control('pointer', x=x + width / 2, y=y + height / 2)
            control('button', pressed=True)
            control('button', pressed=False)
            trial.wait_for(lambda: {2, 4, 12}.issubset(json.loads(events.read_text())), description='X11 keyboard, button and expose')
            capture = artifacts / 'x11.png'
            control('screenshot', path=str(capture))
            trial.wait_for(capture.exists, description='X11 framebuffer')
            with Image.open(capture) as image:
                assert sum(count for count, rgb in image.convert('RGB').getcolors(image.width * image.height)
                           if rgb[1] > rgb[0] + 40 and rgb[1] > rgb[2] + 20) > 1000, 'X11 green surface did not render'
            (artifacts / 'verification.json').write_text(json.dumps({'display': display, 'window': window, 'events': json.loads(events.read_text())}, indent=2))
            control('quit')
            assert process.wait(timeout=10) == 0
            number = display[1:]
            trial.wait_for(lambda: not Path(f'/tmp/.X{number}-lock').exists(), description='Xwayland shutdown')
            assert {w['id']: w['pid'] for w in trial.parent_windows()} == original
        finally:
            if process.poll() is None:
                control('quit')
                process.wait(timeout=10)
        # A signal must not orphan satellite or Xwayland either.
        (artifacts / 'environment').unlink()
        process = subprocess.Popen([str(trial.BINARY), '--session', '--no-clients',
            '--control-socket', control.path], env=env, stdout=log, stderr=log)
        try:
            trial.wait_for(lambda: (artifacts / 'environment').exists(), timeout=25, description='second satellite')
            child_env = dict(line.split('=', 1) for line in (artifacts / 'environment').read_text().splitlines() if '=' in line)
            number = child_env['DISPLAY'][1:]
            process.terminate()
            process.wait(timeout=10)
            trial.wait_for(lambda: not Path(f'/tmp/.X{number}-lock').exists(), description='Xwayland cleanup after termination')
        finally:
            if process.poll() is None:
                control('quit')
                process.wait(timeout=10)
    print('X11 session startup, rendering, keyboard, pointer and shutdown passed.')


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--probe':
        probe(Path(sys.argv[2]))
    else:
        run()
