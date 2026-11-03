#!/usr/bin/env python3
"""Stage a pinned local engine into a development build, without modifying its source app."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
from signing import sign, signing_identity

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--bundle', type=Path, default=root / 'dist/Ohmansy.app')
args = parser.parse_args()
source = Path('/Applications/Try Omarchy.app/Contents/Resources')
engine = source / 'runtime/bin/Try Omarchy'
expected = 'aa9c7e0e53fbba751d8014625366a2bf59f05d02dced6c9f9d394980823d5c66'
if hashlib.sha256(engine.read_bytes()).hexdigest() != expected:
    raise SystemExit('Unsupported runtime. This adapter is tested with Try Omarchy 1.2.0 (464).')
helper = args.bundle / 'Contents/Helpers/try ohmansy.app'
contents = helper / 'Contents'
for directory in ['MacOS', 'Frameworks', 'Resources', 'lib']:
    (contents / directory).mkdir(parents=True, exist_ok=True)
shutil.copy2(engine, contents / 'MacOS/try ohmansy')
shutil.copy2(source / 'runtime/bin/zstd', contents / 'MacOS/zstd')
shutil.copytree(source / 'runtime/lib', contents / 'lib', dirs_exist_ok=True)
shutil.copytree(source / 'firmware', contents / 'Resources/firmware', dirs_exist_ok=True)
shutil.copy2(source / 'LICENSE', contents / 'Resources/LICENSE.TryOmarchy')
shutil.copy2(source / 'Credits.rtf', contents / 'Resources/Credits.TryOmarchy.rtf')
shutil.copy2(root / 'app/resources/Runtime.plist', contents / 'Info.plist')
for resource in ['Ohmansy.icns', 'Assets.car']:
    shutil.copy2(root / '.build/app-icon' / resource, contents / 'Resources' / resource)
shutil.copy2(root / 'app/native/Welcome.metal', contents / 'Resources/Welcome.metal')
subprocess.run(['clang', '-dynamiclib', '-fobjc-arc', '-mmacosx-version-min=15.0',
                '-framework', 'AppKit', '-framework', 'QuartzCore', '-framework', 'ApplicationServices', '-framework', 'GameplayKit',
                '-framework', 'Metal', '-framework', 'MetalKit',
                str(root / 'app/native/RuntimeChrome.m'), str(root / 'app/native/WelcomeCanvas.m'),
                str(root / 'app/native/ClipboardBridge.m'), '-o',
                str(contents / 'Frameworks/OhmansyChrome.dylib')], check=True)
identity = signing_identity()
for library in [*sorted((contents / 'lib').glob('*.dylib')),
                contents / 'Frameworks/OhmansyChrome.dylib']:
    sign(library, identity)
sign(contents / 'MacOS/zstd', identity)
sign(helper, identity, root / 'app/resources/Runtime.entitlements')
print(f'Staged local QEMU/VirGL engine: {helper}')
