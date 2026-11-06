#!/usr/bin/env python3
"""Exercise focus, launcher reuse, frames and real GTK transient dialogs."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time
from PIL import Image
import compositor_support as trial


def run():
    trial.ensure_test_display()
    artifacts = Path(tempfile.mkdtemp(prefix='window-policy-', dir=trial.ROOT / '.local/compositor-tests'))
    print(f'Artifacts: {artifacts}', flush=True)
    flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', '--libs', 'gtk4'], text=True))
    client = artifacts / 'client'
    subprocess.run(['cc', '-Wall', '-Wextra', '-Werror', str(Path(__file__).with_name('compositor_window_policy_client.c')), '-o', str(client), *flags], check=True)
    config = artifacts / 'config.toml'
    config.write_text('[animations]\nenabled=false\n[decorations.frame]\nactive_color=[1.0,0.0,0.0,1.0]\ninactive_color=[0.0,1.0,0.0,1.0]\n[decorations.inactive]\nenabled=false\n')
    control = trial.Control(artifacts / 'control.sock')
    command = artifacts / 'command'
    original = {w['id']: w['pid'] for w in trial.parent_windows()}
    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--outputs', '2', '--test-input', '--config', str(config), '--control-socket', control.path, '--close-after', '90'], stdout=log, stderr=log)
        def title(name):
            return next((w for w in control()['windows'] if w['title'] == name and w['surface_size']), None)
        def focus(ident):
            return control()['focused'] == ident and control()['keyboard_focus'] == ident
        try:
            trial.wait_for(control)
            control('launch', program='foot', args=['--app-id=policy-left', 'sleep', '90'])
            left = trial.wait_for(lambda: trial.window_for(control, 'policy-left'))
            trial.wait_for(lambda: focus(left['id']))
            control('launch', program='foot', args=['--app-id=policy-middle', 'sleep', '90'])
            middle = trial.wait_for(lambda: trial.window_for(control, 'policy-middle'))
            trial.wait_for(lambda: focus(middle['id']))
            control('launch', program=str(client), args=[str(command)])
            parent = trial.wait_for(lambda: title('Shine policy parent'))
            trial.wait_for(lambda: focus(parent['id']))
            control('focus', middle['id'])
            control('close')
            trial.wait_for(lambda: not trial.window_for(control, 'policy-middle'))
            trial.wait_for(lambda: focus(left['id']), description='closing middle focuses left')
            control('focus', parent['id'])
            control('move-workspace', 2)
            assert control()['workspace'] == 2 and focus(parent['id'])
            control('workspace', 1)
            entry = artifacts / 'data/applications'
            entry.mkdir(parents=True)
            (entry / 'policy.desktop').write_text('[Desktop Entry]\nType=Application\nName=Policy\nStartupWMClass=org.ohmansy.WindowPolicyProbe\nExec=false\n')
            env = dict(os.environ, OHMANSY_COMPOSITOR_CONTROL=control.path, WAYLAND_DISPLAY=control()['wayland_display'], XDG_DATA_HOME=str(entry.parent))
            before = len(control()['windows'])
            subprocess.run([sys.executable, str(trial.ROOT / 'nix/modules/launcher/activate.py'), 'policy.desktop'], env=env, check=True)
            assert control()['workspace'] == 2 and focus(parent['id'])
            assert len(control()['windows']) == before
            parent_geometry = title('Shine policy parent')['target_geometry']
            command.write_text('dialog')
            dialog = trial.wait_for(lambda: title('Shine policy dialog'))
            trial.wait_for(lambda: focus(dialog['id']))
            assert title('Shine policy parent')['target_geometry'] == parent_geometry
            assert dialog['content_target_geometry'][2] == 420, dialog
            assert dialog['target_geometry'][3] < parent_geometry[3], dialog
            control.send_keys([30])
            trial.wait_for(lambda: command.with_suffix('.key').exists(), description='dialog keyboard input')
            x,y,w,h = title('Shine policy dialog')['geometry']
            control('pointer', x=x+w/2, y=y+h/2)
            control('button', pressed=True)
            control('button', pressed=False)
            trial.wait_for(lambda: command.with_suffix('.click').exists(), description='dialog pointer input')
            control('pointer', x=x+w/2, y=y+16)
            control('button', pressed=True)
            time.sleep(.1)
            control('pointer', x=x+w/2+16, y=y+16)
            time.sleep(.15)
            control('pointer', x=x+w/2+80, y=y-34)
            control('button', pressed=False)
            trial.wait_for(lambda: title('Shine policy dialog')['target_geometry'][:2]!=[x,y], description='floating dialog titlebar drag')
            assert title('Shine policy parent')['target_geometry']==parent_geometry
            control('focus',parent['id'])
            assert focus(dialog['id']), 'Modal dialog must retain keyboard focus above parent'
            image = artifacts / 'frames.png'
            control('screenshot', path=str(image))
            trial.wait_for(image.exists)
            with Image.open(image) as screenshot:
                colors = screenshot.convert('RGB').getcolors(screenshot.width*screenshot.height)
                assert sum(n for n,(r,g,b) in colors if r>180 and g<70 and b<70)>100, 'active frame missing'
                assert sum(n for n,(r,g,b) in colors if g>180 and r<70 and b<70)>100, 'inactive frame missing'
            command.write_text('close')
            trial.wait_for(lambda: not title('Shine policy dialog'))
            trial.wait_for(lambda: focus(parent['id']), description='dialog returns focus to parent')
            control('toggle-floating')
            assert title('Shine policy parent')['target_geometry'][3] < parent_geometry[3]
            floating_geometry=title('Shine policy parent')['target_geometry']
            control('maximize')
            assert title('Shine policy parent')['target_geometry'][3]>floating_geometry[3]
            control('maximize')
            assert title('Shine policy parent')['target_geometry']==floating_geometry
            control('toggle-floating')
            assert title('Shine policy parent')['target_geometry'] == parent_geometry
            command.write_text('hide')
            trial.wait_for(lambda: control()['keyboard_focus'] != parent['id'], description='unmapping releases focus')
            command.write_text('show')
            trial.wait_for(lambda: (window:=title('Shine policy parent')) and focus(window['id']), description='remapping receives focus')
            parent=title('Shine policy parent')
            command.write_text('dialog2')
            dialog=trial.wait_for(lambda:title('Shine policy dialog'))
            control('focus',parent['id'])
            control('move-workspace',3)
            assert control()['workspace']==3 and title('Shine policy dialog')['workspace']==3
            assert title('Shine policy dialog')['parent']==parent['id']
            previous_output=title('Shine policy parent')['output']
            control('move-output-next')
            assert title('Shine policy parent')['output']!=previous_output
            assert title('Shine policy dialog')['output']==title('Shine policy parent')['output']
            assert title('Shine policy dialog')['floating']
            command.write_text('close2')
            trial.wait_for(lambda: not title('Shine policy dialog'))
            trial.wait_for(lambda: focus(parent['id']))
            (artifacts / 'verification.json').write_text(json.dumps({'new_window_focus':True,'close_left':True,'move_follow':True,'launcher_reuse':True,'frames':True,'transient_dialogs_and_input':True,'unmap_remap':True}))
        finally:
            if process.poll() is None:
                control('quit')
                process.wait(timeout=10)
            assert {w['id']:w['pid'] for w in trial.parent_windows()} == original
    print('PASS: window focus, launcher reuse, frames, workspace following and floating dialog input')


if __name__ == '__main__':
    run()
