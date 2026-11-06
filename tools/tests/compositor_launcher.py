#!/usr/bin/env python3
"""Exercise launcher search, activation and focus on the private display."""
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import time

import compositor_support as trial


def run():
    trial.ensure_test_display()
    artifacts = Path(tempfile.mkdtemp(prefix='launcher-', dir=trial.ROOT / '.local/compositor-tests'))
    control = trial.Control(os.environ['OHMANSY_COMPOSITOR_CONTROL'])
    environment = dict(os.environ)
    data = artifacts / 'data/applications'
    data.mkdir(parents=True)
    marker = artifacts / 'activated'
    app = artifacts / 'test-app'
    app.write_text(f'#!/bin/sh\ntouch "{marker}"\nexec foot --app-id=launcher-test-app sleep 60\n')
    app.chmod(0o755)
    (data / 'ohmansy-launcher-test.desktop').write_text(
        '[Desktop Entry]\nType=Application\nName=Launcher Test Application\n'
        f'Exec={app}\nIcon=utilities-terminal\nKeywords=probe;\n')
    (data / 'ohmansy-launcher-broken.desktop').write_text(
        '[Desktop Entry]\nType=Application\nName=zzbrokenlaunchertest\n'
        'Exec=/nonexistent/ohmansy-launcher-test\n')
    environment['XDG_DATA_HOME'] = str(data.parent)
    # Exercise the real nested-session helper on this private activation bus.
    wrapper = Path(os.environ['OHMANSY_COMPOSITOR_SHELL']).read_text()
    environment['OHMANSY_COMPOSITOR_SESSION_KIND'] = 'nested'
    shell = None
    with (artifacts / 'shell.log').open('w') as log:
        shell = subprocess.Popen([os.environ['OHMANSY_COMPOSITOR_SHELL']], env=environment, stdout=log, stderr=log)
        def ipc(method):
            return subprocess.check_output(['quickshell', 'ipc', '--pid', str(shell.pid),
                'call', 'launcher', method], env=environment, text=True, stderr=subprocess.DEVNULL)
        def status():
            try:
                return json.loads(ipc('status'))
            except subprocess.CalledProcessError as error:
                raise AssertionError('Launcher IPC is not ready') from error
        def type_codes(codes):
            control.send_keys(codes)
            time.sleep(.15)
        try:
            trial.wait_for(lambda: status() == {'opened': False}, description='launcher IPC ready')
            control('launch', program='foot', args=['--app-id=launcher-focus-test', 'sleep', '90'])
            original = trial.wait_for(lambda: trial.window_for(control, 'launcher-focus-test'))
            focused = original['id']
            ipc('toggle')
            trial.wait_for(lambda: status()['opened'], description='launcher open')
            time.sleep(.5)  # Wait for the layer's configure/map and exclusive focus.
            # "lta" is a discontinuous abbreviation of our fixture's name.
            type_codes([38, 20, 30])
            assert status()['results'][0]['id'] == 'app:ohmansy-launcher-test', status()
            control('screenshot', path=str(artifacts / 'search.png'))
            type_codes([108])
            assert status()['selected'] == status()['results'][1]['id'], status()
            type_codes([103])
            type_codes([28])
            trial.wait_for(marker.exists, description='GIO desktop activation')
            trial.wait_for(lambda: trial.window_for(control, 'launcher-test-app'), description='launched app')
            assert not status()['opened']
            # Dismissal must return keyboard focus and leave app identities alone.
            control('focus', focused)
            before = {w['id'] for w in control()['windows']}
            for _ in range(3):
                ipc('toggle')
                trial.wait_for(lambda: status()['opened'])
                type_codes([1])
                trial.wait_for(lambda: not status()['opened'])
                trial.wait_for(lambda: control()['keyboard_focus'] == focused, description='focus restored')
            assert before == {w['id'] for w in control()['windows']}
            ipc('toggle')
            # Exact title must outrank incidental keywords: "displays".
            type_codes([32, 23, 31, 25, 38, 30, 21, 31])
            assert status()['selected'] == 'desktop:displays', status()
            type_codes([28])
            display = trial.wait_for(lambda: next((w for w in control()['windows']
                if w['title'] == 'ohmansy displays'), None), description='desktop command')
            control('focus', display['id'])
            control('close')
            appearance = re.search(r'export OHMANSY_APPEARANCE=(\S+)', wrapper).group(1)
            for codes, preference in [([32, 30, 19, 37], 'prefer-dark'),
                                      ([38, 23, 34, 35, 20], 'prefer-light')]:
                ipc('toggle')
                type_codes(codes)
                type_codes([28])
                trial.wait_for(lambda: preference in subprocess.check_output(
                    [appearance, 'read'], env=environment, text=True), description='appearance command')
            ipc('toggle')
            type_codes([44, 44, 48, 19, 24, 37, 18, 49])
            assert status()['selected'] == 'app:ohmansy-launcher-broken', status()
            type_codes([28])
            time.sleep(.5)
            assert not status()['opened'], 'A failed request must not steal focus by reopening'
            ipc('toggle')
            assert status()['error'], 'Report activation failures on the next open'
            type_codes([1])
            ipc('toggle')
            type_codes([44] * 20)
            assert status()['results'] == [], status()
            type_codes([28])
            assert status()['opened'], 'Enter on an empty list must be harmless'
            control('pointer', x=2, y=2)
            control('button', pressed=True)
            control('button', pressed=False)
            trial.wait_for(lambda: not status()['opened'], description='outside click dismisses')
            assert shell.poll() is None
        finally:
            shell.terminate()
            shell.wait(timeout=10)
    log_text = (artifacts / 'shell.log').read_text()
    assert not any(word in log_text for word in ('ReferenceError', 'TypeError', 'failed to load', 'Binding loop', 'Unable to assign')), log_text
    print(f'PASS: fuzzy search, ranking, selection, GIO activation, commands, empty results, dismissal and focus. Artifacts: {artifacts}')


if __name__ == '__main__':
    run()
