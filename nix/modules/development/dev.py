"""Enable or remove private development access on an installed Ohmansy system."""
import argparse
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import sys
import tempfile

# Share configuration checks and atomic writes with the release updater.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'updates'))
from update import atomic_write, fingerprint, run

CONFIG = Path('/etc/nixos')
STATE = Path('/var/lib/ohmansy/development')
PROFILE = Path('/nix/var/nix/profiles/system')
CURRENT = Path('/run/current-system')
IMPORT = '        ./development.nix # Managed by ohmansy-dev\n'
HEADER = '# Managed by ohmansy-dev. Personal settings; never include in an image.\n'


def public_key(value):
    fields = value.strip().split()
    if len(fields) < 2 or fields[0] != 'ssh-ed25519':
        raise ValueError('Supply an Ed25519 public key, not a private key.')
    try:
        data = base64.b64decode(fields[1], validate=True)
    except ValueError as error:
        raise ValueError('Invalid Ed25519 public key.') from error
    if len(data) != 51 or data[:19] != b'\0\0\0\x0bssh-ed25519\0\0\0\x20':
        raise ValueError('Invalid Ed25519 public key.')
    return ' '.join(fields[:2])


def owner(value):
    if not value or not re.fullmatch(r'[a-z_][a-z0-9_-]*', value) or value in ('root', 'nixos'):
        raise ValueError('Run through sudo from your installed owner, or supply --user.')
    if pwd.getpwnam(value).pw_uid < 1000:
        raise ValueError('Development access requires an existing normal user.')
    return value


def overlay(user, key, passwordless=True):
    # Follow the installed release, including after updates and store GC.
    return (HEADER + '{ ohmansy, ... }: {\n'
            '  imports = [ ohmansy.nixosModules.development ];\n'
            '  ohmansy.development = {\n    enable = true;\n'
            f'    user = {json.dumps(user)};\n'
            f'    authorizedKeys = [ {json.dumps(key)} ];\n'
            f'    passwordlessSudo = {str(passwordless).lower()};\n'
            '  };\n}\n').encode()


def regular_configuration(config):
    if config.is_symlink():
        raise ValueError('Symlink-managed configurations must enable the module manually.')
    for root, dirs, files in os.walk(config):
        dirs[:] = [name for name in dirs if name != '.git']
        for name in dirs + files:
            path = Path(root) / name
            if path.is_symlink() or not (path.is_file() or path.is_dir()):
                raise ValueError('Development setup requires regular configuration files.')


def plan(action, config, state, content=None):
    """Only edit our own overlay and one marked import; preserve other modules."""
    regular_configuration(config)
    flake = (config / 'flake.nix').read_text()
    target = config / 'development.nix'
    managed = state / 'managed.json'
    if target.exists():
        if not managed.exists() or hashlib.sha256(target.read_bytes()).hexdigest() != json.loads(managed.read_text())['sha256']:
            raise ValueError('development.nix is not managed by this command, or was edited. Preserve it and configure the module manually.')
        if flake.count('\n' + IMPORT) != 1:
            raise ValueError('The managed development import changed. Inspect flake.nix first.')
    elif action == 'disable':
        raise ValueError('No command-managed development configuration is installed.')
    elif 'development.nix' in flake:
        raise ValueError('An existing development import needs manual review.')
    if action == 'enable':
        if not target.exists():
            pattern = r'(?m)^(\s*modules\s*=\s*\[)'
            if len(re.findall(pattern, flake)) != 1:
                raise ValueError('Expected one modules list in flake.nix; configure the module manually.')
            flake = re.sub(pattern, lambda m: m[1] + '\n' + IMPORT, flake, count=1)
        return flake.encode(), content
    return flake.replace('\n' + IMPORT, '', 1).encode(), None


def activate(action, content=None, config=CONFIG, state=STATE, profile=PROFILE, current=CURRENT):
    flake, module = plan(action, config, state, content)
    before = fingerprint(config)
    transaction = Path(tempfile.mkdtemp(prefix=action + '-', dir=state))
    backup = transaction / 'previous'
    candidate = transaction / 'configuration'
    for destination in (backup, candidate):
        shutil.copytree(config, destination, ignore=shutil.ignore_patterns('.git'))
    (candidate / 'flake.nix').write_bytes(flake)
    if module is None:
        (candidate / 'development.nix').unlink()
    else:
        (candidate / 'development.nix').write_bytes(module)
    print('Building development configuration. Your running system is unchanged.', flush=True)
    run('nix', 'build', '--no-update-lock-file', '--out-link', transaction / 'system',
        'path:' + str(candidate) + '#nixosConfigurations.ohmansy.config.system.build.toplevel')
    if fingerprint(config) != before:
        raise ValueError('Local configuration changed during the build; run the command again.')
    system = (transaction / 'system').resolve(strict=True)
    previous_profile, previous_current = profile.resolve(strict=True), current.resolve(strict=True)
    atomic_write(transaction / 'previous-system', str(previous_profile).encode())
    managed = state / 'managed.json'
    previous_managed = managed.read_bytes() if managed.exists() else None
    try:
        atomic_write(config / 'flake.nix', flake)
        if module is None:
            (config / 'development.nix').unlink()
        else:
            atomic_write(config / 'development.nix', module)
        run('nix-env', '--profile', profile, '--set', system)
        run(system / 'bin/switch-to-configuration', 'switch')
        if module is None:
            managed.unlink()
        else:
            atomic_write(managed, json.dumps({'sha256': hashlib.sha256(module).hexdigest()}).encode())
    except BaseException:
        for name in ('flake.nix', 'development.nix'):
            saved, destination = backup / name, config / name
            if saved.exists():
                shutil.copy2(saved, destination)
            else:
                destination.unlink(missing_ok=True)
        if previous_managed is None:
            managed.unlink(missing_ok=True)
        else:
            atomic_write(managed, previous_managed)
        try:
            run('nix-env', '--profile', profile, '--set', previous_profile)
            run(previous_current / 'bin/switch-to-configuration', 'test')
            run(previous_profile / 'bin/switch-to-configuration', 'boot')
        except (OSError, subprocess.CalledProcessError):
            print(f'Automatic runtime rollback failed. Keep this session open. Recovery files: {transaction}', file=sys.stderr)
        raise
    atomic_write(transaction / 'applied', b'switch\n')
    print(f'Development access {"enabled" if action == "enable" else "disabled"}. No reboot needed.')
    print(f'Configuration backup: {backup}')


def main():
    parser = argparse.ArgumentParser(prog='ohmansy-dev', description=__doc__)
    commands = parser.add_subparsers(dest='action', required=True)
    enable = commands.add_parser('enable', help='Enable key-only SSH for your existing account')
    enable.add_argument('--public-key', required=True)
    enable.add_argument('--user', default=os.environ.get('SUDO_USER'))
    enable.add_argument('--require-password', action='store_true', help='Keep sudo password prompts')
    commands.add_parser('disable', help='Remove access configured by this command')
    commands.add_parser('status', help='Show whether the running system enables development access')
    args = parser.parse_args()
    if args.action == 'status':
        active = Path('/etc/ohmansy/development-access').is_file()
        print('Development access: ' + ('enabled in the running system' if active else 'disabled in the running system'))
        print('Local overlay: ' + ('present' if (CONFIG / 'development.nix').exists() else 'absent'))
        return
    if os.geteuid() != 0:
        raise ValueError('Run enable/disable with sudo.')
    content = None
    if args.action == 'enable':
        user, key = owner(args.user), public_key(args.public_key)
        content = overlay(user, key, not args.require_password)
    os.umask(0o077)
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Serialize with release updates as both commands manage /etc/nixos.
    lock_dir = STATE.parent / 'updates'
    lock_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (lock_dir / 'lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        activate(args.action, content)
    if args.action == 'enable':
        print('Verify this guest host-key fingerprint before connecting from the Mac:')
        run('ssh-keygen', '-lf', '/etc/ssh/ssh_host_ed25519_key.pub')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f'ohmansy-dev: {error}')
