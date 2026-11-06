#!/usr/bin/env python3
"""Verify frame lighting and the inward shadow overlay on client content."""
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
    root = trial.ROOT / '.local/compositor-tests'
    root.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='bevel-', dir=root))
    print(f'Artifacts: {artifacts}', flush=True)
    config = artifacts / 'config.toml'
    control = trial.Control(artifacts / 'control.sock')
    revision = 0

    def configure(glass=True, bevel=False, light=(-1,-1), width=3.0, inner_width=2.0, inset=False, offset=(0,0), defaults=False):
        nonlocal revision
        revision += 1
        text = '''[layout]
default_column_width={pixels=480}
[animations]
enabled=false
[decorations.shadow]
enabled=false
[decorations.inactive]
enabled=false
'''
        if not defaults:
            text += f'''[decorations.frame]
active_color=[0.4,0.4,0.4,1.0]
[decorations.frame.glass]
enabled={str(glass).lower()}
opacity=1.0
noise=0.0
blur_radius=0
[decorations.frame.bevel]
enabled={str(bevel).lower()}
width={width}
inner_width={inner_width}
highlight=0.35
shadow=0.30
light_direction={list(light)}
[decorations.frame.inset_shadow]
enabled={str(inset).lower()}
width=4.0
softness=2.0
offset={list(offset)}
color=[0.0,0.0,0.0,0.5]
'''
        # A harmless settings field gives each write a distinct revision even
        # when resetting to an earlier fixture.
        text += f'\n[browser]\nprogram="frame-lighting-fixture-{revision}"\n'
        temporary = config.with_suffix('.new')
        temporary.write_text(text)
        temporary.replace(config)
        if process is not None:
            trial.wait_for(lambda: control()['preferences']['browser']['program'] == f'frame-lighting-fixture-{revision}')
            time.sleep(.15)

    def window():
        return trial.window_for(control, 'frame-bevel-probe')

    def capture(label):
        path = artifacts / f'{label}.png'
        control('screenshot', path=str(path))
        def read():
            with Image.open(path) as source:
                return source.convert('RGB')
        return trial.wait_for(read, description=label)

    def pixel(image, px, py):
        state, win = control(), window()
        scale = state['outputs'][0]['scale']
        x,y = win['geometry'][:2]
        return image.getpixel((int((x+px)*scale), int((y+py)*scale)))

    def edges(image):
        w,h = window()['client_geometry'][2:]
        w,h = w+14,h+37
        positions = dict(top=(w/2,0),left=(0,h/2),bottom=(w/2,h-1),right=(w-1,h/2),
            inner_top=(w/2,29),inner_left=(6,h/2),inner_bottom=(w/2,h-7),inner_right=(w-7,h/2),
            corner_nw=(3,3),corner_se=(w-4,h-4))
        return {name: pixel(image,*point)[0] for name,point in positions.items()}

    process = None
    configure()
    with (artifacts/'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY),'--no-clients','--test-input','--scale','1',
            '--config',str(config),'--control-socket',control.path,'--close-after','180'],stdout=log,stderr=log)
        try:
            trial.wait_for(control)
            code = 'import sys,time; sys.stdout.write("\\x1b[?25l\\x1b]2;Northwest light · beveled glass\\x07"); sys.stdout.flush(); time.sleep(160)'
            control('launch', program='foot', args=['--config=/dev/null','--app-id=frame-bevel-probe',
                '-o','colors-dark.background=112233',sys.executable,'-c',code])
            trial.wait_for(lambda: window() and window()['surface_size'])
            control('pointer',x=1000,y=700)
            for glass in [True, False]:
                configure(glass=glass)
                baseline = edges(capture(f'flat-{glass}'))
                assert set(baseline.values()) == {102}, baseline
                configure(glass=glass,bevel=True)
                lit = edges(capture(f'northwest-{glass}'))
                for name in ['top','left','corner_nw']:
                    assert lit[name] > baseline[name]+8, (name,lit,baseline)
                for name in ['bottom','right','corner_se']:
                    assert lit[name] < baseline[name]-8, (name,lit,baseline)
                assert lit['inner_top'] < 98 and lit['inner_left'] < 98, lit
                assert lit['inner_bottom'] > 108 and lit['inner_right'] > 108, lit
                configure(glass=glass,bevel=True,light=(1,1))
                reversed_light = edges(capture(f'southeast-{glass}'))
                assert reversed_light['top'] < 98 and reversed_light['bottom'] > 108, reversed_light
                assert reversed_light['inner_top'] > 108 and reversed_light['inner_bottom'] < 98, reversed_light
                configure(glass=glass,bevel=True,width=0,inner_width=0)
                assert edges(capture(f'zero-width-{glass}')) == baseline
                configure(glass=glass,inset=True)
                shadow = capture(f'inset-{glass}')
                shaded = edges(shadow)
                assert set(shaded.values()) == {102}, 'Inset shadow changed the frame material'
                assert all(a<b for a,b in zip(pixel(shadow,100,32),(17,34,51))), 'Inset shadow did not overlay app content'
                assert pixel(shadow,100,60) == (17,34,51), 'Shadow did not fade out inside the client'
                assert pixel(shadow,8,31) == (102,102,102), 'Shadow leaked into the frame at a rounded client corner'
                configure(glass=glass,inset=True,offset=(4,0))
                shifted = capture(f'inset-offset-{glass}')
                w,h = window()['client_geometry'][2:]
                left = pixel(shifted,8,h/2+30)[2]
                right = pixel(shifted,w+6,h/2+30)[2]
                assert right > left+10, ('Inset offset did not move the opening',left,right)
            for scale in [125,200]:
                control('scale',scale)
                configure(bevel=True)
                image = capture(f'scale-{scale}')
                lit=edges(image)
                assert lit['top'] > lit['bottom']+12 and lit['left'] > lit['right']+12, lit
                assert pixel(image,100,100) == (17,34,51), 'Lighting changed client pixels'
                configure(inset=True)
                shaded = capture(f'content-shadow-scale-{scale}')
                assert all(a<b for a,b in zip(pixel(shaded,100,32),(17,34,51))), 'Scaled shadow missed the client edge'
                assert pixel(shaded,100,100) == (17,34,51), 'Scaled shadow did not fade out'
            control('scale',100)
            configure(defaults=True)
            capture('final')
            time.sleep(.3)
            frames=control()['rendered_frames']
            time.sleep(.4)
            assert control()['rendered_frames']==frames, 'Lighting repaints while idle'
            (artifacts/'verification.json').write_text(json.dumps({'northwest_light':True,'curved_normals':True,'inner_bevel':True,
                'configurable_direction_and_widths':True,'solid_and_glass':True,'inset_shadow':True,'client_preserved':True,
                'scales':[100,125,200],'idle':True},indent=2))
        finally:
            if process.poll() is None:
                try:
                    control('quit')
                    process.wait(timeout=5)
                except (OSError,ValueError,AssertionError,subprocess.TimeoutExpired):
                    process.terminate()
                    process.wait(timeout=5)
    print('PASS: northwest/southeast lighting, curved/inner bevels, app-content inset shadows, live settings, scale and idle')


if __name__ == '__main__':
    run()
