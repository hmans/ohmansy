#!/usr/bin/env python3
"""Test the shared notification shell and exact GTK window activation privately."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import time

import compositor_support as trial


def run():
    trial.ensure_test_display()
    artifacts = Path(tempfile.mkdtemp(prefix='notifications-', dir=trial.ROOT / '.local/compositor-tests'))
    print(f'Artifacts: {artifacts}', flush=True)
    fixture = artifacts / 'notification-client'
    flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', '--libs', 'gtk4'], text=True))
    subprocess.run(['cc', '-Wall', '-Wextra', '-Werror',
                    str(Path(__file__).with_name('compositor_notification_client.c')),
                    '-o', str(fixture), *flags], check=True)
    control = trial.Control(Path(os.environ['XDG_RUNTIME_DIR']) / 'notifications.sock')
    processes = []
    config = artifacts / 'config.toml'
    config.write_text('[animations]\nenabled=false\n')
    with (artifacts / 'session.log').open('w') as log:
        def launch(args, env=None):
            process = subprocess.Popen(args, env=env, stdout=log, stderr=log)
            processes.append(process)
            return process

        try:
            launch([str(trial.BINARY), '--no-clients', '--test-input', '--outputs', '2',
                    '--config', str(config), '--control-socket', control.path])
            state = trial.wait_for(control)
            env = dict(os.environ, WAYLAND_DISPLAY=state['wayland_display'], GDK_BACKEND='wayland')
            env.pop('WAYLAND_SOCKET', None)
            package = subprocess.check_output(['nix', 'build', '--no-update-lock-file',
                '--no-link', '--print-out-paths', '.#desktop-shell'], cwd=trial.ROOT, text=True).strip()
            wrapper = str(Path(package) / 'bin/ohmansy-quickshell')
            qml = artifacts / 'shell.qml'
            qml.write_text(Path(__file__).with_name('notification_shell.qml').read_text())
            shell = launch([wrapper, '--path', str(qml)], env)

            def ipc(method, *args):
                return subprocess.check_output([wrapper, 'ipc', '--pid', str(shell.pid),
                    'call', 'notifications', method, *map(str, args)], env=env, text=True)

            def status():
                try:
                    return json.loads(ipc('status'))
                except subprocess.CalledProcessError:
                    return None

            trial.wait_for(lambda: shell.poll() is None and status(), description='notification shell')
            command = artifacts / 'command'
            launch([str(fixture), str(command)], env)

            def window(title):
                return next((w for w in control()['windows'] if w['title'] == title), None)

            origin = trial.wait_for(lambda: window('Notification origin'))
            sibling = trial.wait_for(lambda: window('Other window from the same app'))
            control('focus', origin['id'])
            control('move-output-next')
            control('move-workspace', 2)
            control('focus', sibling['id'])
            destination = window('Notification origin')

            # Presenting from the background without input must not steal focus.
            command.write_text('present')
            trial.wait_for(lambda: not command.exists())
            time.sleep(.5)
            assert window(sibling['title'])['focused'], 'Background presentation stole focus'

            ack = Path(str(command) + '.action')

            def click_notification(deferred=False):
                ack.unlink(missing_ok=True)
                command.write_text('notify-deferred' if deferred else 'notify')
                trial.wait_for(lambda: not command.exists())
                trial.wait_for(lambda: any(n['summary'] == 'Notification activation trial'
                    for n in status()['active']), description='Quickshell notification')
                time.sleep(.3)
                output = control()['outputs'][0]
                x, y = output['position']
                width = output['logical_size'][0]
                control('pointer', x=x + width - 120, y=y + 70)
                control('button', pressed=True)
                control('button', pressed=False)
                trial.wait_for(ack.exists, description='notification action')

            # Click the real notification through normal pointer input.
            click_notification()
            activated = trial.wait_for(lambda: window('Notification origin')['focused'],
                                       description='notification activation across outputs/workspaces')
            assert activated
            current = window('Notification origin')
            assert current['output'] == destination['output']
            assert current['workspace'] == destination['workspace'] == 2
            assert not window(sibling['title'])['focused']
            assert control()['keyboard_focus'] == origin['id']

            # The same token cannot bring the origin back a second time.
            control('focus', sibling['id'])
            command.write_text('activate')
            trial.wait_for(lambda: not command.exists())
            time.sleep(.3)
            assert window(sibling['title'])['focused'], 'Replayed token changed focus'

            # Even an unused token loses permission after ten seconds.
            click_notification(deferred=True)
            assert window(sibling['title'])['focused']
            time.sleep(10.2)
            command.write_text('activate')
            trial.wait_for(lambda: not command.exists())
            time.sleep(.3)
            assert window(sibling['title'])['focused'], 'Expired token changed focus'
            # Dismiss must not bubble into the default action. Check protocol reasons.
            closed = Path(str(command) + '.closed')
            closed.unlink(missing_ok=True)
            ack.unlink(missing_ok=True)
            command.write_text('notify')
            trial.wait_for(lambda: not command.exists())
            trial.wait_for(lambda: status()['active'])
            time.sleep(.2)
            control('screenshot', path=str(artifacts / 'popup.png'))
            output = control()['outputs'][0]
            x, y = output['position']
            control('pointer', x=x + output['logical_size'][0] - 56, y=y + 60)
            control('button', pressed=True)
            control('button', pressed=False)
            trial.wait_for(closed.exists)
            assert closed.read_text() == '2', 'Dismiss must report reason 2'
            assert not ack.exists(), 'Dismiss also invoked the default action'
            control('pointer', x=10, y=400)
            closed.unlink()
            command.write_text('notify-expire')
            trial.wait_for(closed.exists)
            assert closed.read_text() == '1', 'Expiry must report reason 1'
            def notify(summary, body='Body', replaces=0, timeout=0, hints=()):
                reply = subprocess.check_output(['busctl', '--user', 'call',
                    'org.freedesktop.Notifications', '/org/freedesktop/Notifications',
                    'org.freedesktop.Notifications', 'Notify', 'susssasa{sv}i',
                    'Notification test', str(replaces), '', summary, body, '0',
                    str(len(hints)), *[part for hint in hints for part in hint], str(timeout)],
                    env=env, text=True)
                return int(reply.split()[1])

            replacement = notify('Original')
            assert notify('Replaced', '<b>Updated</b>', replaces=replacement) == replacement
            trial.wait_for(lambda: any(n['summary'] == 'Replaced' for n in status()['active']))
            saved = status()['history']
            assert not any(n['summary'] == 'Original' for n in saved)
            assert next(n for n in saved if n['summary'] == 'Replaced')['body'] == 'Updated'
            notify('Transient', hints=[('transient', 'b', 'true')])
            time.sleep(.2)
            assert not any(n['summary'] == 'Transient' for n in status()['history'])
            control('pointer', x=10, y=400)
            expired = notify('Short expiry', timeout=150)
            trial.wait_for(lambda: all(n['id'] != expired for n in status()['active']))
            assert any(n['summary'] == 'Short expiry' for n in status()['history'])
            hover_id = notify('Hover expiry', timeout=400)
            output = control()['outputs'][0]
            x, y = output['position']
            control('pointer', x=x + output['logical_size'][0] - 120, y=y + 70)
            time.sleep(.6)
            assert any(n['id'] == hover_id for n in status()['active']), 'Hover did not pause expiry'
            control('pointer', x=10, y=400)
            trial.wait_for(lambda: all(n['id'] != hover_id for n in status()['active']))
            ipc('setDoNotDisturb', 'true')
            notify('Quiet notification')
            trial.wait_for(lambda: any(n['summary'] == 'Quiet notification' for n in status()['history']))
            assert status()['doNotDisturb']
            assert status()['popups'] == []
            ipc('setDoNotDisturb', 'false')
            ipc('toggleHistory')
            time.sleep(.3)
            control('screenshot', path=str(artifacts / 'history.png'))
            ipc('closeHistory')
            # QML reload carries active notifications and reads durable history.
            qml.write_text(qml.read_text() + '\n')
            time.sleep(.5)
            trial.wait_for(lambda: any(n['summary'] == 'Replaced' for n in status()['history']))
            assert not status()['storageError']
            assert window(sibling['title'])['focused'], 'Notification lifecycle stole focus'
            shell.terminate()
            shell.wait(timeout=5)
            shell = launch([wrapper, '--path', str(qml)], env)
            trial.wait_for(lambda: status() and any(n['summary'] == 'Replaced' for n in status()['history']),
                           description='history after a process restart')
            ipc('clear')
            assert status()['history'] == []
            imported = dict(entries=[dict(summary=f'Imported {i}', urgency='normal') for i in range(105)])
            assert int(ipc('importHistory', json.dumps(imported))) == 100
            assert len(status()['history']) == 100
            (artifacts / 'report.json').write_text(json.dumps({
                'exact_window_activated': True, 'background_present_rejected': True,
                'cross_workspace_and_output': True, 'replayed_and_expired_tokens_rejected': True,
                'replacement_expiry_transient_dnd_history_restart': True,
            }, indent=2))
            print('Notification activation trial passed', flush=True)
        finally:
            for process in reversed(processes):
                process.terminate()
            for process in reversed(processes):
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == '__main__':
    run()
