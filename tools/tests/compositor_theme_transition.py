#!/usr/bin/env python3
"""Check frame and wallpaper colors between palette endpoints and on reversal."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
from PIL import Image, ImageChops
import compositor_support as trial


def run():
    trial.ensure_test_display()
    base=trial.ROOT/'.local/compositor-tests';base.mkdir(parents=True,exist_ok=True)
    artifacts=Path(tempfile.mkdtemp(prefix='theme-transition-',dir=base))
    print(f'Artifacts: {artifacts}',flush=True)
    control=trial.Control(artifacts/'control.sock')
    config=artifacts/'config.toml'
    def configure(duration=1000,animations=True,primary=(1,0,0)):
        config.write_text(f'''[animations]
enabled={str(animations).lower()}
[layout]
default_column_width={{pixels=480}}
[decorations.inactive]
enabled=false
[decorations.shadow]
enabled=false
[decorations.frame]
active_color=[0.3,0.3,0.3,1.0]
focus_duration_ms=0
[decorations.frame.glass]
enabled=false
[theme]
transition_duration_ms={duration}
[theme.lighting]
strength=0.0
[theme.palette]
primary={list(primary)}
secondary=[0.0,1.0,0.0]
accent=[0.0,0.0,1.0]
''')
    configure()
    def capture(name):
        path=artifacts/f'{name}.png';control('screenshot',path=str(path))
        def read():
            with Image.open(path) as image:return image.convert('RGB')
        return trial.wait_for(read,description=name)
    def frame(image):
        w=trial.window_for(control,'theme-probe');x,y,_,_=w['geometry']
        return image.getpixel((x+100,y+10))
    def light(function):
        reply=subprocess.check_output(['quickshell','ipc','--pid',str(shell.pid),
            'call','lighting',function],env=environment,text=True)
        return json.loads(reply) if reply.strip() else None
    def click(px,py):
        out=control()['outputs'][0]
        control('pointer',x=out['logical_size'][0]+px,y=py)
        control('button',pressed=True);control('button',pressed=False)
    shell=None
    with (artifacts/'session.log').open('w') as log:
        process=subprocess.Popen([str(trial.BINARY),'--no-clients','--test-input','--scale','1',
            '--config',str(config),'--control-socket',control.path,'--close-after','90'],stdout=log,stderr=log)
        try:
            state=trial.wait_for(control)
            environment=dict(os.environ,WAYLAND_DISPLAY=state['wayland_display'],
                OHMANSY_COMPOSITOR_CONTROL=control.path,OHMANSY_WALLPAPER_IMAGE='',QT_QPA_PLATFORM='wayland')
            environment.pop('WAYLAND_SOCKET',None)
            shell=subprocess.Popen([os.environ['OHMANSY_COMPOSITOR_SHELL']],env=environment,stdout=log,stderr=log)
            trial.wait_for(lambda: control()['outputs'][0]['work_area'][1]==44)
            trial.wait_for(lambda: abs(light('status')['displayedFrame'][0] - control()['preferences']['theme_materials']['active_frame'][0])<.002)
            assert not light('status')['transitioning'], 'Startup palette should load without a fade'
            # Keep timed software-renderer assertions independent of ribbon
            # shader throughput; color uniforms and transition cadence are unchanged.
            subprocess.check_call(['quickshell','ipc','--pid',str(shell.pid),'call','wallpaper','configure','.25','0','0'],env=environment,stdout=subprocess.DEVNULL)
            subprocess.check_call(['quickshell','ipc','--pid',str(shell.pid),'call','wallpaper','pause','true'],env=environment,stdout=subprocess.DEVNULL)
            control('launch',program='foot',args=['--config=/dev/null','--app-id=theme-probe','-o','cursor.blink=no','sleep','80'])
            trial.wait_for(lambda: trial.window_for(control,'theme-probe') and trial.window_for(control,'theme-probe')['surface_size'])
            time.sleep(.25)
            light('toggle');time.sleep(.2)
            initial=capture('initial')
            def expected_frame(): return tuple(round(v*255) for v in control()['preferences']['theme_materials']['active_frame'])
            assert all(abs(a-b)<=2 for a,b in zip(frame(initial),expected_frame())), (frame(initial),expected_frame())
            click(-204,398)  # Lagoon: cyan/orange/indigo.
            trial.wait_for(lambda: light('status')['theme']=='Lagoon')
            time.sleep(.3)
            mid=capture('middle')
            displayed=light('status')['displayedFrame']
            assert light('status')['transitioning']
            assert frame(mid)!=frame(initial), (frame(mid),frame(initial))
            assert frame(mid)!=expected_frame(), (frame(mid),expected_frame())
            # Retarget from the visible intermediate value, without an endpoint jump.
            before=light('status')['displayedFrame']
            click(-204,492)  # Rose: vivid pink/ice blue/violet.
            after=light('status')['displayedFrame']
            assert max(abs(a-b) for a,b in zip(before,after))<.2,(before,after)
            trial.wait_for(lambda: not light('status')['transitioning'],timeout=4)
            time.sleep(.15)
            end=capture('endpoint')
            expected=expected_frame()
            assert all(abs(a-b)<=2 for a,b in zip(frame(end),expected)),(frame(end),expected)
            crop=(700,800,1100,1000)
            assert ImageChops.difference(initial.crop(crop),mid.crop(crop)).getbbox(), 'Wallpaper did not fade'
            assert ImageChops.difference(mid.crop(crop),end.crop(crop)).getbbox(), 'Wallpaper stayed at an intermediate color'
            time.sleep(.3)
            before_idle=control();time.sleep(.4)
            after_idle=control()
            assert after_idle['rendered_frames']<=before_idle['rendered_frames']+1, ('Theme animation kept rendering after settling',
                before_idle['rendered_frames'],after_idle['rendered_frames'],before_idle['surface_commits'],after_idle['surface_commits'],light('status'))
            configure(duration=0,primary=(0,0,1))
            trial.wait_for(lambda: control()['preferences']['theme']['transition_duration_ms']==0)
            trial.wait_for(lambda: abs(light('status')['displayedFrame'][2]-control()['preferences']['theme_materials']['active_frame'][2])<.002)
            assert not light('status')['transitioning']
            assert all(abs(a-b)<=2 for a,b in zip(frame(capture('zero-duration')),expected_frame()))
            configure(animations=False,primary=(0,1,0))
            trial.wait_for(lambda: control()['preferences']['animations']['enabled'] is False)
            trial.wait_for(lambda: abs(light('status')['displayedFrame'][1]-control()['preferences']['theme_materials']['active_frame'][1])<.002)
            assert not light('status')['transitioning']
            assert all(abs(a-b)<=2 for a,b in zip(frame(capture('animations-disabled')),expected_frame()))
            assert 'TypeError:' not in (artifacts/'session.log').read_text()
        finally:
            if shell and shell.poll() is None:shell.terminate();shell.wait(timeout=10)
            if process.poll() is None:
                try: control('quit');process.wait(timeout=10)
                except (OSError,AssertionError,subprocess.TimeoutExpired):process.terminate();process.wait(timeout=5)
    print('PASS: one-second frame/wallpaper interpolation, startup snap, retargeting, zero duration, global disable and idle')


if __name__=='__main__':run()
