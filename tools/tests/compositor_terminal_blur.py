#!/usr/bin/env python3
"""Prove terminal backgrounds blur shared wallpaper while text stays sharp."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from PIL import Image, ImageChops
import compositor_support as trial


def run():
    trial.ensure_test_display()
    base = trial.ROOT / '.local/compositor-tests'
    base.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='terminal-blur-', dir=base))
    print(f'Artifacts: {artifacts}', flush=True)
    config = artifacts / 'config.toml'
    control = trial.Control(artifacts / 'control.sock')
    revision = 0
    process = None
    wallpaper = None
    fixed_scale = os.environ.get('OHMANSY_TEST_FIXED_SCALE')

    def configure(radius=0, frames=True, enabled=True, ids=('blur-front',)):
        nonlocal revision
        revision += 1
        config.write_text(f'''[animations]
enabled=false
[browser]
program="blur-fixture-{revision}"
[layout]
default_column_width={{pixels=1600}}
[decorations.inactive]
enabled=false
[decorations.shadow]
enabled=false
[decorations.frame]
enabled={str(frames).lower()}
[decorations.frame.glass]
enabled=false
[decorations.terminal_blur]
enabled={str(enabled).lower()}
radius={radius}
app_ids={json.dumps(list(ids))}
''')
        if process:
            trial.wait_for(lambda: control()['preferences']['browser']['program'] == f'blur-fixture-{revision}')
            time.sleep(.2)

    def win(): return trial.window_for(control, 'blur-front')

    def capture(name):
        path = artifacts / f'{name}.png'
        control('screenshot', path=str(path))
        def read():
            with Image.open(path) as image: return image.convert('RGB')
        return trial.wait_for(read, description=name)

    def area(image):
        x,y,_,_ = win()['content_geometry']
        scale = control()['outputs'][0]['scale']
        return image.crop(tuple(round(v*scale) for v in (x+70,y+80,x+350,y+170)))

    def contrast(image):
        pixels = list(area(image).getdata())
        return sum(abs(r-b) for r,g,b in pixels)/len(pixels)

    configure()
    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY),'--no-clients','--test-input','--scale',fixed_scale or '1',
            '--config',str(config),'--control-socket',control.path,'--close-after','180'], stdout=log,stderr=log)
        try:
            state = trial.wait_for(control)
            expected_renderer = os.environ.get('OHMANSY_TEST_EXPECT_RENDERER')
            if expected_renderer:
                assert expected_renderer in state['graphics']['renderer'], state['graphics']
                print('Verified renderer:', state['graphics'], flush=True)
            wallpaper = trial.WallpaperFixture(control, log)
            text = 'import sys,time;sys.stdout.write("\\x1b[?25l\\x1b[38;2;255;255;255mSHARP WHITE TEXT\\x07");sys.stdout.flush();time.sleep(160)'
            control('launch',program='foot',args=['--config=/dev/null','--app-id=blur-front',
                '-o','font=monospace:size=16',
                '-o','colors-dark.background=202020','-o','colors-dark.alpha=0.35',sys.executable,'-c',text])
            trial.wait_for(lambda: win() and win()['surface_size'])
            control('toggle-floating')
            control('pointer',x=10,y=10)
            time.sleep(.5)
            cases = [(True,100),(True,125),(True,200),(False,100)] if not fixed_scale else [(True,round(float(fixed_scale)*100)),(False,round(float(fixed_scale)*100))]
            for frames, scale in cases:
                control('scale',scale)
                configure(frames=frames)
                sharp = capture(f'sharp-{frames}-{scale}')
                configure(radius=14,frames=frames)
                blurred = capture(f'blurred-{frames}-{scale}')
                assert contrast(sharp)>80, ('Missing sharp checkerboard',contrast(sharp))
                assert contrast(blurred)<contrast(sharp)*.7, ('Background stayed sharp',contrast(sharp),contrast(blurred))
                configure(radius=32,frames=frames)
                stronger = capture(f'stronger-{frames}-{scale}')
                print('Blur contrast', frames, scale, contrast(sharp), contrast(blurred), contrast(stronger), flush=True)
                assert contrast(stronger)<contrast(blurred), ('Larger radius did not soften the pattern',contrast(blurred),contrast(stronger))
                blurred = stronger
                # Fully opaque white glyph pixels survive at the exact same positions.
                x,y,_,_ = win()['content_geometry']
                density=control()['outputs'][0]['scale']
                glyphs=tuple(round(v*density) for v in (x+2,y+1,x+180,y+35))
                original = list(sharp.crop(glyphs).getdata()); current = list(blurred.crop(glyphs).getdata())
                white = [i for i,p in enumerate(original) if min(p)>248]
                assert len(white)>30 and all(min(current[i])>248 for i in white), 'Blur softened opaque text'
                assert not ImageChops.difference(blurred,capture(f'idle-{frames}-{scale}')).getbbox(), 'Blur shimmered while idle'
                configure(radius=14,frames=frames,enabled=False)
                assert not ImageChops.difference(area(sharp),area(capture(f'disabled-{frames}-{scale}'))).getbbox()
                configure(radius=14,frames=frames,ids=())
                assert not ImageChops.difference(area(sharp),area(capture(f'unmatched-{frames}-{scale}'))).getbbox()
            configure(radius=14,frames=False)
            control('fullscreen')
            full_blur=capture('fullscreen-blur')
            configure(frames=False)
            full_sharp=capture('fullscreen-sharp')
            # Foot makes its fullscreen buffer opaque, even with alpha set.
            # Keep that buffer unchanged rather than forcing translucency.
            assert not ImageChops.difference(full_blur,full_sharp).getbbox(), 'Blur changed opaque fullscreen content'
            control('fullscreen')
            configure(radius=14,frames=False)
            capture('static-blur');time.sleep(.3)
            before=control()['rendered_frames']; time.sleep(.3)
            assert control()['rendered_frames']<=before+1, 'Static terminal blur keeps rendering'
            wallpaper_only = area(capture('wallpaper-only-reference'))
            control('launch',program='foot',args=['--config=/dev/null','--app-id=blur-opaque',
                '-o','colors-dark.background=336644','-o','colors-dark.alpha=1.0','sleep','120'])
            opaque=trial.wait_for(lambda: trial.window_for(control,'blur-opaque') and trial.window_for(control,'blur-opaque')['surface_size'])
            control('focus',win()['id'])
            time.sleep(.2)
            assert not ImageChops.difference(wallpaper_only,area(capture('wallpaper-only-over-app'))).getbbox(), 'Terminal sampled another app instead of shared wallpaper'
            configure(frames=False,ids=('blur-opaque',))
            unblurred=capture('opaque-without-blur')
            configure(radius=14,frames=False,ids=('blur-opaque',))
            unaffected=capture('opaque-with-blur')
            window=trial.window_for(control,'blur-opaque')
            x,y,w,h=window['content_geometry']
            density=control()['outputs'][0]['scale']
            clip=tuple(round(v*density) for v in (x+30,y+40,x+w-30,y+h-30))
            assert not ImageChops.difference(unblurred.crop(clip),unaffected.crop(clip)).getbbox(), 'Blur changed an opaque terminal'
            assert 'GL_INVALID' not in (artifacts/'session.log').read_text(),'GPU error in blur path'
            control('quit'); process.wait(timeout=10)
            assert process.returncode==0
        finally:
            if wallpaper: wallpaper.close()
            if process.poll() is None:
                try: control('quit');process.wait(timeout=10)
                except (OSError,AssertionError,subprocess.TimeoutExpired): process.terminate();process.wait(timeout=5)
    print('PASS: terminal blur, sharp text, matching/disable, frames/frameless/fullscreen, opaque terminals, 100/125/200% and idle')


if __name__=='__main__': run()
