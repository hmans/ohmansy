#!/usr/bin/env python3
"""Measure offscreen animation throttling and real monitor preview rollback."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

import compositor_support as trial


def run():
    trial.ensure_test_display()
    base = trial.ROOT / '.local/compositor-tests'
    base.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='performance-', dir=base))
    print(f'Artifacts: {artifacts}', flush=True)
    config = artifacts / 'config.toml'
    config.write_text('# Preserve this comment.\n[layout]\ndefault_column_width={pixels=900}\n[animations]\nenabled=false\n')
    fixture = artifacts / 'animation.qml'
    fixture.write_text('''import QtQuick
import Quickshell
ShellRoot {
    FloatingWindow {
        visible: true
        title: "Shine animation fixture"
        implicitWidth: 900
        implicitHeight: 600
        Rectangle {
            anchors.fill: parent
            SequentialAnimation on color {
                loops: Animation.Infinite
                ColorAnimation { from: "#204060"; to: "#608020"; duration: 1000 }
                ColorAnimation { from: "#608020"; to: "#204060"; duration: 1000 }
            }
        }
    }
}''')
    control = trial.Control(artifacts / 'control.sock')
    original = {w['id']: w['pid'] for w in trial.parent_windows()}
    samples = {}

    def sample(label):
        time.sleep(.4)
        before = control()
        time.sleep(1)
        after = control()
        samples[label] = {key: after[key] - before[key] for key in ('surface_commits', 'rendered_frames')}
        return samples[label]['surface_commits']

    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--test-input', '--scale', '1',
            '--config', str(config), '--control-socket', control.path, '--close-after', '90'], stdout=log, stderr=log)
        animation = None
        try:
            state = trial.wait_for(control)
            env = dict(os.environ, WAYLAND_DISPLAY=state['wayland_display'],
                       OHMANSY_COMPOSITOR_CONTROL=control.path)
            env.pop('WAYLAND_SOCKET', None)
            animation = subprocess.Popen(['quickshell', '--path', str(fixture)], env=env, stdout=log, stderr=log)
            window = trial.wait_for(lambda: next((w for w in control()['windows']
                if w['title'] == 'Shine animation fixture' and w['surface_size']), None))
            assert sample('visible') > 10, samples
            for index in range(4):
                app = f'shine-performance-{index}'
                control('launch', program='foot', args=['--config=/dev/null', f'--app-id={app}',
                    sys.executable, '-c', 'import sys,time; print("\\x1b[?25l",end="",flush=True); time.sleep(80)'])
                trial.wait_for(lambda: (w if (w := trial.window_for(control, app)) and w['surface_size'] else None))
            state = control()
            hidden = next(w for w in state['windows'] if w['id'] == window['id'])
            assert hidden['geometry'][0] + hidden['geometry'][2] <= 0, hidden
            assert sample('offscreen') <= 4, samples
            control('focus', window['id'])
            assert sample('visible_again') > 10, samples
            control('workspace', 2)
            assert sample('inactive_workspace') <= 4, samples
            control('workspace', 1)
            assert sample('workspace_return') > 10, samples

            helper = trial.ROOT / 'nix/modules/desktop/shine-displays.py'
            output = control()['outputs'][0]
            mode = output['mode']
            mode_name = f'{mode["width"]}x{mode["height"]}@{mode["refresh"] / 1000:.3f}'
            def preview(decision):
                result = subprocess.run([sys.executable, str(helper), 'preview', output['name'], '1.5', mode_name],
                    input=decision, text=True, capture_output=True, env=env, timeout=20)
                assert result.returncode == 0, result.stdout + result.stderr
                return [json.loads(line)['status'] for line in result.stdout.splitlines()]
            assert preview('revert\n') == ['preview', 'reverted']
            assert control()['outputs'][0]['scale'] == 1
            assert preview('') == ['preview', 'reverted'], 'Closing settings must revert'
            assert control()['outputs'][0]['scale'] == 1
            assert preview('keep\n') == ['preview', 'kept']
            assert control()['outputs'][0]['scale'] == 1.5
            assert '# Preserve this comment.' in config.read_text()
            assert 'scale = 1.5' in config.read_text()
            (artifacts / 'samples.json').write_text(json.dumps(samples, indent=2))
        finally:
            if animation:
                animation.terminate()
                animation.wait(timeout=10)
            try:
                control('quit')
            finally:
                process.wait(timeout=10)
    assert {w['id']: w['pid'] for w in trial.parent_windows()} == original
    print('PASS: offscreen/workspace throttling, animation resumption, display preview/revert/EOF/keep; parent preserved')


if __name__ == '__main__':
    run()
