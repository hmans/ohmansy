#!/usr/bin/env python3
"""Check real backdrop blur, translucency and stationary grain privately."""
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
    artifacts = Path(tempfile.mkdtemp(prefix='glass-', dir=base))
    print(f'Artifacts: {artifacts}', flush=True)
    control = trial.Control(artifacts / 'control.sock')
    config = artifacts / 'config.toml'
    def configure(blur=0, noise=0, opacity=1.0, tint='[0.0,0.0,0.0,0.0]'):
        temporary = config.with_suffix('.new')
        temporary.write_text(f'''[layout]
gap=30
default_column_width={{pixels=1600}}
[animations]
enabled=false
[decorations.shadow]
enabled=false
[decorations.inactive]
enabled=false
[decorations.frame]
active_color={tint}
[decorations.frame.glass]
blur_radius={blur}
noise={noise}
opacity={opacity}
''')
        temporary.replace(config)
    configure()

    def win(app='glass-front'):
        return trial.window_for(control, app)

    def capture(label):
        path = artifacts / f'{label}.png'
        (artifacts / f'{label}.json').write_text(json.dumps(control(), indent=2))
        control('screenshot', path=str(path))
        def read():
            with Image.open(path) as source:
                return source.convert('RGB')
        return trial.wait_for(read, description=label)

    def samples(image):
        state, w = control(), win()
        out = next(o for o in state['outputs'] if o['name'] == w['output'])
        # Floating terminals can round their configure down to a whole cell.
        # Frames hug committed client geometry, rather than the requested slot.
        style = state['preferences']['decorations']['frame']
        x,y = w['content_geometry'][:2]
        x -= style['width']
        y -= style['titlebar_height']
        width = w['client_geometry'][2] + style['width'] * 2
        height = w['client_geometry'][3] + style['titlebar_height'] + style['width']
        scale = out['scale']
        canvas = sum(o['physical_size'][0] for o in state['outputs'][:state['outputs'].index(out)])
        x -= out['position'][0]
        y -= out['position'][1]
        row = int((y + style['titlebar_height'] / 2) * scale)
        if y + style['titlebar_height'] / 2 < win('glass-back')['content_geometry'][1]:
            # At 200% the floating window can fill the work area; its top edge
            # then has wallpaper behind it. Check the right edge over the app.
            points = [(int((x+width-3)*scale), int((y+py)*scale)) for py in range(80,min(380,height-30))]
        else:
            points = [(int((x+px)*scale), row) for px in range(200,min(500,width-30))]
        return [image.getpixel((point[0]+canvas,point[1])) for point in points
            if 0 <= point[0] < out['physical_size'][0] and 0 <= point[1] < image.height]

    def wait_config(blur, noise=0):
        trial.wait_for(lambda: control()['preferences']['decorations']['frame']['glass']['blur_radius'] == blur
            and abs(control()['preferences']['decorations']['frame']['glass']['noise'] - noise) < .000001)
        time.sleep(.2)

    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--test-input', '--outputs', '2', '--scale', '1',
            '--config', str(config), '--control-socket', control.path, '--close-after', '180'], stdout=log, stderr=log)
        try:
            trial.wait_for(control)
            pattern = '''import os, select, sys, tty
tty.setraw(sys.stdin.fileno())
changed=False
size=None
while True:
    latest=os.get_terminal_size()
    if latest!=size:
        size=latest
        width,height=size
        sys.stdout.write("\\x1b[?25l")
        for row in range(height):
            sys.stdout.write(f"\\x1b[{row+1};1H")
            for col in range(width):
                color=("255;255;0" if (col+row)%2 else "0;255;255") if changed else ("255;0;0" if (col+row)%2 else "0;0;255")
                sys.stdout.write(f"\\x1b[48;2;{color}m ")
        sys.stdout.flush()
    if select.select([sys.stdin],[],[],.1)[0]:
        if not os.read(sys.stdin.fileno(),1): break
        changed=True
        size=None
'''
            control('launch', program='foot', args=['--config=/dev/null','--app-id=glass-back','-o','pad=0x0',sys.executable,'-c',pattern])
            trial.wait_for(lambda: win('glass-back') and win('glass-back')['surface_size'])
            control('launch', program='foot', args=['--config=/dev/null','--app-id=glass-front','-o','colors-dark.background=116422',
                sys.executable,'-c','import sys,time; sys.stdout.write("\\x1b[?25l\\x1b]2;Frosted glass\\x07"); sys.stdout.flush(); time.sleep(160)'])
            trial.wait_for(lambda: win() and win()['surface_size'])
            control('toggle-floating')
            control('focus', win('glass-back')['id'])
            control('focus', win()['id'])
            control('pointer', x=10, y=10)
            time.sleep(.5)
            prefs = control()['preferences']['decorations']['frame']
            assert [prefs[key] for key in ['width','titlebar_height','icon_width','icon_height','title_padding','outer_corner_radius','inner_corner_radius']] == [7,30,18,18,11,10,8]
            sharp_image = capture('sharp-backdrop')
            sharp = samples(sharp_image)
            assert sum(max(r,b)>230 and min(r,b)<10 and g<10 for r,g,b in sharp) > len(sharp)*.8, ('Backdrop is not the window behind', sharp[:15])
            configure(blur=14)
            wait_config(14)
            blurred_image = capture('blurred-backdrop')
            blurred = samples(blurred_image)
            assert sum(r>35 and b>35 and g<10 for r,g,b in blurred) > len(blurred)*.8, ('Blur did not mix the checkerboard', blurred[:15])
            x,y,_,_ = win()['geometry']
            assert blurred_image.getpixel((x+100,y+100)) == (17,100,34), 'Glass changed client content'
            configure(blur=14,noise=.08)
            wait_config(14,.08)
            noisy_image = capture('grain')
            noisy = samples(noisy_image)
            assert noisy != blurred, 'Grain missing'
            assert max(abs(a-b) for p,q in zip(noisy,blurred) for a,b in zip(p,q)) <= 12, 'Grain is too strong'
            assert noisy == samples(capture('stationary-grain')), 'Grain shimmers without a scene change'
            configure(blur=14,opacity=.55,tint='[0.317647,0.250980,0.372549,0.55]')
            wait_config(14)
            assert samples(capture('translucent-tint')) != blurred, 'Glass tint/transparency missing'
            control('focus', win('glass-back')['id'])
            control('key', code=30, pressed=True)
            control('key', code=30, pressed=False)
            control('focus', win()['id'])
            configure(blur=14)
            wait_config(14)
            trial.wait_for(lambda: sum(g>200 for r,g,b in samples(capture('updated-backdrop'))) > len(blurred)*.8,
                description='glass updates when the window behind repaints')
            for scale in [125,200]:
                control('scale', scale)
                time.sleep(.3)
                assert sum(g>180 for r,g,b in samples(capture(f'scale-{scale}'))) > 100, 'Scaled backdrop is missing'
            control('scale',100)
            control('fullscreen')
            time.sleep(.2)
            assert win()['geometry'] == win()['content_geometry']
            control('fullscreen')
            time.sleep(.2)
            control('focus',win('glass-back')['id'])
            control('move-output-next')
            control('focus',win()['id'])
            control('move-output-next')
            if not win()['floating']:
                control('toggle-floating')
            control('focus',win('glass-back')['id'])
            control('focus',win()['id'])
            time.sleep(.4)
            assert win()['output'] == win('glass-back')['output'] == control()['outputs'][1]['name']
            second = samples(capture('second-output'))
            assert second and sum(g>180 for r,g,b in second) > len(second)*.8, 'Backdrop on second output is missing'
            configure(blur=12,noise=.025,opacity=.9,tint='[0.317647,0.250980,0.372549,0.55]')
            wait_config(12,.025)
            capture('final')
            time.sleep(.3)
            frames=control()['rendered_frames']
            time.sleep(.4)
            assert control()['rendered_frames']==frames, 'Glass repaints while idle'
            assert 'Window glass unavailable' not in (artifacts/'session.log').read_text(), 'Glass fell back to a flat frame'
            (artifacts/'verification.json').write_text(json.dumps({'gpu_backdrop_path':True,'blur':True,'translucency':True,
                'stationary_noise':True,'client_preserved':True,'live_background_updates':True,'scales':[100,125,200],'two_outputs':True,'idle':True},indent=2))
        finally:
            if process.poll() is None:
                try:
                    control('quit')
                    process.wait(timeout=5)
                except (OSError,ValueError,AssertionError,subprocess.TimeoutExpired):
                    process.terminate()
                    process.wait(timeout=5)
    print('PASS: actual backdrop blur, transparency, stationary grain, live updates, scale and idle')


if __name__ == '__main__':
    run()
