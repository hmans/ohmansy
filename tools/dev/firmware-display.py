#!/usr/bin/env python3
"""Set an EDK II VM's boot graphics resolution from inside its Linux guest."""
import argparse
import json
import os
from pathlib import Path
import struct

VARIABLE = Path('/sys/firmware/efi/efivars/PlatformConfig-7235c51c-0c80-4cab-87ac-3b084a6304b1')
# EDK II OvmfPkg/PlatformDxe/PlatformConfig.h: two little-endian UINT32s.
# efivarfs prefixes the value with its UINT32 attributes (NV | BS | RT).
RESOLUTIONS = {'1024x768': (1024, 768), '1280x800': (1280, 800), '1920x1200': (1920, 1200)}


def resolution_value(previous, width, height):
    if previous is not None:
        if len(previous) != 12 or struct.unpack_from('<I', previous)[0] != 7:
            raise ValueError('Unknown PlatformConfig format; refusing to replace it')
    return struct.pack('<III', 7, width, height)


def set_resolution(variable, resolution, backup):
    previous = variable.read_bytes() if variable.exists() else None
    value = resolution_value(previous, *RESOLUTIONS[resolution])
    if value == previous:
        return False
    # Save the exact old value before touching NVRAM. Refuse backup replacement.
    descriptor = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        json.dump({'previous': previous.hex() if previous is not None else None}, stream)
    variable.write_bytes(value)
    if variable.read_bytes() != value:
        raise RuntimeError('Firmware resolution readback failed')
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('resolution', choices=RESOLUTIONS)
    parser.add_argument('--backup', type=Path, required=True,
                        help='New file to save the previous firmware variable value')
    args = parser.parse_args()
    if not VARIABLE.parent.is_dir():
        parser.error('Run inside the EDK II guest with efivarfs mounted')
    changed = set_resolution(VARIABLE, args.resolution, args.backup)
    print('Firmware resolution saved; restart the guest to apply.' if changed else 'Already configured.')


if __name__ == '__main__':
    main()
