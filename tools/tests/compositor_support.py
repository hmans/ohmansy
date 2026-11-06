"""Shared IPC, keyboard input and display isolation for compositor trials."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / ".build/spatial/debug/ohmansy-compositor"


def ensure_test_display():
    """Graphical automation is headless unless the caller explicitly opts in."""
    mode = os.environ.get('OHMANSY_TEST_DISPLAY')
    if mode == 'headless':
        runtime = Path(os.environ['XDG_RUNTIME_DIR'])
        control = Path(os.environ['OHMANSY_COMPOSITOR_CONTROL'])
        if not ((runtime / 'headless').is_socket() and control.parent == runtime and control.is_socket()):
            raise RuntimeError('The private headless display is unavailable; refusing to use the desktop')
        return
    if mode == 'visible':
        return
    runner = ROOT / 'tools/dev/compositor-test-display.py'
    os.execv(sys.executable, [sys.executable, str(runner), '--', sys.executable, *sys.argv])


def wait_for(function, timeout=15, description="condition"):
    deadline = time.monotonic() + timeout
    last_error = None
    while time.monotonic() < deadline:
        try:
            result = function()
            if result:
                return result
        except (OSError, ValueError, KeyError, AssertionError) as error:
            last_error = error
        time.sleep(0.1)
    raise AssertionError(f"Timed out waiting for {description}: {last_error}")


def parent_windows():
    ensure_test_display()
    path = os.environ.get('OHMANSY_COMPOSITOR_CONTROL')
    if os.environ.get('OHMANSY_TEST_DISPLAY') == 'headless':
        state = Control(path)()
        if state['wayland_display'] != os.environ['WAYLAND_DISPLAY']:
            raise RuntimeError('Headless parent does not host the configured test display')
        return [{**window, 'pid': state['pid'], 'is_focused': window['focused']}
                for window in state['windows']]
    if path:
        try:
            state = Control(path)()
            if state['wayland_display'] == Path(os.environ['WAYLAND_DISPLAY']).name:
                return [{**window, 'pid': state['pid'], 'is_focused': window['focused']}
                        for window in state['windows']]
        except (OSError, ValueError, AssertionError):
            pass
        # A retained agent can outlive the login that supplied this path too.
        os.environ.pop('OHMANSY_COMPOSITOR_CONTROL', None)
    try:
        return json.loads(subprocess.check_output(["niri", "msg", "--json", "windows"], stderr=subprocess.PIPE))
    except (OSError, subprocess.CalledProcessError):
        # A long-lived agent may retain a previous desktop's environment after
        # login. Find only the Shine server hosting the current Wayland socket.
        runtime = Path(os.environ['XDG_RUNTIME_DIR'])
        display = Path(os.environ['WAYLAND_DISPLAY']).name
        matches = []
        for path in runtime.glob('ohmansy-compositor-*.sock'):
            try:
                state = Control(path)()
                if state['wayland_display'] == display:
                    matches.append((path, state))
            except (OSError, ValueError, AssertionError):
                continue
        if len(matches) != 1:
            raise AssertionError('Cannot identify the compositor hosting the current Wayland display')
        path, state = matches[0]
        os.environ['OHMANSY_COMPOSITOR_CONTROL'] = str(path)
        return [{**window, 'pid': state['pid'], 'is_focused': window['focused']}
                for window in state['windows']]


def focus_parent_window(ident):
    path = os.environ.get('OHMANSY_COMPOSITOR_CONTROL')
    if path:
        Control(path)('focus', ident)
    else:
        subprocess.run(['niri', 'msg', 'action', 'focus-window', '--id', str(ident)], check=True, stdout=subprocess.DEVNULL)


class Control:
    def __init__(self, path):
        self.path = str(path)
        self._socket_alias = None
        # Linux Unix-domain sockets have a 108-byte path limit. Worktree
        # artifact paths can exceed it; keep the socket in the artifacts but
        # bind and connect through a short, private directory alias.
        if len(os.fsencode(self.path)) >= 104:
            self._socket_alias = tempfile.TemporaryDirectory(prefix='shine-ipc-')
            alias = Path(self._socket_alias.name) / 'artifacts'
            alias.symlink_to(Path(path).parent.resolve(), target_is_directory=True)
            self.path = str(alias / Path(path).name)

    def send_keys(self, keycodes, modifiers=()):
        """Send data key events only to this compositor's private test socket."""
        held = [{"ctrl": 29, "alt": 56, "shift": 42, "super": 125}[modifier] for modifier in modifiers]
        for code in held:
            self("key", code=code, pressed=True)
        for code in keycodes:
            self("key", code=code, pressed=True)
            time.sleep(.05)
            self("key", code=code, pressed=False)
            time.sleep(.15)
        for code in reversed(held):
            self("key", code=code, pressed=False)
        time.sleep(.1)

    def __call__(self, action="status", value=None, **fields):
        request = {"action": action, **fields}
        if value is not None:
            request["value"] = value
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(5)
            connection.connect(self.path)
            connection.sendall(json.dumps(request).encode() + b"\n")
            with connection.makefile("rb") as stream:
                response = json.loads(stream.readline())
        assert response["ok"], response
        return response["state"]


def window_for(control, app):
    return next((window for window in control()["windows"] if window["app_id"] == app), None)


def keys(control, pid, window_id, keycodes, modifiers=(), gui_only=False):
    state = control("focus", window_id)
    assert state["pid"] == pid
    focused = next(window for window in state["windows"] if window["id"] == state["focused"])
    if gui_only:
        assert focused["app_id"] in {"firefox", "org.gnome.TextEditor"}, focused
    selection_updates = state["selection_updates"]
    control.send_keys(keycodes, modifiers)
    if ("ctrl" in modifiers or "super" in modifiers) and 46 in keycodes:
        wait_for(lambda: control()["selection_updates"] > selection_updates, description="clipboard publication")
