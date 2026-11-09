#!/usr/bin/env python3
"""Prove tiled windows share wallpaper imports/blur and overlap adds a scene layer."""
from pathlib import Path
import os
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
    artifacts = Path(tempfile.mkdtemp(prefix='shared-blur-', dir=base))
    print(f'Artifacts: {artifacts}', flush=True)
    config = artifacts / 'config.toml'
    ids = [f'shared-blur-{i}' for i in range(4)]
    fixed_scale = os.environ.get('OHMANSY_TEST_FIXED_SCALE')
    config.write_text(f'''[animations]
enabled=false
[layout]
default_column_width={{pixels=250}}
[decorations.inactive]
enabled=false
[decorations.terminal_blur]
app_ids={ids!r}
radius=32
''')
    control = trial.Control(artifacts / 'control.sock')
    wallpaper = None
    script = '''import os,sys,tty
tty.setraw(sys.stdin.fileno())
sys.stdout.write("\\x1b[?25lSHARP WHITE TEXT")
sys.stdout.flush()
while os.read(sys.stdin.fileno(),1):
 sys.stdout.write("\\x1b[48;2;0;255;0mUpdated content\\x1b[0m")
 sys.stdout.flush()
'''
    def stats(): return control()['blur']
    def settle(): time.sleep(.45); return stats()
    def capture(name):
        path=artifacts/f'{name}.png'
        control('screenshot',path=str(path))
        def read():
            with Image.open(path) as image:return image.convert('RGB')
        return trial.wait_for(read,description=name)
    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY),'--no-clients','--test-input',
            '--outputs','2','--scale',fixed_scale or '1','--config',str(config),
            '--control-socket',control.path,'--close-after','100'],stdout=log,stderr=log)
        try:
            state = trial.wait_for(control)
            expected = os.environ.get('OHMANSY_TEST_EXPECT_RENDERER')
            if expected:
                assert expected in state['graphics']['renderer'],state['graphics']
                print('Verified renderer:',state['graphics'],flush=True)
            wallpaper = trial.WallpaperFixture(control,log)
            for index, app in enumerate(ids):
                control('launch',program='foot',args=['--config=/dev/null',f'--app-id={app}',
                    '-o','cursor.blink=no','-o','colors-dark.background=202020',
                    '-o','colors-dark.alpha=0.35',sys.executable,'-c',script])
                window = trial.wait_for(lambda: (w if (w := trial.window_for(control,app)) and w['surface_size'] else None))
                target = state['outputs'][index//2]['name']
                if window['output'] != target: control('move-output-next')
            before = settle()
            print('Four tiled windows:',before,flush=True)
            assert before['sources'] == 2,before
            assert before['wallpaper_imports'] >= 2,before
            assert before['scene_captures'] == 0, 'Tiled windows captured a scene instead of importing wallpaper'
            # Input, client pixels, focus and pointer movement are consumers,
            # not changes to a wallpaper source.
            for app in ids:
                control('focus',trial.window_for(control,app)['id'])
                control.send_keys([30])
            for x in [30,80,130]: control('pointer',x=x,y=100)
            after = settle()
            print('After input/content:',after,flush=True)
            assert after['background_blur_builds'] == before['background_blur_builds'],(before,after)
            assert after['scene_captures'] == 0,after
            assert after['wallpaper_imports'] == before['wallpaper_imports'],(before,after)
            # Each imported wallpaper commit is blurred once, shared by every
            # window/material. Some Qt backends commit before and after Canvas
            # paints, so compare with actual imports rather than paint requests.
            wallpaper.advance()
            trial.wait_for(lambda: stats()['background_blur_builds'] >= after['background_blur_builds']+2)
            changed = settle()
            print('Wallpaper changed:',changed,flush=True)
            builds=changed['background_blur_builds']-after['background_blur_builds']
            assert 2<=builds<=4 and builds==changed['wallpaper_imports']-after['wallpaper_imports'],(after,changed)
            assert changed['filter_passes']-after['filter_passes'] == builds*3,(after,changed)
            assert changed['scene_captures'] == 0,changed
            control('configure-blur',radius=20)
            radius = settle()
            print('Radius changed:',radius,flush=True)
            assert radius['background_blur_builds']-changed['background_blur_builds'] == 2,(changed,radius)
            control('configure-blur',radius=32)
            assert settle()['background_blur_builds'] == radius['background_blur_builds'], 'Previously blurred radius was discarded'
            # Overlapping frames need their lower window; content blur still
            # consumes the wallpaper source and does not add another capture.
            control('focus',trial.window_for(control,ids[1])['id'])
            control('toggle-floating')
            overlap = settle()
            print('Overlapping frame:',overlap,flush=True)
            assert overlap['scene_captures'] > radius['scene_captures'],(radius,overlap)
            assert overlap['background_blur_builds'] == radius['background_blur_builds'],(radius,overlap)
            assert overlap['sources'] == 3,overlap
            control('toggle-floating')
            assert settle()['sources'] == 2,'Unused overlap scene source leaked'
            for scale in ([] if fixed_scale else [125,200]):
                control('scale',scale)
                scaled = settle()
                assert scaled['scene_captures'] == overlap['scene_captures'],scaled
                assert scaled['sources'] == 2,scaled
            print('Final:',stats(),flush=True)
            # Transparent, unblurred title-bar interiors should sample the
            # exact wallpaper coordinates, including fractional scale, imports
            # with inverted textures and the second output's canvas offset.
            config.write_text(config.read_text()+'''
[decorations.frame]
active_color=[0.0,0.0,0.0,0.0]
inactive_color=[0.0,0.0,0.0,0.0]
[decorations.frame.glass]
blur_radius=0
opacity=1.0
noise=0.0
[decorations.frame.bevel]
enabled=false
''')
            control('reload-config')
            for scale in ([round(float(fixed_scale)*100)] if fixed_scale else [100,125,200]):
                control('scale',scale);settle()
                state=control();points=[]
                for app in [ids[0],ids[2]]:
                    w=trial.window_for(control,app)
                    o=next(o for o in state['outputs'] if o['name']==w['output'])
                    canvas=sum(out['physical_size'][0] for out in state['outputs'][:state['outputs'].index(o)])
                    x,y,_,_=w['content_geometry']
                    points.append((round((x-o['position'][0]+173-7)*o['scale'])+canvas,
                                   round((y-o['position'][1]-30+15)*o['scale'])))
                actual=capture(f'sample-{scale}')
                for app in [ids[0],ids[2]]:
                    control('focus',trial.window_for(control,app)['id']);control('workspace',2)
                reference=capture(f'wallpaper-{scale}')
                for point in points:
                    assert all(abs(a-b)<=2 for a,b in zip(actual.getpixel(point),reference.getpixel(point))), (scale,point,actual.getpixel(point),reference.getpixel(point))
                for app in [ids[0],ids[2]]:
                    control('focus',trial.window_for(control,app)['id'])
            control('scale',round(float(fixed_scale)*100) if fixed_scale else 100);settle()
            control('focus',trial.window_for(control,ids[1])['id']);control('toggle-floating');settle()
            front=trial.window_for(control,ids[1]);back=trial.window_for(control,ids[0])
            fx,fy,fw,fh=front['geometry'];bx,by,bw,bh=back['content_geometry']
            candidates=[(fx+3,fy+min(200,fh//2)),(fx+fw-3,fy+min(200,fh//2)),(fx+173,fy+15)]
            point=next((round(x),round(y)) for x,y in candidates if bx<x<bx+bw and by<y<by+bh)
            state=control();out=next(o for o in state['outputs'] if o['name']==front['output'])
            canvas=sum(o['physical_size'][0] for o in state['outputs'][:state['outputs'].index(out)])
            point=(round((point[0]-out['position'][0])*out['scale'])+canvas,
                   round((point[1]-out['position'][1])*out['scale']))
            actual=capture('scene-layer-sample')
            control('close');trial.wait_for(lambda:trial.window_for(control,ids[1]) is None)
            reference=capture('scene-layer-reference')
            assert all(abs(a-b)<=2 for a,b in zip(actual.getpixel(point),reference.getpixel(point))),('scene layer',point,actual.getpixel(point),reference.getpixel(point))
            text=(artifacts/'session.log').read_text()
            assert 'blur unavailable' not in text.lower() and 'Window glass unavailable' not in text and 'GL_INVALID' not in text,text
            control('quit');process.wait(timeout=10)
            assert process.returncode == 0
        finally:
            if wallpaper:wallpaper.close()
            if process.poll() is None:
                try:control('quit');process.wait(timeout=10)
                except (OSError,ValueError,AssertionError,subprocess.TimeoutExpired):process.terminate();process.wait(timeout=5)
    print('PASS: shared GPU wallpaper, two outputs/four windows, no input/content invalidation, one blur per source/radius, overlapping frame layers, cleanup and scaling')


if __name__ == '__main__':run()
