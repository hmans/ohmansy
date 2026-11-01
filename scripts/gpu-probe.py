#!/usr/bin/env python3
"""Run NixOS with VirGL using a local runtime or the app-owned helper.

Live sessions are diskless. Persistent sessions use an independent disk copy;
the original VM disk and Try Omarchy's guest data are never attached.
"""

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import stat
import tempfile
import time


DEFAULT_APP = Path('/Applications/Try Omarchy.app')
DEFAULT_STATE = Path(__file__).resolve().parent.parent / '.local/gpu-probe'


def qemu_value(value):
    """QEMU's comma-separated option grammar escapes a literal comma by doubling it."""
    return str(value).replace(',', ',,')


def launch_arguments(app, iso, state, disk=None, helper=None, cpus=4, memory_mib=4096):
    resources = app / 'Contents/Resources'
    arguments = [
        str(helper / 'Contents/MacOS/try ohmansy' if helper else resources / 'runtime/bin/Try Omarchy'),
        '-name', 'try ohmansy',
        '-machine', 'virt,gic-version=3', '-accel', 'hvf',
        '-cpu', 'host,pmu=off', '-smp', str(cpus), '-m', str(memory_mib), '-nodefaults',
        '-device', 'qemu-xhci,id=usb',
        '-device', 'usb-kbd,bus=usb.0', '-device', 'usb-tablet,bus=usb.0',
        '-device', 'virtio-gpu-gl-pci,max_outputs=1,xres=1920,yres=1200,romfile=',
        '-display', 'cocoa,gl=on,show-cursor=off,zoom-to-fit=on,full-grab=on',
        '-netdev', 'user,id=net', '-device', 'virtio-net-pci,netdev=net,romfile=',
        '-device', 'virtio-rng-pci',
        '-serial', f'unix:{state / "serial.sock"},server=on,wait=off',
        '-qmp', f'unix:{state / "qmp.sock"},server=on,wait=off',
        '-monitor', 'none',
    ]
    firmware = resources / 'firmware/edk2-aarch64-code.fd'
    if helper:
        arguments += ['-S', '-no-shutdown']
        arguments[arguments.index('-netdev') + 1] = 'user,id=net,hostfwd=tcp:127.0.0.1:2222-:22'
        bootstrap = state / 'bootstrap.iso'
        if bootstrap.is_file():
            arguments += [
                '-drive', f'if=none,id=bootstrap,media=cdrom,format=raw,readonly=on,file={qemu_value(bootstrap)}',
                '-device', 'usb-storage,drive=bootstrap,bus=usb.0',
            ]
        firmware = helper / 'Contents/Resources/firmware/edk2-aarch64-code.fd'
    if disk is None:
        arguments += [
            '-bios', str(firmware),
            '-drive', f'if=none,id=installer,format=raw,readonly=on,file={qemu_value(iso)}',
            '-device', 'usb-storage,drive=installer,bootindex=0',
        ]
    else:
        arguments += [
            '-drive', f'if=pflash,format=raw,readonly=on,file={qemu_value(firmware)}',
            '-drive', f'if=pflash,format=raw,file={qemu_value(state / "efi-vars.fd")}',
            '-drive', f'if=none,id=root,format=raw,file={qemu_value(disk)}',
            '-device', 'virtio-blk-pci,drive=root,bootindex=0',
        ]
    return arguments


def require_regular_file(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_size == 0:
        raise RuntimeError(f'Expected a nonempty regular file, not a symlink: {path}')


def prepare_vm_copy(source, state):
    """Call under the destination lock. Clone once, under the original VM's lock."""
    disk = state / 'disk.raw'
    if disk.exists() or disk.is_symlink():
        require_regular_file(disk)
    else:
        # Do not create or change anything in the original VM directory.
        descriptor = os.open(source / 'lock', os.O_RDONLY | os.O_NOFOLLOW)
        try:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError('Shut down the original NixOS VM before creating its accelerated copy.') from None
            original = source / 'disk.raw'
            require_regular_file(original)
            with tempfile.TemporaryDirectory(prefix='import-', dir=state) as temporary:
                clone = Path(temporary) / 'disk.raw'
                # APFS copy-on-write clone; no full allocation of the 64 GiB image.
                subprocess.run(['/bin/cp', '-c', str(original), str(clone)], check=True)
                require_regular_file(clone)
                os.replace(clone, disk)
        finally:
            os.close(descriptor)
    variables = state / 'efi-vars.fd'
    try:
        with variables.open('xb') as stream:
            stream.truncate(64 * 1024 * 1024)
    except FileExistsError:
        require_regular_file(variables)
        if variables.stat().st_size != 64 * 1024 * 1024:
            raise RuntimeError('Unexpected QEMU EFI variable-store size; it has not been replaced.')
    return disk


def qmp_command(state, command):
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(5)
        connection.connect(str(state / 'qmp.sock'))
        stream = connection.makefile('rwb')
        greeting = json.loads(stream.readline())
        if 'QMP' not in greeting:
            raise RuntimeError('The graphics probe did not send a QMP greeting.')
        for index, name in enumerate(['qmp_capabilities', command]):
            stream.write((json.dumps({'execute': name, 'id': index}) + '\n').encode())
            stream.flush()
            while True:
                line = stream.readline()
                if not line:
                    raise RuntimeError('QEMU closed the control connection.')
                reply = json.loads(line)
                if reply.get('id') == index:
                    if 'error' in reply:
                        raise RuntimeError(str(reply['error']))
                    break
        return reply['return']


def diagnose_guest(state):
    """Use the live ISO's serial login, never GUI keystroke injection."""
    with socket.socket(socket.AF_UNIX) as connection, (state / 'guest-gpu.log').open('w') as log:
        connection.settimeout(1)
        connection.connect(str(state / 'serial.sock'))
        connection.sendall(b'\r')
        deadline = time.monotonic() + 20
        received = ''
        sent_login = False
        sent_command = False
        while time.monotonic() < deadline:
            try:
                data = connection.recv(65536)
            except socket.timeout:
                continue
            if not data:
                break
            text = data.decode(errors='replace')
            log.write(text)
            log.flush()
            received += text
            plain = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', received[-8000:])
            if not sent_login and plain.rstrip().endswith('login:'):
                connection.sendall(b'nixos\r')
                sent_login = True
            if not sent_command and re.search(r'(nixos|root)@[^\r\n]*[#$]\s*$', plain):
                command = (
                    "printf '\\nOHMANSY_GPU_BEGIN\\n'; "
                    "uname -m; ls -l /dev/dri; "
                    "timeout 120 nix-shell -p mesa-demos --run 'EGL_PLATFORM=surfaceless eglinfo -B'; "
                    "printf '\\nOHMANSY_NIRI_BEGIN\\n'; "
                    "timeout 120 nix-shell -p niri --run "
                    "'WAYLAND_DISPLAY=wayland-0 timeout 15 niri --config /dev/null'; "
                    "printf '\\nOHMANSY_NIRI_EXIT=%s\\n' \"$?\"; "
                    "printf '\\nOHMANSY_GPU_END\\n'\r"
                )
                connection.sendall(command.encode())
                sent_command = True
                received = ''
                deadline = time.monotonic() + 270
            elif sent_command and '\nOHMANSY_GPU_END' in plain:
                print(f'Guest diagnostics saved to {state / "guest-gpu.log"}')
                return
        if not sent_command:
            raise RuntimeError('No live-ISO serial shell found. See guest-gpu.log; no guest settings were changed.')
        raise RuntimeError('Guest diagnostics did not finish in time. See guest-gpu.log.')


def read_console(state):
    with socket.socket(socket.AF_UNIX) as connection, (state / 'boot-console.log').open('w') as log:
        connection.settimeout(1)
        connection.connect(str(state / 'serial.sock'))
        connection.sendall(b'\r')
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            try:
                data = connection.recv(65536)
            except socket.timeout:
                continue
            if not data:
                break
            log.write(data.decode(errors='replace'))
            log.flush()
    (state / 'runtime-status.json').write_text(json.dumps(qmp_command(state, 'query-status'), indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['check', 'start', 'start-copy', 'status', 'shutdown', 'stop', 'diagnose', 'console'])
    parser.add_argument('--app', type=Path, default=DEFAULT_APP)
    parser.add_argument('--iso', type=Path)
    parser.add_argument('--state', type=Path, default=DEFAULT_STATE)
    parser.add_argument('--source', type=Path, default=Path.home() / 'Library/Application Support/Ohmansy/VM')
    parser.add_argument('--helper', type=Path)
    parser.add_argument('--cpus', type=int, default=4)
    parser.add_argument('--memory-mib', type=int, default=4096)
    args = parser.parse_args()
    state = args.state.resolve()
    if args.action == 'console':
        read_console(state)
        return
    if args.action == 'diagnose':
        diagnose_guest(state)
        return
    if args.action in ['status', 'shutdown', 'stop']:
        command = {'status': 'query-status', 'shutdown': 'system_powerdown', 'stop': 'quit'}[args.action]
        print(json.dumps(qmp_command(state, command), indent=2))
        return

    app = args.app.resolve()
    binary = app / 'Contents/Resources/runtime/bin/Try Omarchy'
    firmware = app / 'Contents/Resources/firmware/edk2-aarch64-code.fd'
    helper = args.helper.resolve() if args.helper else None
    if helper:
        binary = helper / 'Contents/MacOS/try ohmansy'
        firmware = helper / 'Contents/Resources/firmware/edk2-aarch64-code.fd'
    if not binary.is_file() or not firmware.is_file():
        raise RuntimeError(f'Install Try Omarchy first; runtime or firmware missing in {app}')
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(helper or app)], check=True)
    subprocess.run([str(binary), '--version'], check=True)
    devices = subprocess.check_output([str(binary), '-device', 'help'], text=True)
    if '"virtio-gpu-gl-pci"' not in devices:
        raise RuntimeError('This QEMU runtime does not provide a VirGL GPU.')
    if args.action == 'check':
        print('Signed runtime and virtio-gpu-gl-pci found. Guest acceleration is not yet verified.')
        return

    if not 1 <= args.cpus <= (os.cpu_count() or 1) or args.memory_mib < 2048:
        raise RuntimeError('Choose a supported CPU count and at least 2048 MiB memory.')

    if args.action == 'start' and (not args.iso or not args.iso.is_file()):
        raise RuntimeError('Pass --iso with a graphical aarch64 NixOS installer ISO.')
    if ',' in str(state) or len(os.fsencode(state / 'serial.sock')) >= 104:
        raise RuntimeError('Use a shorter state path without commas for the Unix sockets.')
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    if args.action == 'start-copy' and state == args.source.resolve():
        raise RuntimeError('The accelerated copy must use a separate directory from the original VM.')
    descriptor = os.open(state / 'lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, 'a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('The graphics probe is already running.') from None
        disk = prepare_vm_copy(args.source.resolve(), state) if args.action == 'start-copy' else None
        arguments = launch_arguments(app, args.iso.resolve() if args.iso else None, state, disk,
                                     helper, args.cpus, args.memory_mib)
        environment = os.environ.copy()
        if helper:
            environment['DYLD_INSERT_LIBRARIES'] = str(helper / 'Contents/Frameworks/OhmansyChrome.dylib')
            environment['OHMANSY_QMP_SOCKET'] = str(state / 'qmp.sock')
        (state / 'launch.json').write_text(json.dumps(arguments, indent=2) + '\n')
        print(f'Starting GPU test. Log: {state / "qemu.log"}', flush=True)
        with (state / 'qemu.log').open('w') as log:
            # Hold the probe lock in QEMU too if this launcher exits unexpectedly.
            process = subprocess.Popen(arguments, stdout=log, stderr=log, env=environment,
                                       pass_fds=(lock.fileno(),))
            (state / 'runtime.pid').write_text(str(process.pid) + '\n')
            try:
                result = process.wait()
            except KeyboardInterrupt:
                qmp_command(state, 'system_powerdown')
                print('Requested a clean shutdown; waiting for the live session.', flush=True)
                result = process.wait()
        if result:
            raise RuntimeError(f'QEMU exited with status {result}; inspect {state / "qemu.log"}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f'gpu-probe: {error}', file=sys.stderr)
        sys.exit(1)
