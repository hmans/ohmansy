#!/usr/bin/env python3
"""Exercise Quickshell panels inside a disposable Shine compositor."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

from PIL import Image, ImageChops

import compositor_support as trial


def run():
    trial.ensure_test_display()
    root = trial.ROOT / '.local/compositor-tests'
    root.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='shell-', dir=root))
    print(f'Artifacts: {artifacts}', flush=True)
    config = artifacts / 'config.toml'
    config.write_text('[animations]\nenabled=false\n')
    control = trial.Control(artifacts / 'control.sock')
    original = {w['id']: w['pid'] for w in trial.parent_windows()}
    shell = None

    def layers_ready():
        return all(o['work_area'][1] == 44 and
                   {layer['namespace'] for layer in o['layers']} ==
                   {'ohmansy-shine-bar', 'ohmansy-wallpaper', 'ohmansy-screenshot-result', 'ohmansy-launcher', 'ohmansy-notifications'} and
                   all(layer['geometry'] and layer['geometry'][2] > 0 and layer['geometry'][3] > 0
                       for layer in o['layers'])
                   for o in control()['outputs'])

    def capture(label):
        path = artifacts / f'{label}.png'
        control('screenshot', path=str(path))

        def read():
            with Image.open(path) as image:
                return image.convert('RGB')
        return trial.wait_for(read, description=label)

    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--test-input',
            '--outputs', '2', '--config', str(config), '--control-socket', control.path,
            '--close-after', '120'], stdout=log, stderr=log)
        try:
            state = trial.wait_for(control, description='Shine')
            environment = dict(os.environ, WAYLAND_DISPLAY=state['wayland_display'],
                               OHMANSY_COMPOSITOR_CONTROL=os.path.relpath(control.path),
                               PWD=str(Path.cwd()), QT_QPA_PLATFORM='wayland',
                               XDG_STATE_HOME=str(artifacts / 'state'),
                               OHMANSY_WALLPAPER_IMAGE='')
            environment.pop('WAYLAND_SOCKET', None)
            environment.pop('NIRI_SOCKET', None)
            shell = subprocess.Popen([os.environ['OHMANSY_COMPOSITOR_SHELL']],
                                     env=environment, stdout=log, stderr=log)
            trial.wait_for(layers_ready, description='two panels and wallpapers')
            for output in control()['outputs']:
                background = next(layer for layer in output['layers']
                                  if layer['namespace'] == 'ohmansy-wallpaper')
                assert background['geometry'] == [0, 0, *output['logical_size']], background
            first_frame = capture('ribbons-first').crop((80, 80, 600, 500))
            shell_log = (artifacts / 'session.log').read_text()
            assert 'Failed to deserialize QShader' not in shell_log and 'shader preparation failed' not in shell_log, 'Workspace material shader failed to load'
            assert max(channel[1] - channel[0] for channel in first_frame.getextrema()) > 20
            time.sleep(0.8)
            next_frame = capture('ribbons-next').crop((80, 80, 600, 500))
            assert ImageChops.difference(first_frame, next_frame).getbbox(), 'Ribbons are not animating'
            def wallpaper(function, *args):
                return json.loads(subprocess.check_output(['quickshell', 'ipc', '--pid', str(shell.pid),
                    'call', 'wallpaper', function, *map(str, args)], env=environment, text=True))
            balanced = wallpaper('status')
            assert balanced == dict(renderScale=.75, particleLayers=2, particleMotionDetail=1, moving=True), balanced
            assert 'error' in wallpaper('configure', .1, 9, 2)
            assert wallpaper('status') == balanced, 'Invalid request partially changed fidelity'
            assert wallpaper('quality', 'high')['particleLayers'] == 3
            low = wallpaper('quality', 'low')
            assert low['renderScale'] == .5 and low['particleMotionDetail'] == 0, low
            assert wallpaper('quality', 'balanced') == balanced
            wallpaper('pause', 'true')
            time.sleep(.3)
            paused = capture('paused-first').crop((80, 80, 600, 500))
            time.sleep(.4)
            assert not ImageChops.difference(paused, capture('paused-next').crop((80, 80, 600, 500))).getbbox(), 'Pause kept moving'
            wallpaper('pause', 'false')
            time.sleep(.5)
            assert ImageChops.difference(paused, capture('resumed').crop((80, 80, 600, 500))).getbbox(), 'Resume stayed frozen'
            wrapper = Path(os.environ['OHMANSY_COMPOSITOR_SHELL']).read_text()
            appearance = re.search(r'export OHMANSY_APPEARANCE=(\S+)', wrapper).group(1)
            original_appearance = subprocess.check_output([appearance, 'read'], env=environment, text=True).strip().strip("'")
            try:
                for preference, foreground in [('prefer-light', (32, 32, 36)),
                                                ('prefer-dark', (245, 245, 245))]:
                    subprocess.run([appearance, preference], env=environment, check=True)

                    def brand_has_foreground():
                        scale = control()['outputs'][0]['scale']
                        brand = capture(preference).crop(tuple(round(value * scale)
                            for value in (15, 8, 80, 36)))
                        return sum(all(abs(a - b) <= 3 for a, b in zip(pixel, foreground))
                                   for pixel in brand.getdata()) > 10

                    trial.wait_for(brand_has_foreground, description=f'{preference} bar text')
            finally:
                subprocess.run([appearance, original_appearance], env=environment, check=True)
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
            # Plain brand text followed by four workspace buttons.
            click(first, 95)
            assert control()['keyboard_focus'] == focused, 'Panel stole keyboard focus'
            click(second, 135)
            trial.wait_for(lambda: control()['outputs'][1]['workspace'] == 2,
                           description='workspace button targets its monitor')
            assert control()['outputs'][0]['workspace'] == 1
            def launcher_status():
                return json.loads(subprocess.check_output(['quickshell', 'ipc', '--pid', str(shell.pid),
                    'call', 'launcher', 'status'], env=environment, text=True))

            click(second, 40)
            trial.wait_for(lambda: launcher_status()['opened'], description='brand opens launcher')
            time.sleep(.5)  # Wait for the mapped launcher's keyboard focus.
            control.send_keys([24, 25, 18, 49, 57, 20, 18, 19, 50, 23, 49, 30, 38])  # open terminal
            trial.wait_for(lambda: launcher_status()['selected'] == 'desktop:terminal')
            control.send_keys([28])
            trial.wait_for(lambda: len(control()['windows']) == 2, description='launcher terminal')
            assert next(w for w in control()['windows'] if w['id'] != window['id'])['output'] == second['name']
            # The real monitor panel must open from Shine and read its outputs.
            click(first, 40)
            trial.wait_for(lambda: launcher_status()['opened'])
            time.sleep(.5)
            control.send_keys([32, 23, 31, 25, 38, 30, 21, 31])  # displays
            trial.wait_for(lambda: launcher_status()['selected'] == 'desktop:displays')
            control.send_keys([28])
            display_window = trial.wait_for(lambda: next((w for w in control()['windows']
                if w['title'] == 'ohmansy displays' and w['surface_size']), None),
                description='launcher opens monitor settings')
            time.sleep(1)  # Let the controller read the real monitor list.
            capture('display-settings')
            control('focus', display_window['id'])
            control('close')
            trial.wait_for(lambda: all(w['id'] != display_window['id'] for w in control()['windows']),
                           description='monitor settings close')
            control('focus', window['id'])
            control('fullscreen')
            assert trial.window_for(control, 'shine-shell-test')['geometry'] == [
                *first['position'], *first['logical_size']]
            control('fullscreen')
            control('output', 1)
            control('scale', 150)
            trial.wait_for(lambda: all(layer['geometry'][2] ==
                           control()['outputs'][0]['logical_size'][0]
                           for layer in control()['outputs'][0]['layers']
                           if layer['namespace'] not in {'ohmansy-screenshot-result', 'ohmansy-notifications'}),
                           description='panel and wallpaper follow scale')
            control('screenshot', path=str(artifacts / 'panel.png'))
            trial.wait_for((artifacts / 'panel.png').exists, description='panel screenshot')
            (artifacts / 'status.json').write_text(json.dumps(control(), indent=2))
            shell.terminate()
            shell.wait(timeout=10)
            trial.wait_for(lambda: all(o['work_area'][1] == 0 and not o['layers']
                                      for o in control()['outputs']), description='panel space released')
            assert trial.window_for(control, 'shine-shell-test')['geometry'][1] == 12
            # A uniform image makes the alpha blend measurable, independently
            # of ribbon motion, theme, and any personal wallpaper selection.
            background = (80, 120, 180)
            image_path = artifacts / 'custom wallpaper.png'
            Image.new('RGB', (32, 32), background).save(image_path)
            environment['OHMANSY_WALLPAPER_IMAGE'] = str(image_path)
            shell = subprocess.Popen([os.environ['OHMANSY_COMPOSITOR_SHELL']],
                                     env=environment, stdout=log, stderr=log)
            trial.wait_for(layers_ready, description='panels and wallpapers restart')
            # An empty part of the bar must show the wallpaper without a tint.
            scale = control()['outputs'][0]['scale']
            blank_x = control()['outputs'][0]['logical_size'][0] * .65
            # Sample the top padding to avoid controls at fractional scales.
            bar_pixel = (round(blank_x * scale), round(2 * scale))
            trial.wait_for(lambda: all(abs(a - b) <= 2 for a, b in zip(
                capture('transparent-bar').getpixel(bar_pixel), background)),
                description='transparent panel background')
            # Check actual control pixels, so a missing shader cannot pass just
            # because labels, click handlers and the transparent bar still work.
            material = capture('workspace-material')
            frame = control()['preferences']['decorations']['frame']
            for x, field in [(104, 'active_color'), (136, 'inactive_color')]:
                tint = frame[field]
                alpha = tint[3] * frame['glass']['opacity']
                expected = tuple(round(tint[i] * 255 * alpha + background[i] * (1-alpha)) for i in range(3))
                actual = material.getpixel((round(x*scale),round(12*scale)))
                assert all(abs(a-b)<=5 for a,b in zip(actual,expected)), (field,actual,expected)
            northwest = material.getpixel((round(104*scale),round(6*scale)))
            southeast = material.getpixel((round(104*scale),round(37*scale)))
            assert sum(northwest)>sum(southeast)+8, ('Workspace bevel lighting missing',northwest,southeast)
            control('launch', program='foot', args=['--app-id=shine-alpha-test',
                    '--override=main.initial-color-theme=dark',
                    '--override=colors-dark.alpha=0.85',
                    '--override=colors-dark.background=202020', 'sleep', '100'])
            terminal = trial.wait_for(lambda: trial.window_for(control, 'shine-alpha-test'))
            x, y, width, height = terminal['geometry']
            scale = control()['outputs'][0]['scale']
            point = (round((x + width / 2) * scale), round((y + height / 2) * scale))
            expected = tuple(round(32 * 0.85 + channel * 0.15) for channel in background)

            def blended():
                actual = capture(f'alpha-{time.monotonic_ns()}').getpixel(point)
                return all(abs(a - b) <= 3 for a, b in zip(actual, expected))
            trial.wait_for(blended, description='wallpaper visible through foot at 85% opacity')
            control('pointer', x=x + width / 2, y=y + height / 2)
            control('button', pressed=True)
            control('button', pressed=False)
            assert control()['keyboard_focus'] == terminal['id'], 'Wallpaper blocked the terminal'
            shell.terminate()
            shell.wait(timeout=10)
            trial.wait_for(lambda: all(not o['layers'] for o in control()['outputs']),
                           description='shell stopped before fallback check')
            environment['QT_QUICK_BACKEND'] = 'software'
            environment['OHMANSY_WALLPAPER_IMAGE'] = ''
            shell = subprocess.Popen([os.environ['OHMANSY_COMPOSITOR_SHELL']],
                                     env=environment, stdout=log, stderr=log)
            trial.wait_for(layers_ready, description='software-rendered fallback')
            control('workspace', 3)
            time.sleep(0.5)
            fallback = capture('fallback-first').crop((80, 80, 600, 500))
            assert max(hi - lo for lo, hi in fallback.getextrema()) > 20, 'Fallback image missing'
            time.sleep(0.3)
            assert not ImageChops.difference(fallback,
                capture('fallback-next').crop((80, 80, 600, 500))).getbbox(), 'Fallback is not stationary'
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
    print('PASS: animated wallpapers, image override, software fallback, foot transparency, two panels, reserved space, '
          'runtime fidelity, validation, pause/resume, light/dark bar text, workspace/launcher clicks, keyboard focus, fullscreen, scale, clean shell exit '
          'and parent windows preserved')


if __name__ == '__main__':
    run()
