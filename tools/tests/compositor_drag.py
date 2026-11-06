#!/usr/bin/env python3
"""Regress pointer lock re-entry when a real Wayland drag clears focus."""
import json
from pathlib import Path
import shlex
import subprocess
import tempfile
import time

import compositor_support as trial


def run():
    trial.ensure_test_display()
    artifacts = Path(tempfile.mkdtemp(prefix='drag-', dir=trial.ROOT / '.local/compositor-tests'))
    print(f'Artifacts: {artifacts}', flush=True)
    flags = shlex.split(subprocess.check_output(['pkg-config', '--cflags', '--libs', 'gtk4'], text=True))
    client = artifacts / 'client'
    subprocess.run(['cc', '-Wall', '-Wextra', '-Werror',
                    str(Path(__file__).with_name('compositor_drag_client.c')),
                    '-o', str(client), *flags], check=True)
    config = artifacts / 'config.toml'
    config.write_text('[animations]\nenabled=false\n')
    control = trial.Control(artifacts / 'control.sock')
    result = artifacts / 'drag-state'
    with (artifacts / 'session.log').open('w') as log:
        process = subprocess.Popen([str(trial.BINARY), '--no-clients', '--test-input',
                                    '--config', str(config), '--control-socket', control.path,
                                    '--close-after', '60'], stdout=log, stderr=log)
        try:
            trial.wait_for(control)
            control('launch', program=str(client), args=[str(result)])
            window = trial.wait_for(lambda: (window := trial.window_for(control, 'org.ohmansy.DragProbe'))
                                   and window['surface_size'] and window)
            for _ in range(3):
                result.unlink(missing_ok=True)
                x, y, width, height = window['geometry']
                control('pointer', x=x + width / 2, y=y + height / 2)
                control('button', pressed=True)
                time.sleep(.1)
                control('pointer', x=x + width / 2 + 50, y=y + height / 2 + 30)
                trial.wait_for(lambda: result.exists() and result.read_text() == 'started',
                               description='real drag with icon starts')
                # StartDrag clears focus under the pointer lock. The old cursor
                # callback deadlocks before it can answer this status request.
                before = control()['rendered_frames']
                control('pointer', x=x + width / 2 + 80, y=y + height / 2 + 60)
                trial.wait_for(lambda: control()['rendered_frames'] > before,
                               description='frames continue during drag')
                control('button', pressed=False)
                trial.wait_for(lambda: result.read_text() == 'ended', description='drag ends')
            (artifacts / 'verification.json').write_text(json.dumps(
                {'drag_with_icon_repeated': 3, 'responsive_during_drag': True}, indent=2))
        except Exception:
            diagnostic = {'pid': process.pid}
            try:
                diagnostic['main_thread_wait'] = Path(f'/proc/{process.pid}/wchan').read_text().strip()
                diagnostic['status'] = control()
            except (OSError, ValueError, AssertionError) as error:
                diagnostic['status_error'] = str(error)
            (artifacts / 'failure.json').write_text(json.dumps(diagnostic, indent=2))
            raise
        finally:
            if process.poll() is None:
                try:
                    control('quit')
                    process.wait(timeout=5)
                except (OSError, ValueError, AssertionError, subprocess.TimeoutExpired):
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


if __name__ == '__main__':
    run()
