#!/usr/bin/env python3
"""Run graphical tests on a private headless Wayland display and D-Bus session."""
import argparse
from contextlib import contextmanager, ExitStack
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/tests'))
from compositor_support import BINARY, Control  # noqa: E402


def stop(process, timeout=5):
    """Clean up only this runner's process groups, including leftover clients."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    deadline = time.monotonic() + timeout
    while True:
        process.poll()  # Reap the leader; descendants can outlive it.
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            break
        if time.monotonic() >= deadline:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            break
        time.sleep(.05)
    process.wait(timeout=5)


@contextmanager
def process_group(command, **kwargs):
    process = subprocess.Popen(command, start_new_session=True, **kwargs)
    try:
        yield process
    finally:
        stop(process)


def quit_parent(process, control):
    if process.poll() is None:
        try:
            control('quit')
            process.wait(timeout=5)
        except (OSError, ValueError, AssertionError, subprocess.TimeoutExpired):
            pass  # The process-group cleanup still runs.


def wait_ready(process, probe, label):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f'{label} exited with {process.returncode}; inspect the headless logs')
        try:
            if result := probe():
                return result
        except (OSError, ValueError, AssertionError):
            pass
        time.sleep(.1)
    raise RuntimeError(f'{label} did not become ready; inspect the headless logs')


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--visible', action='store_true', help='Explicitly run on the current desktop')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ['--']:
        command = command[1:]
    if not command:
        parser.error('Provide a test command after --')
    if command[0].endswith('.py'):
        command.insert(0, sys.executable)
    if args.visible:
        os.environ['OHMANSY_TEST_DISPLAY'] = 'visible'
        os.execvpe(command[0], command, os.environ)
    if os.environ.get('OHMANSY_SPATIAL_SHELL') != '1':
        os.chdir(ROOT)
        os.execvp('nix', ['nix', 'develop', '--no-update-lock-file', '.#spatial', '--command',
            'env', 'OHMANSY_SPATIAL_SHELL=1', sys.executable, str(Path(__file__).resolve()), '--', *command])
    if not BINARY.is_file():
        raise RuntimeError('Run mise run compositor-integration to build the development compositor')
    base = ROOT / '.local/compositor-tests'
    base.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix='headless-', dir=base))
    print(f'Headless display logs: {artifacts}', flush=True)
    # A short runtime path also keeps Wayland and control sockets below UNIX's
    # path limit. No socket from the real desktop is available in this directory.
    with tempfile.TemporaryDirectory(prefix='ohmansy-test-') as runtime, ExitStack() as stack:
        env = dict(os.environ)
        # Used only by the packaged-session trial's read-only manager assertion.
        env['OHMANSY_TEST_HOST_RUNTIME'] = env.get('XDG_RUNTIME_DIR', '')
        env['OHMANSY_TEST_HOST_DBUS'] = env.get('DBUS_SESSION_BUS_ADDRESS') or (
            f'unix:path={env["XDG_RUNTIME_DIR"]}/bus' if env.get('XDG_RUNTIME_DIR') else '')
        for key in ('DISPLAY', 'WAYLAND_DISPLAY', 'WAYLAND_SOCKET', 'NIRI_SOCKET',
                    'SWAYSOCK', 'OHMANSY_COMPOSITOR_CONTROL', 'XAUTHORITY'):
            env.pop(key, None)
        env.update(XDG_RUNTIME_DIR=runtime, XDG_SESSION_TYPE='wayland',
                   XDG_CURRENT_DESKTOP='ohmansy-test', OHMANSY_TEST_DISPLAY='headless',
                   GTK_USE_PORTAL='0', QT_QPA_PLATFORM='wayland',
                   DBUS_SESSION_BUS_ADDRESS=f'unix:path={runtime}/bus')
        for kind in ('CONFIG', 'DATA', 'STATE', 'CACHE'):
            path = artifacts / kind.lower()
            path.mkdir()
            env[f'XDG_{kind}_HOME'] = str(path)
        def launch(command, log_name=None):
            output = stack.enter_context((artifacts / log_name).open('w')) if log_name else None
            return stack.enter_context(process_group(command, env=env, stdout=output, stderr=output))

        weston = launch(['weston', '--backend=headless', '--renderer=gl',
            '--shell=kiosk-shell.so', '--socket=headless', '--no-config', '--idle-time=0',
            '--width=1920', '--height=1200'], 'weston.log')
        wait_ready(weston, lambda: (Path(runtime) / 'headless').is_socket(), 'headless Weston')
        env['WAYLAND_DISPLAY'] = 'headless'
        config = artifacts / 'parent.toml'
        config.write_text('[layout]\ndefault_column_width={pixels=1360}\n[animations]\nenabled=false\n')
        control = Control(Path(runtime) / 'parent.sock')
        parent = launch([str(BINARY), '--no-clients', '--test-input',
            '--config', str(config), '--control-socket', control.path], 'parent.log')
        stack.callback(quit_parent, parent, control)
        state = wait_ready(parent, control, 'isolated parent compositor')
        env['WAYLAND_DISPLAY'] = state['wayland_display']
        env['OHMANSY_COMPOSITOR_CONTROL'] = control.path
        # Activated helpers must inherit the private display and XDG directories.
        # Do not depend on /etc/dbus-1/session.conf: an application sandbox can
        # expose a stub there even when the packaged daemon is available.
        bus_config = artifacts / 'bus.conf'
        bus_config.write_text('''<busconfig>
          <type>session</type><listen>unix:tmpdir=/tmp</listen>
          <auth>EXTERNAL</auth><standard_session_servicedirs/>
          <policy context="default">
            <allow own="*"/><allow send_destination="*"/>
            <allow receive_sender="*"/>
          </policy>
        </busconfig>''')
        bus = launch(['dbus-daemon', f'--config-file={bus_config}', '--nofork', '--nopidfile',
            f'--address={env["DBUS_SESSION_BUS_ADDRESS"]}'], 'bus.log')
        wait_ready(bus, lambda: (Path(runtime) / 'bus').is_socket(), 'private D-Bus session')
        if not (Path(runtime) / env['WAYLAND_DISPLAY']).is_socket():
            raise RuntimeError('The private test display disappeared')
        (artifacts / 'display.json').write_text(json.dumps({
            'runtime': runtime, 'wayland_display': env['WAYLAND_DISPLAY'],
            'parent_control': control.path, 'parent_pid': parent.pid,
            'weston_pid': weston.pid, 'command': command,
        }, indent=2))
        result = launch(command).wait()
    return result if result >= 0 else 128 - result


if __name__ == '__main__':
    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, interrupted)
    try:
        sys.exit(run())
    except KeyboardInterrupt:
        sys.exit(130)
    except (OSError, RuntimeError) as error:
        sys.exit(f'Headless display failed: {error}. No visible fallback was started.')
