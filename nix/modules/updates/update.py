"""Prepare and apply an Ohmansy release without replacing local configuration."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

CONFIG = Path('/etc/nixos')
STATE = Path('/var/lib/ohmansy/updates')
PROFILE = Path('/nix/var/nix/profiles/system')
PIN = re.compile(r'(?m)^(\s*inputs\.ohmansy\.url\s*=\s*)"[^"\n]+";\s*$')


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def fingerprint(directory):
    """Detect local edits between prepare and apply, including symlink changes."""
    digest = hashlib.sha256()
    for root, dirs, files in os.walk(directory, followlinks=False):
        dirs[:] = sorted(name for name in dirs if name != '.git')
        for name in sorted(set(dirs + files)):
            path = Path(root) / name
            digest.update(str(path.relative_to(directory)).encode() + b'\0')
            if path.is_symlink():
                digest.update(b'link\0' + os.readlink(path).encode())
            elif path.is_file():
                digest.update(b'file\0' + path.read_bytes())
            else:
                digest.update(b'dir\0')
            digest.update(b'\0')
    return digest.hexdigest()


def release_url(ref):
    if not re.fullmatch(r'(?:[0-9a-f]{40}|v[0-9]+\.[0-9]+\.[0-9]+(?:[-.][A-Za-z0-9.-]+)?)', ref):
        raise ValueError('Use a full commit ID or a release tag such as v0.2.0.')
    return 'github:hmans/ohmansy/' + ref


def pin_release(text, ref):
    url = release_url(ref)
    if len(PIN.findall(text)) != 1:
        raise ValueError('Expected one inputs.ohmansy.url declaration. See docs/updates.md for migration.')
    return PIN.sub(lambda match: match[1] + json.dumps(url) + ';', text)


def atomic_write(path, data):
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def prepare(ref, config=CONFIG, state=STATE):
    for root, dirs, files in os.walk(config, followlinks=False):
        dirs[:] = [name for name in dirs if name != '.git']
        for name in dirs + files:
            path = Path(root) / name
            if path.is_symlink():
                raise ValueError('Update preparation requires regular configuration files, not symlinks. '
                                 'Use nixos-rebuild directly for a symlink-managed configuration.')
    updated = pin_release((config / 'flake.nix').read_text(), ref)
    before = fingerprint(config)
    transaction = Path(tempfile.mkdtemp(prefix='update-', dir=state))
    candidate = transaction / 'configuration'
    shutil.copytree(config, candidate, symlinks=True, ignore=shutil.ignore_patterns('.git'))
    (candidate / 'flake.nix').write_text(updated)
    run('nix', 'flake', 'lock', 'path:' + str(candidate))
    # Keep the exact built closure rooted until the user applies or discards it.
    run('nix', 'build', '--no-update-lock-file', '--out-link', transaction / 'system',
        'path:' + str(candidate) + '#nixosConfigurations.ohmansy.config.system.build.toplevel')
    if fingerprint(config) != before:
        raise ValueError('Local configuration changed during the build. Prepare the update again.')
    manifest = {'before': before, 'release': ref, 'candidate': fingerprint(candidate),
                'system': str((transaction / 'system').resolve())}
    atomic_write(transaction / 'manifest.json', json.dumps(manifest, indent=2).encode())
    print(f'Update built. Apply with: sudo ohmansy-update apply {transaction.name}')
    return transaction


def apply(identifier, config=CONFIG, state=STATE, profile=PROFILE, store=Path('/nix/store')):
    if not re.fullmatch(r'update-[a-zA-Z0-9_-]+', identifier):
        raise ValueError('Invalid update ID.')
    transaction = state / identifier
    if (transaction / 'applied').exists():
        raise ValueError('This update was already applied.')
    manifest = json.loads((transaction / 'manifest.json').read_text())
    candidate = transaction / 'configuration'
    if fingerprint(config) != manifest['before']:
        raise ValueError('Local configuration changed. Prepare a new update to include your edits.')
    if fingerprint(candidate) != manifest['candidate']:
        raise ValueError('Prepared configuration changed. Prepare a new update.')
    system = (transaction / 'system').resolve(strict=True)
    if str(system) != manifest['system'] or system.parent != store:
        raise ValueError('Prepared system does not match the built update.')
    previous = profile.resolve(strict=True)
    backup = transaction / 'previous'
    backup.mkdir(exist_ok=True)
    for name in ('flake.nix', 'flake.lock'):
        shutil.copy2(config / name, backup / name)
    atomic_write(transaction / 'previous-system', str(previous).encode())
    try:
        run('nix-env', '--profile', profile, '--set', system)
        run(system / 'bin/switch-to-configuration', 'boot')
        # Only the release reference and lock change; all user modules stay put.
        for name in ('flake.nix', 'flake.lock'):
            atomic_write(config / name, (candidate / name).read_bytes())
    except BaseException:
        for name in ('flake.nix', 'flake.lock'):
            atomic_write(config / name, (backup / name).read_bytes())
        try:
            run('nix-env', '--profile', profile, '--set', previous)
            run(previous / 'bin/switch-to-configuration', 'boot')
        except subprocess.CalledProcessError:
            print('Could not restore the boot default. Keep this session open and inspect the bootloader.', file=sys.stderr)
        raise
    atomic_write(transaction / 'applied', b'boot\n')
    print('Update selected for the next boot. Restart when ready. The current desktop is unchanged.')


def main():
    parser = argparse.ArgumentParser(prog='ohmansy-update', description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('prepare', help='Build a release with your local settings').add_argument('release')
    commands.add_parser('apply', help='Select a prepared update for the next boot').add_argument('id')
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise ValueError('Run with sudo.')
    os.umask(0o077)
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (STATE / 'lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.command == 'prepare':
            prepare(args.release)
        else:
            apply(args.id)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f'ohmansy-update: {error}')
