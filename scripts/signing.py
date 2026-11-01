"""Use a stable local development identity when one is available."""
import argparse
import os
from pathlib import Path
import re
import subprocess


def choose_identity(output, override=None):
    if override:
        return override
    identities = re.findall(r'\b([0-9A-F]{40}) "Apple Development:[^"]+"', output)
    return identities[0] if len(identities) == 1 else '-'


def signing_identity():
    result = subprocess.run(['security', 'find-identity', '-v', '-p', 'codesigning'],
                            capture_output=True, text=True, check=True)
    identity = choose_identity(result.stdout, os.environ.get('OHMANSY_SIGN_IDENTITY'))
    if identity == '-':
        print('Using ad-hoc signing. macOS permissions may need reauthorizing after rebuilds. '
              'Set OHMANSY_SIGN_IDENTITY to a stable signing identity to retain them.')
    return identity


def sign(path, identity, entitlements=None):
    command = ['codesign', '--force', '--sign', identity, '--timestamp=none']
    if entitlements:
        command += ['--entitlements', str(entitlements)]
    subprocess.run(command + [str(path)], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('--entitlements', type=Path)
    args = parser.parse_args()
    sign(args.bundle, signing_identity(), args.entitlements)
