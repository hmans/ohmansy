#!/usr/bin/env python3
"""Verify task startup, placement, named navigation and reload on private displays."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

import compositor_support as trial


def configuration(order=('dev', 'chat'), broken=False):
    text = '# My task workspaces\n'
    for task in order:
        text += f'\n[[workspaces]]\nid="{task}"\nname="{task.upper()}"\n'
        text += f'[[workspaces.apps]]\ncommand=["foot","--app-id=task-{task}","--title={task}","sleep","90"]\n'
        text += f'match={{app_id="task-{task}",title_contains="{task}"}}\n'
        if broken and task == 'dev':
            text += '[[workspaces.apps]]\ncommand=["/missing-ohmansy-test-app"]\nmatch={app_id="missing"}\n'
    return text


def run():
    trial.ensure_test_display()
    base = trial.ROOT / '.local/compositor-tests'
    base.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='tasks-', dir=base))
    print(f'Artifacts: {artifacts}', flush=True)
    config = artifacts / 'config.toml'
    compositor_settings = '[animations]\nenabled=false\n[bindings]\n"Mod+D"={action="task",id="dev"}\n'
    config.write_text(compositor_settings)
    workspaces = artifacts / 'workspaces.toml'
    workspaces.write_text(configuration(broken=True))
    subprocess.run([str(trial.BINARY), 'validate-workspaces', str(workspaces)], check=True)
    # Short control path: worktree artifact paths can exceed AF_UNIX's limit.
    control = trial.Control(Path(os.environ['XDG_RUNTIME_DIR']) / 'tasks.sock')
    original = {w['id']: w['pid'] for w in trial.parent_windows()}
    env = dict(os.environ, OHMANSY_COMPOSITOR_SESSION_SETUP=shutil.which('true'),
               OHMANSY_SHINE_QML=str(trial.ROOT / 'nix/modules/shine-shell/shell.qml'))
    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--session', '--test-input',
            '--config', str(config), '--control-socket', control.path,
            '--close-after', '90'], env=env, stdout=log, stderr=log)
        try:
            trial.wait_for(control)

            def window(app):
                return trial.window_for(control, f'task-{app}')

            trial.wait_for(lambda: window('dev') and window('chat'))
            trial.wait_for(lambda: window('dev')['workspace'] == 1 and window('chat')['workspace'] == 2)
            state = control()
            assert Path(state['task_config_path']) == workspaces
            assert state['task_config_error'] is None
            assert len(state['task_startup_errors']) == 1, state
            assert len(state['windows']) == 2, 'Configured tasks replace the default startup terminal'
            assert [w['id'] for w in state['workspaces']] == ['dev', 'chat']
            trial.wait_for(lambda: any(layer['namespace'] == 'ohmansy-shine-bar'
                for output in control()['outputs'] for layer in output['layers']), description='named workspace shell')
            # Allow the shell's status poll and first rendered buffers to arrive.
            time.sleep(1)
            control('screenshot', path=str(artifacts / 'tasks.png'))
            trial.wait_for(lambda: (artifacts / 'tasks.png').exists())
            dev, chat = window('dev')['id'], window('chat')['id']
            control('focus', dev)
            control('launch', program='foot', args=['--app-id=task-chat', '--title=chat', 'sleep', '90'])
            trial.wait_for(lambda: len(control()['windows']) == 3)
            trial.wait_for(lambda: all(w['workspace'] == 2 for w in control()['windows'] if w['app_id'] == 'task-chat'))
            newest=max(w['id'] for w in control()['windows'] if w['app_id']=='task-chat')
            trial.wait_for(lambda: control()['keyboard_focus']==newest, description='new task-routed window receives focus')
            assert control()['workspace']==2
            control('task', id='chat')
            assert control()['workspace'] == 2
            control.send_keys([32], ('super',))  # Mod+D targets the stable dev ID.
            assert control()['workspace'] == 1
            control('focus', chat)
            control('move-workspace', 1)
            ids = {w['id'] for w in control()['windows']}
            workspaces.write_text(configuration(('chat', 'dev')))
            trial.wait_for(lambda: control()['workspaces'][0]['id'] == 'chat')
            assert {w['id'] for w in control()['windows']} == ids, 'Reload launched duplicate apps'
            assert window('dev')['workspace'] == 2
            assert next(w for w in control()['windows'] if w['id'] == chat)['workspace'] == 2, 'Manual move was overwritten'
            before_save = workspaces.read_bytes()
            control('save-config')
            assert workspaces.read_bytes() == before_save, 'Display save modified the task file'
            assert '[[workspaces]]' not in config.read_text()
            expanded = configuration(('chat', 'dev')) + ''.join(
                f'\n[[workspaces]]\nid="extra-{n}"\nname="Extra {n}"\n' for n in range(4))
            workspaces.write_text(expanded)
            trial.wait_for(lambda: len(control()['workspaces']) == 6)
            control('workspace', 6)
            control('workspace-next')
            assert control()['workspace'] == 1
            control('task', id='dev')
            assert control()['workspace'] == 2
            workspaces.write_text(configuration(('dev',)))
            trial.wait_for(lambda: len(control()['workspaces']) == 1)
            assert {w['id'] for w in control()['windows']} == ids, 'Removing a task lost windows'
            assert all(w['workspace'] == 1 for w in control()['windows'])
            workspaces.write_text('[[workspaces]]\nid="broken"\nname=""\n')
            trial.wait_for(lambda: control()['task_config_error'])
            assert control()['workspaces'][0]['id'] == 'dev'
            assert control()['config_error'] is None
            # Invalid tasks must not block display/input preference reloads.
            config.write_text(compositor_settings + '[layout]\ngap=30\n')
            trial.wait_for(lambda: control()['preferences']['layout']['gap'] == 30)
            assert control()['task_config_error']
            assert control()['config_error'] is None
            # Invalid compositor settings must not block task reloads either.
            config.write_text('[layout]\ngap=-1\n')
            trial.wait_for(lambda: control()['config_error'])
            workspaces.write_text(configuration(('chat', 'dev')))
            trial.wait_for(lambda: control()['workspaces'][0]['id'] == 'chat')
            assert control()['task_config_error'] is None
            assert control()['config_error']
            # Explicit reload also handles both files even when one fails.
            workspaces.write_text(configuration(('dev',)))
            try:
                control('reload-config')
            except AssertionError:
                pass  # The compositor config remains invalid.
            assert control()['workspaces'][0]['id'] == 'dev'
            config.write_text(compositor_settings)
            trial.wait_for(lambda: control()['config_error'] is None)
            workspaces.unlink()
            trial.wait_for(lambda: len(control()['workspaces']) == 4)
            assert control()['task_config_error'] is None
            assert {w['id'] for w in control()['windows']} == ids
            workspaces.write_text(configuration(('dev',)))
            trial.wait_for(lambda: control()['workspaces'][0]['id'] == 'dev')
            assert {w['id'] for w in control()['windows']} == ids, 'Recreating tasks relaunched apps'
            control('quit')
            process.wait(timeout=10)
            assert process.returncode == 0
        finally:
            if process.poll() is None:
                control('quit')
                process.wait(timeout=10)
        override = artifacts / 'alternate-tasks.toml'
        override.write_text('[[workspaces]]\nid="override"\nname="Override"\n')
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--test-input',
            '--config', str(config), '--workspaces', str(override),
            '--control-socket', control.path, '--close-after', '30'],
            env=env, stdout=log, stderr=log)
        try:
            state = trial.wait_for(control)
            assert state['workspaces'] == [{'id': 'override', 'name': 'Override'}]
            assert Path(state['task_config_path']) == override
            control('quit')
            process.wait(timeout=10)
            assert process.returncode == 0
        finally:
            if process.poll() is None:
                control('quit')
                process.wait(timeout=10)
    remaining = {w['id']: w['pid'] for w in trial.parent_windows()}
    assert all(remaining.get(ident) == pid for ident, pid in original.items())
    log = (artifacts / 'session.log').read_text()
    assert 'ReferenceError' not in log and 'TypeError' not in log, log
    (artifacts / 'verification.json').write_text(json.dumps({'startup': True,
        'background_placement': True, 'named_navigation': True, 'shell': True,
        'reload_preserves_windows': True, 'invalid_config_recovery': True,
        'independent_config_files': True, 'missing_file_recovery': True,
        'explicit_workspaces_path': True}, indent=2))
    print('PASS: task startup, placement, focus, named shortcuts, shell, independent reloads, saves and file recovery')


if __name__ == '__main__':
    run()
