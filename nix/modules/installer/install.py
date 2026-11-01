#!/usr/bin/env python3
"""Interactive whole-disk installer for the Ohmansy ARM VM image."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

SOURCE = Path('/etc/ohmansy/source')
TARGET = Path('/mnt/ohmansy')


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
                 'PATH,TYPE,SIZE,RO,MOUNTPOINTS,MODEL', capture_output=True, text=True)
    return available_disks(json.loads(result.stdout)['blockdevices'])


def valid_username(value):
    return bool(re.fullmatch(r'[a-z][a-z0-9_-]{0,30}', value)) and value not in {
        'root', 'nixos', 'nobody', 'sddm', 'systemd-network', 'systemd-resolve',
        'messagebus', 'polkituser', 'sshd', 'nixbld',
    } and not value.startswith(('nixbld', 'systemd-'))


def host_config(username, hostname):
    # Inputs have a restricted alphabet; JSON also produces valid Nix strings here.
    return '''{ ... }: {
  imports = [ ./hardware-configuration.nix ./ohmansy/nix/modules/desktop.nix ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = %s;
  system.stateVersion = "26.05";
  users.users.%s = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };
  services.openssh.enable = false;
}
''' % (json.dumps(hostname), json.dumps(username))


def write_configuration(username, hostname):
    config = TARGET / 'etc/nixos'
    config.mkdir(parents=True, exist_ok=True)
    shutil.copytree(SOURCE, config / 'ohmansy')
    (config / 'configuration.nix').write_text(host_config(username, hostname))
    (config / 'flake.nix').write_text('''{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  outputs = { nixpkgs, ... }: {
    nixosConfigurations.ohmansy = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [ ./configuration.nix ];
    };
  };
}
''')
    shutil.copyfile(SOURCE / 'flake.lock', config / 'flake.lock')


def main():
    if os.geteuid() != 0:
        raise SystemExit('Run sudo ohmansy-install from the live ISO.')
    if not Path('/sys/firmware/efi').exists():
        raise SystemExit('Boot this installer with UEFI firmware.')
    print('\nInstall Ohmansy\n')
    print('This installer erases ONE entire disk. It does not support dual boot.')
    print('An internet connection is required to build the installed configuration.\n')
    disks = list_disks()
    if not disks:
        raise SystemExit('No unused writable disk of at least 24 GiB found. Attach a blank VM disk.')
    for index, disk in enumerate(disks, 1):
        print(f"{index}. {disk['path']}  {disk['size'] / 1024**3:.1f} GiB  {disk.get('model') or ''}")
    selection = input('\nDisk number (Enter cancels): ').strip()
    if not selection:
        return
    if not selection.isdigit() or not 1 <= int(selection) <= len(disks):
        raise SystemExit('Invalid disk selection. No changes made.')
    device = disks[int(selection) - 1]['path']
    username = input('New username: ').strip()
    if not valid_username(username):
        raise SystemExit('Use a lowercase username with letters, digits, hyphens, or underscores.')
    hostname = input('Computer name [ohmansy]: ').strip() or 'ohmansy'
    if not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', hostname):
        raise SystemExit('Invalid computer name. No changes made.')
    confirmation = f'ERASE {device}'
    if input(f'\nAll data on {device} will be destroyed. Type {confirmation}: ') != confirmation:
        raise SystemExit('Cancelled. No changes made.')
    # Recheck immediately before modifying the selected device.
    if device not in [disk['path'] for disk in list_disks()]:
        raise SystemExit('The disk is now in use. No changes made.')
    TARGET.mkdir(parents=True, exist_ok=True)
    if any(TARGET.iterdir()) or os.path.ismount(TARGET):
        raise SystemExit(f'{TARGET} is not empty. Unmount any previous installation first.')
    run('parted', '--script', device, 'mklabel', 'gpt',
        'mkpart', 'ESP', 'fat32', '1MiB', '1025MiB', 'set', '1', 'esp', 'on',
        'mkpart', 'primary', 'ext4', '1025MiB', '100%')
    run('udevadm', 'settle')
    separator = 'p' if device[-1].isdigit() else ''
    efi, root = device + separator + '1', device + separator + '2'
    run('mkfs.fat', '-F', '32', efi)
    run('mkfs.ext4', '-F', root)
    run('mount', root, str(TARGET))
    (TARGET / 'boot').mkdir()
    run('mount', efi, str(TARGET / 'boot'))
    run('nixos-generate-config', '--root', str(TARGET))
    write_configuration(username, hostname)
    run('nixos-install', '--root', str(TARGET), '--no-root-passwd', '--no-channel-copy',
        '--flake', f'path:{TARGET}/etc/nixos#ohmansy')
    print(f'\nSet the password for {username}. Input is handled directly by passwd.\n')
    run('nixos-enter', '--root', str(TARGET), '--command', f'passwd {username}')
    run('sync')
    print('\nOhmansy is installed. Shut down, eject the ISO, and start the VM again.')
    print('System configuration: /etc/nixos. No SSH access has been enabled.')


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
