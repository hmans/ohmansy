"""Compile the Icon Composer asset and Apple's legacy fallback with actool."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = root / 'app/resources/Ohmansy.icon'
output = root / '.build/app-icon'
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='ohmansy-icon-') as temporary:
    asset = Path(temporary) / source.name
    shutil.copytree(source, asset)
    # Normalize the canvas only. Apple's compiler owns masks and margins.
    subprocess.run(['sips', '-z', '1024', '1024', str(asset / 'Assets/Artwork.png')],
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['xcrun', 'actool', str(asset), '--compile', str(output),
                    '--platform', 'macosx', '--target-device', 'mac',
                    '--minimum-deployment-target', '14.0', '--app-icon', 'Ohmansy',
                    '--output-partial-info-plist', str(output / 'partial-info.plist')], check=True)
print(f'Built app icon: {output}')
