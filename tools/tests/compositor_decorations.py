#!/usr/bin/env python3
"""Check real pixels and input at rounded windows in an isolated Shine session."""
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time
import zlib

import compositor_support as trial


def png_pixels(path):
    """Read the compositor's 8-bit RGBA PNGs without an extra test dependency."""
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    assert data[-12:] == b'\x00\x00\x00\x00IEND\xaeB`\x82', 'Framebuffer is still being written'
    offset, compressed = 8, bytearray()
    while offset < len(data):
        size = struct.unpack_from('>I', data, offset)[0]
        kind, chunk = data[offset + 4:offset + 8], data[offset + 8:offset + 8 + size]
        if kind == b'IHDR':
            width, height, depth, color, _, _, interlace = struct.unpack('>IIBBBBB', chunk)
            assert (depth, color, interlace) == (8, 6, 0)
        elif kind == b'IDAT':
            compressed.extend(chunk)
        offset += size + 12
    raw, stride = zlib.decompress(compressed), width * 4
    rows, previous = [], bytearray(stride)
    def pixel(x, y):
        nonlocal previous
        x, y = int(x), int(y)
        assert 0 <= x < width and 0 <= y < height, (x, y, width, height)
        while len(rows) <= y:
            start = len(rows) * (stride + 1)
            mode, row = raw[start], bytearray(raw[start + 1:start + 1 + stride])
            for column in range(stride):
                left, up, upper_left = (row[column - 4] if column >= 4 else 0), previous[column], (previous[column - 4] if column >= 4 else 0)
                predictor = (0, left, up, (left + up) // 2)[mode] if mode < 4 else min(
                    (left, up, upper_left), key=lambda v: abs(left + up - upper_left - v))
                row[column] = (row[column] + predictor) & 255
            rows.append(row)
            previous = row
        return tuple(rows[y][x * 4:x * 4 + 3])
    return pixel



if __name__ == "__main__":
    from compositor_frames import run
    run()
