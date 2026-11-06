"""Focus an existing Shine app before falling back to normal GIO launching."""
import configparser
import json
import os
from pathlib import Path
import socket
import sys


def activate(desktop_id):
    path = os.environ.get('OHMANSY_COMPOSITOR_CONTROL')
    if not path:
        return False
    names = [desktop_id.removesuffix('.desktop')]
    roots = [os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')),
             *os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share').split(':')]
    for root in roots:
        applications = Path(root) / 'applications'
        entry = applications / desktop_id
        if not entry.is_file():
            # Desktop IDs flatten subdirectories with hyphens.
            entry = next((p for p in applications.rglob('*.desktop')
                          if str(p.relative_to(applications)).replace('/', '-') == desktop_id), entry)
        if entry.is_file():
            parser = configparser.ConfigParser(interpolation=None, strict=False)
            parser.read(entry)
            wm_class = parser.get('Desktop Entry', 'StartupWMClass', fallback='')
            if wm_class:
                names.append(wm_class)
            break
    try:
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(3)
            connection.connect(path)
            connection.sendall(json.dumps({'action': 'activate-app', 'app_ids': names,
                                          'wayland_display': os.environ.get('WAYLAND_DISPLAY')}).encode() + b'\n')
            reply = json.loads(connection.makefile('rb').readline())
            return bool(reply.get('ok') and reply['state'].get('app_activated'))
    except (OSError, ValueError, KeyError):
        return False


if __name__ == '__main__':
    try:
        found = activate(sys.argv[1])
    except (OSError, configparser.Error):
        found = False
    sys.exit(0 if found else 1)
