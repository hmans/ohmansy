#!/usr/bin/env python3
"""Package a live or installer ISO, source, and checksums without publishing."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess

spec = importlib.util.spec_from_file_location('guest_dev', Path(__file__).resolve().parents[2] / 'tools/dev/guest-dev.py')
guest_dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guest_dev)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iso', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--architecture', choices=['aarch64-linux', 'x86_64-linux'], default='aarch64-linux')
    parser.add_argument('--kind', choices=['live', 'installer'], default='installer')
    parser.add_argument('--graphics', choices=['generic', 'nvidia'], default='generic')
    args = parser.parse_args()
    if not args.iso.is_file() or args.iso.suffix != '.iso':
        parser.error('--iso must name an existing ISO image')
    with args.iso.open('rb') as stream:
        stream.seek(0x8001)
        if stream.read(5) != b'CD001':
            parser.error('--iso has no ISO 9660 volume descriptor')
    args.output.mkdir(parents=True, exist_ok=False)
    image = args.output / args.iso.name
    shutil.copyfile(args.iso, image)
    with image.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    source = args.output / 'ohmansy-source.tar.gz'
    source.write_bytes(guest_dev.source_archive())
    source_digest = hashlib.sha256(source.read_bytes()).hexdigest()
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip())
    manifest = {
        'schemaVersion': 1,
        'product': 'ohmansy',
        'channel': f'{args.kind}-preview',
        'architecture': args.architecture,
        'graphics': args.graphics,
        'sourceRevision': revision,
        'sourceDirty': dirty,
        'source': {'file': source.name, 'sha256': source_digest},
        'image': {'file': image.name, 'bytes': image.stat().st_size, 'sha256': digest},
        'persistentInstallation': args.kind == 'installer',
        'requires': {'firmware': 'UEFI', 'memoryMiB': 4096},
    }
    if args.kind == 'installer':
        manifest['installer'] = {'mode': 'whole-disk', 'networkRequired': True, 'minimumDiskGiB': 24}
    (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (args.output / 'SHA256SUMS').write_text(f'{digest}  {image.name}\n{source_digest}  {source.name}\n')
    shutil.copyfile('flake.lock', args.output / 'flake.lock')
    print(args.output)


if __name__ == '__main__':
    main()
