#!/usr/bin/env python3
"""Create or resume an isolated persistent VM from a packaged Ohmansy factory."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def validate_manifest(manifest):
    if (manifest.get('schemaVersion') != 1 or manifest.get('product') != 'ohmansy'
            or manifest.get('kind') != 'factory' or manifest.get('format') != 'raw.zst'
            or manifest.get('architecture') != 'aarch64-linux'):
        raise ValueError('Unsupported factory manifest')
    name = manifest['image']['file']
    if not name or Path(name).name != name or not name.endswith('.raw.zst'):
        raise ValueError('Unsafe factory image filename')
    return name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--factory', required=True, type=Path)
    parser.add_argument('--state', required=True, type=Path)
    parser.add_argument('--memory-mib', type=int, default=4096)
    parser.add_argument('--cpus', type=int, default=4)
    parser.add_argument('--helper', type=Path, default=ROOT / 'dist/Ohmansy.app/Contents/Helpers/try ohmansy.app')
    parser.add_argument('--probe', type=Path, default=Path(__file__).with_name('gpu-probe.py'))
    args = parser.parse_args()
    manifest = json.loads((args.factory / 'manifest.json').read_text())
    image = args.factory / validate_manifest(manifest)
    state = args.state.resolve()
    if not (state / 'disk.raw').exists():
        # Refuse to adopt an unrelated directory or overwrite any existing VM.
        state.mkdir(parents=True, exist_ok=True, mode=0o700)
        if any(p.name != 'app-launcher.log' for p in state.iterdir()):
            raise ValueError('Refusing to initialize a nonempty VM directory')
        if image.is_symlink() or image.stat().st_size != manifest['image']['bytes']:
            raise ValueError('Factory image size or file type mismatch')
        with image.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != manifest['image']['sha256']:
                raise ValueError('Factory image checksum mismatch')
        bundled_zstd = args.helper / 'Contents/MacOS/zstd'
        zstd = str(bundled_zstd) if bundled_zstd.is_file() else (shutil.which('zstd') or '/Applications/Try Omarchy.app/Contents/Resources/runtime/bin/zstd')
        with tempfile.TemporaryDirectory(prefix='factory-', dir=state) as temporary:
            disk = Path(temporary) / 'disk.raw'
            subprocess.run([zstd, '-d', '--sparse', str(image.resolve()), '-o', str(disk)], check=True)
            if disk.stat().st_size > 64 * 1024**3:
                raise ValueError('Factory exceeds the default 64 GiB disk capacity')
            with disk.open('r+b') as stream:
                stream.truncate(64 * 1024**3)
            disk.rename(state / 'disk.raw')
        (state / 'factory.json').write_text(json.dumps(manifest, indent=2) + '\n')
    elif not (state / 'factory.json').is_file():
        raise ValueError('This directory is not a factory VM')
    # start-copy reuses an existing disk and initializes its private UEFI store.
    print('OHMANSY_FACTORY_READY', flush=True)
    subprocess.run([sys.executable, str(args.probe), 'start-copy',
                    '--source', str(state / 'unused-source'), '--state', str(state),
                    '--helper', str(args.helper), '--cpus', str(args.cpus),
                    '--ssh-port', '0', '--memory-mib', str(args.memory_mib)], check=True)


if __name__ == '__main__':
    main()
