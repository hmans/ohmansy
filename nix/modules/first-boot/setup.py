"""Local, resumable owner setup. Passwords go directly to passwd."""
import json
from pathlib import Path
import pwd
import re
import subprocess
import sys

STATE = Path('/var/lib/ohmansy')
CONFIG = Path('/etc/nixos')


def valid_username(value):
    return bool(re.fullmatch(r'[a-z][a-z0-9_-]{0,30}', value)) and value not in {
        'root', 'nobody', 'nixos', 'sddm', 'greeter', 'daemon', 'bin', 'sys', 'sync',
    }


def main(shell):
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    pending = STATE / 'pending-owner'
    print('\nWelcome to ohmansy.\nCreate your local account to begin.\n', flush=True)
    if pending.exists():
        username = pending.read_text().strip()
        if not valid_username(username):
            raise RuntimeError('Invalid pending owner')
    else:
        while True:
            username = input('Username: ').strip()
            if not valid_username(username):
                print('Use a lowercase letter, then letters, digits, - or _.')
                continue
            try:
                pwd.getpwnam(username)
            except KeyError:
                break
            print('That account already exists. Choose another name.')
        pending.write_text(username + '\n')
    try:
        pwd.getpwnam(username)
    except KeyError:
        subprocess.run(['useradd', '--create-home', '--groups', 'wheel,networkmanager',
                        '--shell', shell, username], check=True)
    print(f'\nSet a password for {username}.', flush=True)
    while subprocess.run(['passwd', username]).returncode:
        print('Password was not saved. Please try again.', flush=True)
    # The owner remains declared when the system is rebuilt from its local flake.
    owner = CONFIG / 'owner.nix'
    owner.write_text('{ ... }: { users.users.' + json.dumps(username) + ' = {\n'
                     '  isNormalUser = true; extraGroups = [ "wheel" "networkmanager" ];\n'
                     '}; }\n')
    (STATE / 'provisioned').write_text(username + '\n')
    pending.unlink()
    print('\nAccount ready. Starting the desktop login screen.', flush=True)


if __name__ == '__main__':
    main(sys.argv[1])
