#!/usr/bin/env python3
"""Exercise the full configuration with disposable Wayland clients."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import compositor_integration as trial


def configuration(layout='us', gap=24, pixels=480, rule=720, resize=False):
    binding = 'action="resize", value=80' if resize else 'action="fullscreen"'
    return f'''# My desktop
[input.keyboard]
layout = "{layout}"
[input.touchpad]
tap = true
natural_scroll = true
[layout]
gap = {gap} # My padding
default_column_width = {{ pixels = {pixels} }}
[animations]
enabled = false
duration_ms = 120
[bindings]
"Mod+Return" = {{ {binding} }}
"Mod+F" = {{ action = "none" }}
"Mod+G" = {{ action = "workspace", value = 2 }}
"Mod+N" = {{ action = "launch", program = "foot", args = ["--app-id=shine-pref-launch", "sleep", "90"] }}
[[window_rules]]
match = {{ app_id = "shine-pref-launch" }}
default_column_width = {{ pixels = 600 }}
[[window_rules]]
match = {{ app_id = "shine-pref-launch" }}
default_column_width = {{ pixels = {rule} }}
[[outputs]]
name = 'SHINE-1' # Connector note
scale = 1.25 # Presentation scale
'''


def run():
    root = trial.ROOT / '.local/compositor-tests'
    root.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='preferences-', dir=root))
    print(f'Artifacts: {artifacts}', flush=True)
    config = artifacts / 'config.toml'
    config.write_text(configuration())
    subprocess.run([str(trial.BINARY), 'validate', str(config)], check=True)
    control = trial.Control(artifacts / 'control.sock')
    trial.TEST_CONTROL = control
    original = {w['id']: w['pid'] for w in trial.parent_windows()}
    modifier = ('super', 'alt')

    def window(ident):
        return next(w for w in control()['windows'] if w['id'] == ident)

    def capture_character(label):
        ready, result = artifacts / f'{label}-ready', artifacts / f'{label}-character'
        code = ("import pathlib,sys,tty; tty.setraw(sys.stdin.fileno()); "
                f"pathlib.Path({str(ready)!r}).touch(); "
                f"pathlib.Path({str(result)!r}).write_text(sys.stdin.read(1))")
        control('launch', program='foot', args=['--app-id=shine-pref-capture', sys.executable, '-c', code])
        trial.wait_for(ready.exists, description=f'{label} capture client')
        trial.send_keys([21])  # Physical US Y key; data, never terminal command text.
        trial.wait_for(result.exists, description=f'{label} keyboard character')
        trial.wait_for(lambda: not trial.window_for(control, 'shine-pref-capture'))
        return result.read_text()

    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--test-input',
            '--config', str(config), '--control-socket', control.path, '--close-after', '120'],
            stdout=log, stderr=log)
        try:
            trial.wait_for(control, description='configured compositor')
            control('launch', program='foot', args=['--app-id=shine-pref-default', 'sleep', '90'])
            ordinary = trial.wait_for(lambda: trial.window_for(control, 'shine-pref-default'))
            assert ordinary['width'] == 480, ordinary
            assert ordinary['geometry'][0:2] == [24, 24], ordinary
            trial.send_keys([49], modifier)  # Mod+N launches argv directly.
            ruled = trial.wait_for(lambda: trial.window_for(control, 'shine-pref-launch'))
            trial.wait_for(lambda: window(ruled['id'])['width'] == 720, description='last matching app rule')
            trial.send_keys([28], modifier)
            assert control()['fullscreen'] == ruled['id']
            trial.send_keys([33], modifier)  # Disabled Mod+F must not change fullscreen.
            assert control()['fullscreen'] == ruled['id']
            trial.send_keys([28], modifier)
            trial.send_keys([34], modifier)
            assert control()['workspace'] == 2
            trial.send_keys([2], modifier)
            assert control()['workspace'] == 1
            control('resize', 80)
            assert window(ruled['id'])['width'] == 800
            assert capture_character('us') == 'y'

            config.write_text(configuration(layout='de', gap=32, pixels=500, rule=900, resize=True))
            trial.wait_for(lambda: control()['preferences']['input']['keyboard']['layout'] == 'de', description='live keyboard/layout reload')
            assert window(ruled['id'])['width'] == 800, 'Reload must preserve a manually resized column'
            assert window(ordinary['id'])['width'] == 480
            assert capture_character('de') == 'z'
            control('focus', ruled['id'])
            trial.send_keys([28], modifier)
            assert window(ruled['id'])['width'] == 880, 'Reloaded custom action must replace the old binding'
            assert control()['fullscreen'] is None
            trial.send_keys([49], modifier)
            trial.wait_for(lambda: any(w['app_id'] == 'shine-pref-launch' and w['width'] == 900 for w in control()['windows']), description='new rule after reload')
            control('launch', program='foot', args=['--app-id=shine-pref-new-default', 'sleep', '90'])
            new = trial.wait_for(lambda: trial.window_for(control, 'shine-pref-new-default'))
            assert new['width'] == 500
            trial.wait_for(lambda: control()['viewport'] == control()['viewport_target'], description='disabled animation snapping')
            identities = {w['id'] for w in control()['windows']}
            control('scale', 150)
            control('save-config')
            saved = config.read_text()
            for comment in ['# My desktop', '# My padding', '# Connector note', '# Presentation scale']:
                assert comment in saved, saved
            assert "name = 'SHINE-1'" in saved, saved
            assert '[bindings]' in saved and 'shine-pref-launch' in saved
            subprocess.run([str(trial.BINARY), 'validate', str(config)], check=True)
            config.write_text(saved.replace('layout = "de"', 'layout = "shine-invalid-layout"'))
            trial.wait_for(lambda: control()['config_error'], description='bad keymap rejection')
            assert control()['preferences']['input']['keyboard']['layout'] == 'de'
            assert {w['id'] for w in control()['windows']} == identities
            config.write_text(saved)
            trial.wait_for(lambda: control()['config_error'] is None)
            (artifacts / 'verification.json').write_text(json.dumps(control(), indent=2))
            control('quit')
            assert process.wait(timeout=10) == 0
        finally:
            if process.poll() is None:
                control('quit')
                process.wait(timeout=10)
    remaining = {w['id']: w['pid'] for w in trial.parent_windows()}
    assert all(remaining.get(ident) == pid for ident, pid in original.items())
    print('PASS: real custom bindings, disabled defaults, app rules, persistent manual widths, US/German keymap reload, gap/default width updates, snapping, comment-preserving save and invalid-keymap recovery; parent preserved')


if __name__ == '__main__':
    run()
