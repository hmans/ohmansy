#!/usr/bin/env python3
"""Run a GPU-only nested Shine desktop and rebuild it when Rust sources change."""
import argparse
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def sources(root):
    paths = [root / 'nix/compositor/Cargo.toml', root / 'nix/compositor/Cargo.lock']
    paths.extend((root / 'nix/compositor/src').rglob('*.rs'))
    return tuple((str(path), path.stat().st_mtime_ns, path.stat().st_size)
                 for path in sorted(paths) if path.exists())


def request(path, action, timeout=1):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(timeout)
        connection.connect(str(path))
        connection.sendall(json.dumps({'action': action}).encode() + b'\n')
        with connection.makefile('rb') as stream:
            reply = json.loads(stream.readline(2 * 1024 * 1024))
    if not reply.get('ok'):
        raise RuntimeError(reply.get('error', 'Shine command failed'))
    return reply.get('state', {})


def stop(process, control):
    if process.poll() is None:
        try:
            request(control, 'quit', timeout=4)
        except (OSError, ValueError, RuntimeError):
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            # This group belongs only to our disposable preview and its apps.
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired as error:
                raise RuntimeError('Preview did not stop; refusing to start another one') from error
    # Some clients can outlive the compositor or private D-Bus launcher.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass


def modifier_for(parent, requested='auto'):
    if requested != 'auto':
        return requested
    options = parent.get('preferences', {}).get('input', {}).get('keyboard', {}).get('options', '') or ''
    # With Option configured as AltGr, older hosts consume Super+Option as
    # plain Super. Ctrl+Option reaches the preview without changing the host.
    return 'ctrl-alt' if 'lv3:lalt_switch' in {part.strip() for part in options.split(',')} else 'super-alt'


def run(root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--outputs', type=int, choices=range(1, 9), default=1)
    parser.add_argument('--scale', type=float, default=1.25)
    parser.add_argument('--no-watch', action='store_true')
    parser.add_argument('--mod-key', choices=['auto', 'super-alt', 'ctrl-alt'], default='auto')
    args = parser.parse_args()
    directory = root / '.local/shine-dev'
    directory.mkdir(parents=True, exist_ok=True)
    config = directory / 'config.toml'
    if not config.exists():
        config.write_text('# Private development preferences; edits reload live.\n')
    workspaces = directory / 'workspaces.toml'
    if not workspaces.exists():
        workspaces.write_text('# Private preview; do not launch personal task workspaces.\n')
    env = os.environ.copy()
    parent = {}
    parent_control = env.get('OHMANSY_COMPOSITOR_CONTROL')
    if args.mod_key == 'auto' and parent_control:
        try:
            candidate = request(parent_control, 'status')
            if candidate.get('wayland_display') == Path(env.get('WAYLAND_DISPLAY', '')).name:
                parent = candidate
        except (OSError, ValueError, RuntimeError):
            print('Could not inspect the parent keyboard; use --mod-key ctrl-alt if Option is AltGr.', flush=True)
    modifier = modifier_for(parent, args.mod_key)
    label = {'super-alt': 'Super+Alt', 'ctrl-alt': 'Ctrl+Alt (Control+Option)'}[modifier]
    env['OHMANSY_REQUIRE_HARDWARE_RENDERER'] = '1'
    env['OHMANSY_SHINE_SHADER_DIR'] = str(root / 'nix/compositor/src')
    target = Path(env.get('CARGO_TARGET_DIR', root / '.build/spatial'))
    binary = target / 'debug/ohmansy-compositor'
    stopping = False

    def interrupt(*_):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGINT, interrupt)
    signal.signal(signal.SIGTERM, interrupt)
    preview = None
    print(f'Shine development files: {directory}', flush=True)
    print('Rust saves rebuild only the preview; shader, QML and TOML edits reload live.', flush=True)
    print(f'Preview shortcuts: {label}+Enter for terminal, {label}+Space for launcher.', flush=True)
    with tempfile.TemporaryDirectory(prefix='shine-dev-', dir=env.get('XDG_RUNTIME_DIR')) as runtime:
        control = Path(runtime) / 'control.sock'
        try:
            observed = None
            while not stopping:
                changed = sources(root)
                if observed is None or (not args.no_watch and changed != observed):
                    time.sleep(.3)  # Coalesce an editor's save/rename sequence.
                    observed = sources(root)
                    print('Building Shine…', flush=True)
                    with (directory / 'build.log').open('a') as log:
                        result = subprocess.run(['mise', 'exec', '--', 'cargo', 'build', '--locked',
                            '--manifest-path', str(root / 'nix/compositor/Cargo.toml')],
                            cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
                    if stopping:
                        break
                    if result.returncode:
                        print('Build failed; the current preview stays open. Save again to retry.', flush=True)
                        print('\n'.join((directory / 'build.log').read_text().splitlines()[-25:]), flush=True)
                        if args.no_watch:
                            return result.returncode
                        continue
                    if preview is not None:
                        stop(preview, control)
                    control.unlink(missing_ok=True)
                    command = ['dbus-run-session', '--', str(binary), '--backend', 'winit', '--desktop',
                        '--mod-key', modifier,
                        '--outputs', str(args.outputs), '--scale', str(args.scale),
                        '--config', str(config), '--workspaces', str(workspaces),
                        '--control-socket', str(control), '--report', str(directory / 'status.json'),
                        '--screenshot', str(directory / 'preview.png')]
                    with (directory / 'session.log').open('a') as log:
                        preview = subprocess.Popen(command, cwd=root, env=env, stdout=log,
                                                   stderr=subprocess.STDOUT, start_new_session=True)
                    deadline = time.monotonic() + 30
                    while not stopping:
                        if preview.poll() is not None:
                            print('\n'.join((directory / 'session.log').read_text().splitlines()[-25:]), flush=True)
                            raise RuntimeError('Shine preview exited during startup; no software fallback')
                        try:
                            state = request(control, 'status')
                            break
                        except (OSError, ValueError, RuntimeError):
                            if time.monotonic() >= deadline:
                                raise RuntimeError('Shine preview did not become ready')
                            time.sleep(.1)
                    if stopping:
                        break
                    graphics = state.get('graphics', {})
                    if graphics.get('acceleration') != 'hardware':
                        raise RuntimeError(f'Preview did not verify hardware rendering: {graphics}')
                    print(f'GPU: {graphics["renderer"]} ({graphics.get("device")})', flush=True)
                    (directory / 'connection.json').write_text(json.dumps({
                        'pid': state['pid'], 'socket': str(control),
                        'wayland_display': state['wayland_display'], 'graphics': graphics,
                        'shortcut_modifier': modifier}, indent=2))
                    print(f'Preview ready. Logs: {directory / "session.log"}', flush=True)
                if preview is not None and preview.poll() is not None:
                    return preview.returncode
                time.sleep(.3)
            return 0
        finally:
            if preview is not None:
                stop(preview, control)
            (directory / 'connection.json').unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        raise SystemExit(run())
    except RuntimeError as error:
        raise SystemExit(str(error))
