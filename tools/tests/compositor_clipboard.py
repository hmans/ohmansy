#!/usr/bin/env python3
"""Check clipboard translation, physical keys, Qt focus and live overrides."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

import compositor_support as trial


def run(profile='super-alt'):
    trial.ensure_test_display()
    base = trial.ROOT / '.local/compositor-tests'
    base.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='clipboard-', dir=base))
    print(f'Artifacts: {artifacts}', flush=True)
    original = {w['id']: w['pid'] for w in trial.parent_windows()}
    (artifacts / 'parent-before.json').write_text(json.dumps(original))
    previous_focus = next((w['id'] for w in trial.parent_windows() if w['is_focused']), None)
    config = artifacts / 'config.toml'
    config.write_text('[animations]\nenabled=false\n')
    control = trial.Control(artifacts / 'control.sock')
    modifier = ('super', 'alt') if profile == 'super-alt' else ('super',)
    clients = []

    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--test-input',
            '--mod-key', profile,
            '--config', str(config), '--control-socket', control.path, '--close-after', '120'],
            stdout=log, stderr=log)
        try:
            state = trial.wait_for(control, description='nested compositor')
            trial.wait_for(lambda: any(w['id'] not in original for w in trial.parent_windows()))
            if previous_focus is not None:
                trial.focus_parent_window(previous_focus)
            env = dict(os.environ, WAYLAND_DISPLAY=state['wayland_display'], QT_QPA_PLATFORM='wayland')
            env.pop('WAYLAND_SOCKET', None)

            def clipboard():
                return subprocess.check_output(['wl-paste', '--no-newline'], env=env,
                    stderr=subprocess.DEVNULL, timeout=5).decode()

            def publish(text):
                subprocess.run(['wl-copy'], input=text.encode(), env=env, check=True, timeout=5,
                               stderr=subprocess.DEVNULL)
                trial.wait_for(lambda: clipboard() == text, description='selection ownership')

            ready, received = artifacts / 'ready', artifacts / 'received'
            # A raw input sink, never a shell: pasted test text cannot execute.
            capture = artifacts / 'capture.py'
            capture.write_text('import os, pathlib, sys, tty\n'
                'tty.setraw(sys.stdin.fileno())\n'
                'print("terminal-marker", flush=True)\n'
                f'pathlib.Path({str(ready)!r}).touch()\n'
                f'with open({str(received)!r}, "wb", buffering=0) as output:\n'
                '    while True:\n'
                '        output.write(os.read(sys.stdin.fileno(), 4096))\n')
            control('launch', program='foot', args=['--app-id=foot',
                '--override=key-bindings.clipboard-paste=Control+Shift+v Control+Shift+Insert',
                sys.executable, str(capture)])
            terminal = trial.wait_for(lambda: trial.window_for(control, 'foot'))
            trial.wait_for(ready.exists)
            control('focus', terminal['id'])
            trial.wait_for(lambda: not trial.window_for(control, 'foot')['moving'])
            x, y, _, _ = trial.window_for(control, 'foot')['geometry']
            # Triple click selects the first complete line in Foot.
            control('pointer', x=x + 30, y=y + 15)
            for _ in range(3):
                control('button', pressed=True)
                control('button', pressed=False)
                time.sleep(.04)
            control.send_keys([46], modifier)
            trial.wait_for(lambda: clipboard().strip() == 'terminal-marker', description='terminal copy')
            assert received.read_bytes() == b'', 'Super+C sent an interrupt to the terminal'
            publish('paste-one')
            control.send_keys([47], modifier)
            trial.wait_for(lambda: received.read_bytes() == b'paste-one', description='terminal paste')
            control.send_keys([46], ('ctrl',))
            control.send_keys([35])  # Plain h must not retain synthetic modifiers.
            trial.wait_for(lambda: received.read_bytes() == b'paste-one\x03h', description='physical Ctrl+C and typing')

            # Change both incoming and outgoing mappings with the file watcher.
            config.write_text('''[clipboard]
terminal_app_ids = ["foot"]
terminal_paste = "Ctrl+Shift+Insert"
[bindings]
"Mod+V" = { action = "none" }
"Alt+Insert" = { action = "paste" }
''')
            trial.wait_for(lambda: control()['preferences']['clipboard']['terminal_paste'] == 'Ctrl+Shift+Insert',
                           description='live target reload')
            publish('paste-two')
            control.send_keys([47], modifier)
            baseline = received.read_bytes() # Unbound keys pass through to Foot.
            assert b'paste-two' not in baseline, 'Disabled binding still pasted'
            control.send_keys([110], ('alt',))
            trial.wait_for(lambda: received.read_bytes() == baseline + b'paste-two', description='remapped terminal paste')
            # A release remains consumed even when its binding disappears mid-chord.
            config.write_text('')
            trial.wait_for(lambda: control()['preferences']['clipboard']['terminal_paste'] == 'Ctrl+Shift+V')
            control('key', code=125, pressed=True)
            if 'alt' in modifier:
                control('key', code=56, pressed=True)
            control('key', code=47, pressed=True)
            trial.wait_for(lambda: received.read_bytes().endswith(b'paste-twopaste-two'))
            config.write_text('[bindings]\n"Mod+V"={action="none"}\n')
            trial.wait_for(lambda: 'Mod+V' in control()['preferences']['bindings'])
            control('key', code=47, pressed=False)
            if 'alt' in modifier:
                control('key', code=56, pressed=False)
            control('key', code=125, pressed=False)
            control.send_keys([35])
            trial.wait_for(lambda: received.read_bytes().endswith(b'paste-twoh'))
            assert not any(control()['modifiers'].values())
            config.write_text('')
            trial.wait_for(lambda: not control()['preferences']['bindings'])
            config.write_text('[clipboard]\npaste="Mod+V"\n')
            trial.wait_for(lambda: control()['config_error'], description='invalid clipboard target rejected')
            assert control()['preferences']['clipboard']['paste'] == 'Ctrl+V'
            config.write_text('')
            trial.wait_for(lambda: control()['config_error'] is None)

            # Qt TextEdit exercises its normal shortcuts with a real wl_keyboard.
            # Shine does not yet assign keyboard focus to layer-shell panels.
            qml = artifacts / 'qt.qml'
            qml.write_text('''import QtQuick
import Quickshell
ShellRoot {
    FloatingWindow {
        visible: true; implicitHeight: 150; implicitWidth: 500
        TextEdit {
            anchors.fill: parent; focus: true; text: "qt-marker"
            Component.onCompleted: { forceActiveFocus(); selectAll(); }
            onTextChanged: console.log("clipboard-text:" + JSON.stringify(text))
        }
    }
}
''')
            before = {w['id'] for w in control()['windows']}
            control('focus', terminal['id'])
            qt_log = artifacts / 'qt.log'
            with qt_log.open('w') as output:
                qt = subprocess.Popen(['qs', '--path', str(qml)], env=env, stdout=output, stderr=output)
                clients.append(qt)
                window = trial.wait_for(lambda: next((w for w in control()['windows'] if w['id'] not in before), None))
                control('focus', window['id'])
                publish('sentinel')
                control.send_keys([46], modifier)
                trial.wait_for(lambda: clipboard() == 'qt-marker', description='Qt copy')
                publish('qt-paste')
                control.send_keys([47], modifier)
                trial.wait_for(lambda: 'clipboard-text:"qt-paste"' in qt_log.read_text(), description='Qt paste')
                time.sleep(.8)
                assert qt_log.read_text().count('clipboard-text:"qt-paste"') == 1, 'Synthetic key repeated'
                baseline = received.read_bytes()
                held = [125, 56] if 'alt' in modifier else [125]
                for code in held:
                    control('key', code=code, pressed=True)
                control('key', code=47, pressed=True)
                control('focus', terminal['id'])
                control('key', code=47, pressed=False)
                for code in reversed(held):
                    control('key', code=code, pressed=False)
                control.send_keys([35])
                trial.wait_for(lambda: received.read_bytes() == baseline + b'h',
                               description='release after focus change and plain terminal typing')
                assert not any(control()['modifiers'].values())
                qt.terminate()
                qt.wait(timeout=10)
                clients.remove(qt)
            (artifacts / 'verification.json').write_text(json.dumps(control(), indent=2))
        finally:
            for client in clients:
                client.terminate()
                client.wait(timeout=10)
            if process.poll() is None:
                control('quit')
            process.wait(timeout=15)
            remaining = {w['id']: w['pid'] for w in trial.parent_windows()}
            (artifacts / 'parent-after.json').write_text(json.dumps(remaining))
            assert all(remaining.get(ident) == pid for ident, pid in original.items()), 'Parent desktop changed'
    assert process.returncode == 0
    print(f'PASS ({profile}): terminal copy/paste, Ctrl+C, live mappings, releases across reload and Qt; parent preserved')


if __name__ == '__main__':
    run(sys.argv[1] if len(sys.argv) > 1 else 'super-alt')
