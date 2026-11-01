#!/usr/bin/env python3
"""Package the persistent VM factory, its source, and checksums."""
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
    parser.add_argument('--image', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    with args.image.open('rb') as stream:
        if stream.read(4) != b'\x28\xb5\x2f\xfd':
            parser.error('Expected a Zstandard-compressed raw disk')
    args.output.mkdir(parents=True, exist_ok=False)
    image = args.output / args.image.name
    shutil.copyfile(args.image, image)
    with image.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    source = args.output / 'ohmansy-source.tar.gz'
    source.write_bytes(guest_dev.source_archive())
    source_digest = hashlib.sha256(source.read_bytes()).hexdigest()
    manifest = {
        'schemaVersion': 1, 'product': 'ohmansy', 'kind': 'factory',
        'architecture': 'aarch64-linux', 'format': 'raw.zst',
        'sourceRevision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
        'sourceDirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], text=True).strip()),
        'image': {'file': image.name, 'bytes': image.stat().st_size, 'sha256': digest},
        'source': {'file': source.name, 'sha256': source_digest},
        'requires': {'firmware': 'UEFI', 'memoryMiB': 4096},
        'defaultDiskGiB': 64,
    }
    (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (args.output / 'SHA256SUMS').write_text(f'{digest}  {image.name}\n{source_digest}  {source.name}\n')
    print(args.output)


if __name__ == '__main__':
    main()
