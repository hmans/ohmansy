#!/usr/bin/env python3
"""Verify real Wayland keyboard forwarding between owned parent/child instances."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

import compositor_support as trial


def run():
    trial.ensure_test_display()
    base = trial.ROOT / '.local/compositor-tests'
    base.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='nesting-', dir=base))
    print(f'Artifacts: {artifacts}', flush=True)
    original = {window['id']: window['pid'] for window in trial.parent_windows()}
    focus = next((window['id'] for window in trial.parent_windows() if window['is_focused']), None)
    parent, child = [trial.Control(artifacts / name) for name in ['parent.sock', 'child.sock']]
    if 'eurkey' in sys.argv[1:]:
        (artifacts / 'parent-config.toml').write_text('[input.keyboard]\nlayout="eu"\noptions="lv3:lalt_switch"\n')
    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([os.environ.get('SHINE_NESTING_PARENT_BINARY', str(trial.BINARY)), '--no-clients', '--test-input',
            '--config', str(artifacts / 'parent-config.toml'),
            '--mod-key', 'super', '--control-socket', parent.path, '--close-after', '60'], stdout=log, stderr=log)
        try:
            trial.wait_for(parent, description='parent socket')
            trial.wait_for(lambda: any(window['id'] not in original and window['app_id'] == 'ohmansy-compositor'
                                      for window in trial.parent_windows()), description='parent window')
            if focus is not None:
                trial.focus_parent_window(focus)
            child_profile = 'ctrl-alt' if 'ctrl-alt' in sys.argv[1:] else 'super-alt'
            child_modifiers = ('ctrl', 'alt') if child_profile == 'ctrl-alt' else ('super', 'alt')
            parent('launch', program=str(trial.BINARY), args=['--no-clients', '--mod-key', child_profile,
                '--config', str(artifacts / 'child-config.toml'),
                '--control-socket', child.path, '--close-after', '50'])
            trial.wait_for(child, description='child socket')
            nested = trial.wait_for(lambda: trial.window_for(parent, 'ohmansy-compositor'), description='nested surface')
            child('terminal')
            trial.wait_for(lambda: len(child()['windows']) == 1, description='child terminal')
            parent('focus', nested['id'])
            parent.send_keys([28], child_modifiers)
            trial.wait_for(lambda: len(child()['windows']) == 2, description='Super+Alt+Enter forwarded to child')
            assert len(parent()['windows']) == 1, 'Host consumed child shortcut'
            parent.send_keys([13], child_modifiers)
            trial.wait_for(lambda: child()['display_scale'] == 1.3, description='child scale shortcut')
            assert parent()['display_scale'] == 1.25
            parent.send_keys([13], ('super',))
            trial.wait_for(lambda: parent()['display_scale'] == 1.3, description='host scale shortcut')
            assert child()['display_scale'] == 1.3, 'Host shortcut reached child'
            parent.send_keys([28], ('super',))
            trial.wait_for(lambda: len(parent()['windows']) == 2, description='Super+Enter opens host terminal')
            assert len(child()['windows']) == 2
            for control in [parent, child]:
                trial.wait_for(lambda: not any(control()['modifiers'].values()), description='released modifiers after focus change')
            parent('focus', nested['id'])
            parent.send_keys([13], child_modifiers)
            trial.wait_for(lambda: child()['display_scale'] == 1.35, description='child shortcut after regaining focus')
            if child_profile == 'ctrl-alt':
                selected = child()['focused']
                width = next(w['width'] for w in child()['windows'] if w['id'] == selected)
                parent.send_keys([13], (*child_modifiers, 'shift'))
                trial.wait_for(lambda: next(w['width'] for w in child()['windows'] if w['id'] == selected) == width + 80,
                               description='Control+Option+Shift resize reaches child')
                assert parent()['display_scale'] == 1.3
            (artifacts / 'verification.json').write_text(json.dumps({'parent': parent(), 'child': child()}, indent=2)+'\n')
        finally:
            for control in [child, parent]:
                try:
                    control('quit')
                except (OSError, ValueError, AssertionError):
                    pass
            process.wait(timeout=65)
            remaining = {window['id']: window['pid'] for window in trial.parent_windows()}
            assert all(remaining.get(ident) == pid for ident, pid in original.items()), 'Original host windows changed'
        assert process.returncode == 0
    print(f'PASS: Super controls host; {child_profile} reaches child through real Wayland input; original desktop preserved')


if __name__ == '__main__':
    run()
