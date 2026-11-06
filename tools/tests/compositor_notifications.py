#!/usr/bin/env python3
"""Click real Mako notifications and verify exact GTK window activation."""
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
            mako_config = artifacts / 'mako.conf'
            mako_config.write_text('default-timeout=0\nwidth=300\nheight=120\nanchor=top-right\n'
                                   f'output={state["outputs"][0]["name"]}\n')
            launch(['mako', '--config', str(mako_config)], env)
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
                trial.wait_for(lambda: 'Notification activation trial' in subprocess.check_output(
                    ['makoctl', 'list'], env=env, text=True), description='Mako notification')
                time.sleep(.3)
                output = control()['outputs'][0]
                x, y = output['position']
                width = output['logical_size'][0]
                control('pointer', x=x + width - 120, y=y + 30)
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
            (artifacts / 'report.json').write_text(json.dumps({
                'exact_window_activated': True, 'background_present_rejected': True,
                'cross_workspace_and_output': True, 'replayed_and_expired_tokens_rejected': True,
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
