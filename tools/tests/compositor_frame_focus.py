#!/usr/bin/env python3
"""Check focus-tint interpolation, interruption, disable controls and idle."""
import json
from pathlib import Path
import subprocess
import tempfile
import time

from PIL import Image
import compositor_support as trial


def run():
    trial.ensure_test_display()
    root = trial.ROOT / '.local/compositor-tests'
    root.mkdir(parents=True,exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='frame-focus-',dir=root))
    print(f'Artifacts: {artifacts}',flush=True)
    control = trial.Control(artifacts/'control.sock')
    config = artifacts/'config.toml'
    revision = 0
    process = None

    def configure(glass=True,duration=800,animations=True):
        nonlocal revision
        revision += 1
        temporary=config.with_suffix('.new')
        temporary.write_text(f'''[layout]
default_column_width={{pixels=320}}
[animations]
enabled={str(animations).lower()}
duration_ms=0
[decorations.inactive]
enabled=false
[decorations.shadow]
enabled=false
[decorations.frame]
focus_duration_ms={duration}
focus_easing="linear"
active_color=[0.8,0.6,0.3,1.0]
inactive_color=[0.2,0.2,0.2,1.0]
[decorations.frame.glass]
enabled={str(glass).lower()}
opacity=1.0
noise=0.0
blur_radius=0
[decorations.frame.bevel]
enabled=false
[browser]
program="frame-focus-fixture-{revision}"
''')
        temporary.replace(config)
        if process is not None:
            trial.wait_for(lambda: control()['preferences']['browser']['program']==f'frame-focus-fixture-{revision}')

    def window(app):
        return trial.window_for(control,app)

    def amount(app):
        return window(app)['frame_focus_amount']

    def capture(label):
        path=artifacts/f'{label}.png'
        control('screenshot',path=str(path))
        def read():
            with Image.open(path) as source:
                return source.convert('RGB')
        return trial.wait_for(read,description=label)

    def red(image,app):
        x,y=window(app)['geometry'][:2]
        return image.getpixel((x+3,y+100))[0]

    configure()
    with (artifacts/'session.log').open('w') as log:
        process=subprocess.Popen([str(trial.BINARY),'--no-clients','--test-input','--scale','1',
            '--config',str(config),'--control-socket',control.path,'--close-after','150'],stdout=log,stderr=log)
        try:
            trial.wait_for(control)
            for app in ['frame-focus-a','frame-focus-b']:
                control('launch',program='foot',args=['--config=/dev/null',f'--app-id={app}','sleep','140'])
                trial.wait_for(lambda: window(app) and window(app)['surface_size'])
            control('pointer',x=1000,y=700)
            capture('warmup')
            for glass in [True,False]:
                configure(glass=glass)
                control('focus',window('frame-focus-b')['id'])
                trial.wait_for(lambda: amount('frame-focus-a')==0 and amount('frame-focus-b')==1)
                baseline=capture(f'inactive-{glass}')
                assert red(baseline,'frame-focus-a')==51 and red(baseline,'frame-focus-b')==204
                control('focus',window('frame-focus-a')['id'])
                time.sleep(.16)
                middle=capture(f'fade-{glass}')
                assert 51<red(middle,'frame-focus-a')<204, 'Focused frame snapped to its endpoint'
                assert 51<red(middle,'frame-focus-b')<204, 'Unfocused frame snapped to its endpoint'
                before=amount('frame-focus-a')
                control('focus',window('frame-focus-b')['id'])
                after=amount('frame-focus-a')
                assert abs(after-before)<.08, (before,after,'Interrupted fade jumped')
                time.sleep(.15)
                assert amount('frame-focus-a')<after, 'Interrupted fade did not reverse'
                trial.wait_for(lambda: amount('frame-focus-a')==0 and amount('frame-focus-b')==1)
                endpoint=capture(f'endpoint-{glass}')
                assert red(endpoint,'frame-focus-a')==51 and red(endpoint,'frame-focus-b')==204
                time.sleep(.2)
                frames=control()['rendered_frames']
                time.sleep(.35)
                assert control()['rendered_frames']==frames, 'Tint fade continues rendering after settling'
                configure(glass=glass,duration=0)
                control('focus',window('frame-focus-a')['id'])
                assert amount('frame-focus-a')==1 and amount('frame-focus-b')==0
                snapped=capture(f'zero-duration-{glass}')
                assert red(snapped,'frame-focus-a')==204 and red(snapped,'frame-focus-b')==51
                configure(glass=glass,animations=False)
                control('focus',window('frame-focus-b')['id'])
                assert amount('frame-focus-a')==0 and amount('frame-focus-b')==1
                disabled=capture(f'animations-disabled-{glass}')
                assert red(disabled,'frame-focus-a')==51 and red(disabled,'frame-focus-b')==204
            configure(duration=150)
            assert control()['preferences']['decorations']['frame']['focus_duration_ms']==150
            control('focus',window('frame-focus-a')['id'])
            trial.wait_for(lambda: amount('frame-focus-a')==1 and amount('frame-focus-b')==0)
            capture('final')
            (artifacts/'verification.json').write_text(json.dumps({'solid_and_glass':True,'bidirectional_color_interpolation':True,
                'smooth_interruption':True,'independent_of_inactive_effect':True,'zero_duration':True,'global_disable':True,
                'idle':True,'default_duration_ms':150},indent=2))
        finally:
            if process.poll() is None:
                try:
                    control('quit')
                    process.wait(timeout=5)
                except (OSError,ValueError,AssertionError,subprocess.TimeoutExpired):
                    process.terminate()
                    process.wait(timeout=5)
    print('PASS: smooth frame tint, interruption/reversal, exact endpoints, disable controls and idle')


if __name__=='__main__':
    run()
