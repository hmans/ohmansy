#!/usr/bin/env python3
"""Boot an ISO with the packaged graphics engine and an isolated test disk."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.build.signing import sign, signing_identity

ROOT = Path(__file__).resolve().parents[2]


def clone(source, destination):
    subprocess.run(['/bin/cp', '-c', str(source), str(destination)], check=True)
    return str(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iso', required=True, type=Path)
    parser.add_argument('--state', type=Path, default=ROOT / '.local/installer-test')
    args = parser.parse_args()
    state = args.state.resolve()
    if not args.iso.is_file():
        parser.error('ISO does not exist')
    # A new test directory guarantees no existing guest disk can be overwritten.
    state.mkdir(parents=True, exist_ok=False, mode=0o700)
    helper = state / 'Ohmansy Installer Test.app'
    shutil.copytree(ROOT / 'dist/Ohmansy.app/Contents/Helpers/try ohmansy.app', helper,
                    copy_function=clone, symlinks=True)
    info_path = helper / 'Contents/Info.plist'
    with info_path.open('rb') as stream:
        info = plistlib.load(stream)
    info['CFBundleIdentifier'] = 'dev.hmans.ohmansy.installer-test'
    info['CFBundleName'] = info['CFBundleDisplayName'] = 'Ohmansy Installer Test'
    with info_path.open('wb') as stream:
        plistlib.dump(info, stream)
    sign(helper, signing_identity(), ROOT / 'app/resources/Runtime.entitlements')
    disk = state / 'install-target.raw'
    with disk.open('xb') as stream:
        stream.truncate(32 * 1024**3)
    print(f'Isolated 32 GiB test disk: {disk}', flush=True)
    subprocess.run([sys.executable, str(ROOT / 'app/runtime/gpu-probe.py'), 'start',
                    '--helper', str(helper), '--state', str(state),
                    '--iso', str(args.iso.resolve()), '--install-disk', str(disk),
                    '--ssh-port', '0', '--memory-mib', '6144'], check=True)


if __name__ == '__main__':
    main()
