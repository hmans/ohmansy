"""Embed the verified factory in the normal application bundle."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--bundle', type=Path, default=root / 'dist/Ohmansy.app')
parser.add_argument('--factory', type=Path, default=root / 'dist/factory-preview')
args = parser.parse_args()
source = args.factory
manifest = json.loads((source / 'manifest.json').read_text())
name = manifest['image']['file']
if Path(name).name != name or manifest.get('kind') != 'factory':
    raise SystemExit('Invalid factory manifest')
image = source / name
with image.open('rb') as stream:
    if hashlib.file_digest(stream, 'sha256').hexdigest() != manifest['image']['sha256']:
        raise SystemExit('Factory checksum mismatch')
destination = args.bundle / 'Contents/Resources/Factory'
destination.mkdir(parents=True, exist_ok=True)
target = destination / name
if target.exists():
    target.unlink()
subprocess.run(['/bin/cp', '-c', str(image), str(target)], check=True)
shutil.copy2(source / 'manifest.json', destination / 'manifest.json')
print('Bundled Ohmansy factory image')
