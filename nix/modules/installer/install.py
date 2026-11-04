#!/usr/bin/env python3
"""Interactive whole-disk installer for the Ohmansy installer image."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

SOURCE = Path('/etc/ohmansy/installation')
TARGET = Path('/mnt/ohmansy')
LOCK = Path('/run/ohmansy-installer.lock')
PAYLOAD = Path('/etc/ohmansy/installed-system')
ROOT_LABEL = 'OHMANSY_ROOT'
EFI_LABEL = 'OHMANSY_EFI'


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def available_disks(devices):
    def in_use(device):
        return (device.get('ro') or any(device.get('mountpoints') or [])
                or any(in_use(child) for child in device.get('children', [])))
    return [device for device in devices
            if device['type'] == 'disk' and device['size'] >= 24 * 1024**3
            and not in_use(device)]


def list_disks():
    result = run('lsblk', '--json', '--bytes', '--output',
                 'PATH,TYPE,SIZE,RO,MOUNTPOINTS,MODEL,SERIAL,WWN,MAJ:MIN', capture_output=True, text=True)
    return available_disks(json.loads(result.stdout)['blockdevices'])


def disk_token(disk):
    identity = {key: disk.get(key) for key in ('path', 'size', 'model', 'serial', 'wwn', 'maj:min')}
    return hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()


def preflight():
    if not Path('/sys/firmware/efi').exists():
        raise RuntimeError('Boot this installer with UEFI firmware.')
    if not (PAYLOAD / 'init').exists():
        raise RuntimeError('The offline system payload is missing.')


def validate_target(device, hostname, token=None):
    preflight()
    if not isinstance(hostname, str) or not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', hostname):
        raise RuntimeError('Use a computer name with lowercase letters, digits, and hyphens (up to 63 characters).')
    disk = next((disk for disk in list_disks() if disk['path'] == device), None)
    if disk is None or (token is not None and disk_token(disk) != token):
        raise RuntimeError('The selected disk changed or is now in use. Refresh the disk list. No changes made.')
    check_labels(device)
    if TARGET.exists() and (os.path.ismount(TARGET) or any(TARGET.iterdir())):
        raise RuntimeError(f'{TARGET} is not empty. A previous installation may need recovery. No changes made.')


def host_config(hostname):
    # Inputs have a restricted alphabet; JSON also produces valid Nix strings here.
    return '''{ ohmansy, ... }: {
  imports = [ ohmansy.nixosModules.firstBoot ./hardware-configuration.nix ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = %s;
  system.stateVersion = "26.05";
  services.openssh.enable = false;
}
''' % json.dumps(hostname)


def write_configuration(hostname):
    config = TARGET / 'etc/nixos'
    config.mkdir(parents=True, exist_ok=True)
    (config / 'configuration.nix').write_text(host_config(hostname))
    (config / 'owner.nix').write_text('{ ... }: { }\n')
    (config / 'preferences.nix').write_text('{ ... }: { }\n')
    shutil.copyfile(SOURCE / 'flake.nix', config / 'flake.nix')
    shutil.copyfile(SOURCE / 'flake.lock', config / 'flake.lock')
    (TARGET / 'etc/hostname').write_text(hostname + '\n')


def check_labels(device):
    # The initial closure boots by label. Refuse ambiguity on another disk;
    # later rebuilds use the UUIDs recorded by nixos-generate-config.
    selected = set(run('lsblk', '--noheadings', '--raw', '--paths', '--output',
                       'PATH', device, capture_output=True, text=True).stdout.split())
    for label in (ROOT_LABEL, EFI_LABEL):
        result = subprocess.run(['blkid', '-t', f'LABEL={label}', '-o', 'device'],
                                capture_output=True, text=True)
        if result.returncode not in (0, 2):
            raise SystemExit('Could not check existing filesystem labels. No changes made.')
        if set(result.stdout.split()) - selected:
            raise SystemExit(f'Another disk has the label {label}. Disconnect it before installing. No changes made.')


def main():
    if os.geteuid() != 0:
        raise SystemExit('Run sudo ohmansy-install from the live ISO.')
    with LOCK.open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit('An Ohmansy installation is already running. Return to its window or console.')
        install()


def install():
    if not Path('/sys/firmware/efi').exists():
        raise SystemExit('Boot this installer with UEFI firmware.')
    print('\nInstall Ohmansy\n')
    print('This installer erases ONE entire disk. It does not support dual boot.')
    if not (PAYLOAD / 'init').exists():
        raise SystemExit('The offline system payload is missing. No changes made.')
    print('Installation and account setup work without an internet connection.\n')
    disks = list_disks()
    if not disks:
        raise SystemExit('No unused writable disk of at least 24 GiB found.')
    for index, disk in enumerate(disks, 1):
        print(f"{index}. {disk['path']}  {disk['size'] / 1024**3:.1f} GiB  {disk.get('model') or ''}")
    selection = input('\nDisk number (Enter cancels): ').strip()
    if not selection:
        return
    if not selection.isdigit() or not 1 <= int(selection) <= len(disks):
        raise SystemExit('Invalid disk selection. No changes made.')
    device = disks[int(selection) - 1]['path']
    hostname = input('Computer name [ohmansy]: ').strip() or 'ohmansy'
    if not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', hostname):
        raise SystemExit('Invalid computer name. No changes made.')
    confirmation = f'ERASE {device}'
    if input(f'\nAll data on {device} will be destroyed. Type {confirmation}: ') != confirmation:
        raise SystemExit('Cancelled. No changes made.')
    perform_install(device, hostname, token=disk_token(disks[int(selection) - 1]))
    print('\nOhmansy is installed. Shut down, remove the installation media, and boot the installed disk.')
    print('The welcome screen will help you create your account on first boot.')
    print('System configuration: /etc/nixos. No SSH access has been enabled.')


def perform_install(device, hostname, *, token=None, progress=lambda stage: None, log=None):
    validate_target(device, hostname, token)
    TARGET.mkdir(parents=True, exist_ok=True)

    def execute(*args):
        if log is not None:
            log.write('\n$ ' + ' '.join(args) + '\n')
            log.flush()
            return run(*args, stdout=log, stderr=subprocess.STDOUT)
        return run(*args)

    progress('partition')
    execute('parted', '--script', device, 'mklabel', 'gpt',
        'mkpart', 'ESP', 'fat32', '1MiB', '1025MiB', 'set', '1', 'esp', 'on',
        'mkpart', 'primary', 'ext4', '1025MiB', '100%')
    execute('udevadm', 'settle')
    separator = 'p' if device[-1].isdigit() else ''
    efi, root = device + separator + '1', device + separator + '2'
    progress('format')
    execute('mkfs.fat', '-F', '32', '-n', EFI_LABEL, efi)
    execute('mkfs.ext4', '-F', '-L', ROOT_LABEL, root)
    execute('mount', '-t', 'ext4', root, str(TARGET))
    (TARGET / 'boot').mkdir()
    execute('mount', '-t', 'vfat', efi, str(TARGET / 'boot'), '-o', 'umask=0077')
    progress('configure')
    execute('nixos-generate-config', '--root', str(TARGET))
    write_configuration(hostname)
    progress('install')
    execute('nixos-install', '--root', str(TARGET), '--no-root-passwd', '--no-channel-copy',
        '--system', str(PAYLOAD.resolve()), '--option', 'substituters', '')
    progress('finish')
    execute('sync')
    execute('umount', '--recursive', str(TARGET))


if __name__ == '__main__':
    try:
        main()
    except (KeyboardInterrupt, EOFError):
        print('\nInstallation cancelled.', file=sys.stderr)
        sys.exit(1)
    except subprocess.CalledProcessError as error:
        print(f'\nInstallation stopped: {error}', file=sys.stderr)
        print(f'The target remains at {TARGET}; do not erase it again just to retry a build.', file=sys.stderr)
        sys.exit(1)
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
