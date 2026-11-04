#!/usr/bin/env python3
"""Boot an installer ISO or its installed disk in an isolated Linux QEMU VM."""
import argparse
import fcntl
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state', required=True, type=Path)
    media = parser.add_mutually_exclusive_group()
    media.add_argument('--iso', type=Path, help='Create a fresh VM and boot this ISO')
    media.add_argument('--rescue-iso', type=Path, help='Boot this ISO with an existing VM disk, without replacing it')
    parser.add_argument('--firmware-code', type=Path,
                        default=Path('/usr/share/edk2/x64/OVMF_CODE.4m.fd'))
    parser.add_argument('--firmware-vars', type=Path,
                        default=Path('/usr/share/edk2/x64/OVMF_VARS.4m.fd'))
    parser.add_argument('--headless', action='store_true', help='Accelerated display through a private VNC socket instead of a window')
    parser.add_argument('--memory-mib', type=int, default=8192)
    parser.add_argument('--no-network', action='store_true', help='Run without a network adapter, for offline installation tests')
    args = parser.parse_args()
    state = args.state.resolve()
    iso = args.iso or args.rescue_iso
    if iso and not iso.is_file():
        parser.error('ISO does not exist')
    if not args.firmware_code.is_file() or not args.firmware_vars.is_file():
        parser.error('Pass matching OVMF code and variables firmware files for this host.')
    if args.iso:
        # Refuse an existing state directory so no previous installation is lost.
        try:
            state.mkdir(mode=0o700, parents=True, exist_ok=False)
        except FileExistsError:
            parser.error('State directory already exists. Choose a fresh directory, or omit --iso to boot its existing disk.')
        with (state / 'disk.raw').open('xb') as disk:
            disk.truncate(64 * 1024**3)
        shutil.copyfile(args.firmware_vars, state / 'OVMF_VARS.fd')
    elif not (state / 'disk.raw').is_file() or not (state / 'OVMF_VARS.fd').is_file():
        parser.error('No installed VM here. Use --iso and a fresh --state directory first.')
    with (state / 'run.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error('This VM is already running.')
        command = [
            'qemu-system-x86_64', '-name', 'Ohmansy installer test',
            '-machine', 'q35,accel=kvm', '-cpu', 'host', '-smp', '4', '-m', str(args.memory_mib),
            '-drive', f'if=pflash,format=raw,readonly=on,file={args.firmware_code.resolve()}',
            '-drive', f'if=pflash,format=raw,file={state}/OVMF_VARS.fd',
            '-drive', f'if=none,id=system-disk,format=raw,file={state}/disk.raw',
            '-device', 'virtio-blk-pci,drive=system-disk,bootindex=2',
            '-device', 'qemu-xhci', '-device', 'usb-tablet',
            '-qmp', f'unix:{state}/qmp.sock,server=on,wait=off',
            '-chardev', f'socket,id=serial,path={state}/serial.sock,server=on,wait=off,logfile={state}/serial.log',
            '-serial', 'chardev:serial',
        ]
        if args.no_network:
            command += ['-nic', 'none']
        else:
            command += ['-netdev', 'user,id=network', '-device', 'virtio-net-pci,netdev=network']
        if args.headless:
            command += ['-vga', 'none', '-device', 'virtio-vga-gl',
                        '-display', 'egl-headless', '-vnc', f'unix:{state}/vnc.sock']
        else:
            command += ['-vga', 'none', '-device', 'virtio-vga-gl', '-display', 'gtk,gl=on']
        if iso:
            command += [
                '-drive', f'if=none,id=install-media,media=cdrom,readonly=on,file={iso.resolve()}',
                '-device', 'ide-cd,drive=install-media,bootindex=1',
                '-boot', 'menu=on',
            ]
        print(f'VM state: {state}\nShut down the guest before restarting without --iso.', flush=True)
        # QEMU inherits the lock even if this launcher is interrupted.
        os.set_inheritable(lock.fileno(), True)
        subprocess.run(command, check=True, pass_fds=(lock.fileno(),))


if __name__ == '__main__':
    main()
