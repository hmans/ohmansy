#!/usr/bin/env python3
"""Exercise disposable native clients on an isolated headless Wayland desktop.

All window operations target the test compositor's private socket. Keyboard
events use a test-only path into the compositor's normal key handler. They do
not touch the parent desktop's input devices. No terminal command text is typed.
The isolated parent's window identities are checked after clean shutdown.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
from urllib.parse import quote

from compositor_support import (
    BINARY, ROOT, Control, ensure_test_display, focus_parent_window, keys,
    parent_windows, wait_for, window_for,
)


class Marionette:
    def __init__(self, port):
        self.connection = socket.create_connection(("127.0.0.1", port), timeout=10)
        self.sequence = 0
        self.receive()
        self.command("WebDriver:NewSession", {"capabilities": {"alwaysMatch": {"pageLoadStrategy": "eager"}}})

    def receive(self):
        length = b""
        while not length.endswith(b":"):
            byte = self.connection.recv(1)
            if not byte:
                raise ConnectionError("Browser closed its test connection")
            length += byte
        remaining = int(length[:-1])
        body = b""
        while len(body) < remaining:
            body += self.connection.recv(remaining - len(body))
        return json.loads(body)

    def command(self, name, params=None):
        self.sequence += 1
        message = json.dumps([0, self.sequence, name, params or {}]).encode()
        self.connection.sendall(str(len(message)).encode() + b":" + message)
        kind, sequence, error, result = self.receive()
        assert kind == 1 and sequence == self.sequence, (kind, sequence)
        assert error is None, error
        return result.get("value", result) if isinstance(result, dict) else result

    def script(self, script):
        return self.command("WebDriver:ExecuteScript", {"script": script, "args": [], "newSandbox": False, "sandbox": "default"})


def set_browser_cursor(browser, style):
    # Keep the cursor target over the entire viewport at every scale, including
    # empty page margins where Firefox would otherwise choose its own arrow.
    browser.script(f'''let area=document.getElementById('cursor-test');
        if (!area) {{area=document.createElement('div');area.id='cursor-test';document.body.append(area);}}
        Object.assign(area.style,{{position:'fixed',inset:'0',zIndex:'2147483647',cursor:{json.dumps(style)}}});return true''')


def cursor_hidden(control):
    state = control()
    return state['cursor']['kind'] == 'hidden' or (state['cursor']['kind'] == 'surface'
                                                  and state['cursor_rendered_elements'] == 0)


def run():
    ensure_test_display()
    os.chdir(ROOT)
    base = ROOT / ".local/compositor-tests"
    base.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix="run-", dir=base))
    original = {window["id"]: window["pid"] for window in parent_windows()}
    (artifacts / "parent-before.json").write_text(json.dumps(original))
    previous_focus = next((window["id"] for window in parent_windows() if window["is_focused"]), None)
    control = Control(artifacts / "control.sock")
    checks = []
    print(f"Artifacts: {artifacts}", flush=True)
    browser = None
    with (artifacts / "session.log").open("w") as log:
        process = subprocess.Popen([str(BINARY), "--no-clients", "--test-input", "--config", str(artifacts / 'config.toml'), "--control-socket", control.path, "--close-after", "180", "--report", str(artifacts / "state.json")], stdout=log, stderr=log)
        try:
            wait_for(control, description="compositor control socket")
            own = wait_for(lambda: next((window for window in parent_windows() if window['id'] not in original and window.get('app_id') == 'ohmansy-compositor'), None), description="test window")
            if own["is_focused"] and previous_focus in {window["id"] for window in parent_windows()}:
                focus_parent_window(previous_focus)
            control("terminal")
            terminal = wait_for(lambda: window_for(control, "ohmansy-nested-client"), description="terminal")
            terminal_width = terminal["width"]

            editor_environment = {f"XDG_{kind}_HOME": str(artifacts / f"editor-{kind.lower()}") for kind in ("DATA", "CONFIG", "STATE", "CACHE")}
            control("launch", program="gnome-text-editor", args=["--standalone"], env=editor_environment)
            editor = wait_for(lambda: window_for(control, "org.gnome.TextEditor"), description="GTK editor")

            with socket.socket() as reservation:
                reservation.bind(("127.0.0.1", 0))
                port = reservation.getsockname()[1]
            profile = artifacts / "firefox"
            profile.mkdir(mode=0o700)
            preferences = {
                "marionette.port": port,
                "browser.shell.checkDefaultBrowser": False,
                "browser.aboutwelcome.enabled": False,
                "browser.startup.homepage_override.mstone": "ignore",
                "startup.homepage_welcome_url": "",
                "startup.homepage_welcome_url.additional": "",
                "browser.startup.homepage_override_url": "",
                "browser.startup.page": 0,
            }
            (profile / "user.js").write_text("".join(f"user_pref({json.dumps(key)}, {json.dumps(value)});\n" for key, value in preferences.items()))
            page = (ROOT / "nix/compositor/demo.html").as_uri()
            control("launch", program="firefox", args=["--no-remote", "--profile", str(profile), "--marionette", page])
            firefox = wait_for(lambda: window_for(control, "firefox"), timeout=35, description="Firefox window")
            browser = wait_for(lambda: Marionette(port), timeout=20, description="isolated browser automation")
            browser.command("WebDriver:Navigate", {"url": page})
            wait_for(lambda: browser.script("return document.querySelector('#clipboard') !== null"), description="browser page")
            wait_for(lambda: browser.script("return window.devicePixelRatio") == control()['display_scale'], description='monitor-matched Firefox density')
            control("focus", firefox["id"])
            browser.script("document.querySelector('#clipboard').value='';document.querySelector('#clipboard').focus();return true")
            keys(control, process.pid, firefox["id"], [35], gui_only=True)
            wait_for(lambda: browser.script("return document.querySelector('#clipboard').value") == "h", timeout=3, description="initial native browser typing")
            wait_for(lambda: control()["dmabuf_imports"] > 0, description="GPU buffer imports")
            assert window_for(control, "ohmansy-nested-client")["width"] == terminal_width
            checks.append("Firefox, GTK editor, terminal, GPU imports, and monitor-matched rendering")

            widths = {window["id"]: window["width"] for window in control()["windows"]}
            control("terminal")
            control("terminal")
            wait_for(lambda: len(control()["windows"]) == 5, description="five live columns")
            assert all(next(window for window in control()["windows"] if window["id"] == ident)["width"] == width for ident, width in widths.items())
            keys(control, process.pid, firefox["id"], [35], ("super", "alt"))
            wait_for(lambda: control()["focused"] == editor["id"], description="Super+Alt+H directional focus")
            keys(control, process.pid, editor["id"], [38], ("super", "alt"))
            wait_for(lambda: control()["focused"] == firefox["id"], description="Super+Alt+L directional focus")
            before = control()
            control("resize", -80)
            after = control()
            assert next(window for window in after["windows"] if window["id"] == firefox["id"])["width"] == next(window for window in before["windows"] if window["id"] == firefox["id"])["width"] - 80
            control("move-next")
            control("move-prev")
            checks.append("persistent widths, scrolling, directional keyboard focus, resize, and reorder")

            control("move-workspace", 2)
            control("workspace", 2)
            assert control()["focused"] == firefox["id"]
            control("fullscreen")
            assert control()["fullscreen"] == firefox["id"]
            control("fullscreen")
            assert control()["fullscreen"] is None
            control('fullscreen')
            cursor_svg = '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><path fill="#ff00ff" d="M0 0h32v8H8v24H0z"/></svg>'
            cursor_css = 'url("data:image/svg+xml,' + quote(cursor_svg) + '") 0 0, crosshair'
            set_browser_cursor(browser, cursor_css)
            viewport = control()['viewport_size']
            control('pointer', x=viewport[0]-120, y=viewport[1]*.6)
            wait_for(lambda: control()['cursor']['kind'] == 'surface' and control()['cursor_rendered_elements'] > 0, description='custom browser cursor')
            old = control()
            cursor_pixels = [value * old['display_scale'] for value in old['pointer_position']]
            control('scale', 150)
            assert control()["display_scale"] == 1.5
            wait_for(lambda: abs(control()["viewport"] - control()["viewport_target"]) < 1, description="viewport animation")
            scaled = control()
            control('screenshot', path=str(artifacts / 'scaled-cursor.png'))
            wait_for(lambda: (artifacts / 'scaled-cursor.png').exists(), description='scaled cursor screenshot')
            assert all(abs(position * scaled['display_scale'] - pixel) < 2 for position, pixel in zip(scaled['pointer_position'], cursor_pixels)), 'Scaling moved the cursor away from its physical position'
            assert all(0 <= position < bound for position, bound in zip(scaled['pointer_position'], scaled['viewport_size'])), 'Scaling pushed the cursor offscreen'
            assert scaled['cursor']['kind'] != 'hidden'
            if scaled['cursor']['kind'] == 'surface':
                assert scaled['cursor']['alive'] and scaled['cursor_rendered_elements'] > 0
            for expected in [1.75, 2.0, 1.0, 1.25, 1.5]:
                control('scale', round(expected * 100))
                wait_for(lambda: control()['display_scale'] == expected
                         and all(abs(position * expected - pixel) < 2 for position, pixel in zip(control()['pointer_position'], cursor_pixels)),
                         description='cursor remains at the same pixel across scale cycle')
                wait_for(lambda: abs(browser.script("return window.devicePixelRatio") - expected) < .02,
                         description=f'browser finishes rendering at {expected}')
                print('Scale cycle:', expected, 'cursor:', control()['cursor'],
                      'elements:', control()['cursor_rendered_elements'], flush=True)
                wait_for(lambda: control()['cursor']['kind'] == 'surface'
                         and control()['cursor']['alive'] and control()['cursor_rendered_elements'] > 0,
                         description='custom cursor remains rendered')
            set_browser_cursor(browser, 'none')
            wait_for(lambda: cursor_hidden(control), description='intentional cursor hiding')
            set_browser_cursor(browser, cursor_css)
            position = control()['pointer_position']
            control('pointer', x=position[0]-1, y=position[1])
            wait_for(lambda: control()['cursor']['kind'] == 'surface' and control()['cursor_rendered_elements'] > 0, description='restored custom cursor')
            checks.append('custom cursor stays visible and physically stationary through 100–200% scale cycles; intentional hiding is preserved')
            browser.script('document.getElementById("cursor-test").remove();return true')
            control('fullscreen')
            wait_for(lambda: browser.script("return window.devicePixelRatio") == 1.5, description='150% browser density')
            # Exercise the real keyboard binding and retain the existing 5% steps.
            keys(control, process.pid, firefox['id'], [12], ('super', 'alt'))
            wait_for(lambda: control()['display_scale'] == 1.45, description='5% scale decrease')
            # Firefox quantizes CSS devicePixelRatio through its layout units.
            # Check that it follows the change without requiring exact CSS DPR.
            wait_for(lambda: 1.4 < browser.script("return window.devicePixelRatio") < 1.5, description='145% browser density')
            print('145% Firefox CSS DPR:', browser.script("return window.devicePixelRatio"), flush=True)
            keys(control, process.pid, firefox['id'], [13], ('super', 'alt'))
            wait_for(lambda: control()['display_scale'] == 1.5 and browser.script("return window.devicePixelRatio") == 1.5, description='5% scale increase')
            checks.append("workspaces, fullscreen, and 5% keyboard steps update browser density")

            keys(control, process.pid, firefox["id"], [], gui_only=True)
            browser.script("document.querySelector('#choice').focus(); return true")
            control.send_keys([57])
            wait_for(lambda: browser.script("return document.querySelector('#choice').matches(':open')"), timeout=5, description="browser dropdown")
            control("screenshot", path=str(artifacts / "popup.png"))
            control.send_keys([108, 28])
            wait_for(lambda: browser.script("return document.querySelector('#choice').selectedIndex") == 1, description="popup keyboard selection")
            wait_for(lambda: not browser.script("return document.querySelector('#choice').matches(':open')"), description="dropdown closing")
            time.sleep(.3)
            rect = browser.script("const r=document.querySelector('#choice').getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2,chrome:outerHeight-innerHeight}")
            window_state = next(window for window in control()["windows"] if window["id"] == firefox["id"])
            geometry = window_state["geometry"]
            shadow_height = window_state["surface_size"][1] - window_state["client_geometry"][3]
            control("pointer", x=geometry[0]+rect["x"], y=geometry[1]+rect["chrome"]-shadow_height+rect["y"])
            control("button", pressed=True)
            control("button", pressed=False)
            wait_for(lambda: browser.script("return document.querySelector('#choice').matches(':open')"), timeout=5, description="pointer dropdown opening")
            control.send_keys([103, 28])
            wait_for(lambda: browser.script("return document.querySelector('#choice').selectedIndex") == 0, description="pointer-opened dropdown selection")

            popup_events = control()["popup_events"]
            keys(control, process.pid, editor["id"], [68], gui_only=True)
            wait_for(lambda: control()["popup_events"] > popup_events, timeout=5, description="GTK native menu")
            assert control()["popup_grabs"] > 0
            control.send_keys([1])
            wait_for(lambda: abs(control()["viewport"] - control()["viewport_target"]) < 1, description="editor viewport")
            editor_geometry = next(window for window in control()["windows"] if window["id"] == editor["id"])["geometry"]
            control("pointer", x=editor_geometry[0]+editor_geometry[2]/2, y=editor_geometry[1]+editor_geometry[3]/2)
            control("button", pressed=True)
            control("button", pressed=False)
            control("screenshot", path=str(artifacts / "editor.png"))
            checks.append("browser subsurface menus, pointer input, GTK popups, grabs, and selection")

            text = "browser clipboard check"
            control("focus", firefox["id"])
            browser.script(f"const field=document.querySelector('#clipboard');field.value={json.dumps(text)};field.focus();field.select();return true")
            keys(control, process.pid, firefox["id"], [46], ("super", "alt"), gui_only=True)
            keys(control, process.pid, editor["id"], [30], ("ctrl",), gui_only=True)
            keys(control, process.pid, editor["id"], [47], ("super", "alt"), gui_only=True)
            keys(control, process.pid, editor["id"], [30], ("ctrl",), gui_only=True)
            keys(control, process.pid, editor["id"], [46], ("super", "alt"), gui_only=True)
            control("focus", firefox["id"])
            browser.script("const field=document.querySelector('#clipboard');field.value='';field.focus();return true")
            keys(control, process.pid, firefox["id"], [47], ("super", "alt"), gui_only=True)
            wait_for(lambda: browser.script("return document.querySelector('#clipboard').value") == text, description="browser/editor clipboard round trip")
            keys(control, process.pid, editor["id"], [30], ("ctrl",), gui_only=True)
            keys(control, process.pid, editor["id"], [35, 18, 38, 38, 24], gui_only=True)
            keys(control, process.pid, editor["id"], [30, 46], ("ctrl",), gui_only=True)
            control("focus", firefox["id"])
            browser.script("document.querySelector('#clipboard').focus();document.querySelector('#clipboard').select();return true")
            keys(control, process.pid, firefox["id"], [47], ("ctrl",), gui_only=True)
            wait_for(lambda: browser.script("return document.querySelector('#clipboard').value") == "hello", description="native GTK typing and copy")
            checks.append("GUI typing, Super copy/paste and ordinary Ctrl clipboard shortcuts between GTK and Firefox")

            control("screenshot", path=str(artifacts / "desktop.png"))
            wait_for(lambda: (artifacts / "desktop.png").exists(), description="rendered desktop image")
            set_browser_cursor(browser, cursor_css)
            geometry = next(window for window in control()['windows'] if window['id'] == firefox['id'])['geometry']
            control('pointer', x=geometry[0]+geometry[2]/2, y=geometry[1]+geometry[3]/2)
            wait_for(lambda: control()['cursor']['kind'] == 'surface' and control()['cursor_rendered_elements'] > 0, description='cursor owned by closing browser')
            control('close')
            wait_for(lambda: not window_for(control, 'firefox'), description='closing cursor owner')
            wait_for(lambda: control()['cursor']['kind'] == 'named', description='default cursor after owner exits')
            browser.connection.close()
            browser = None
            checks.append('default cursor recovers when the client owning its surface exits')
            control("workspace", 4)
            time.sleep(2)
            idle_frames = control()["rendered_frames"]
            time.sleep(1)
            assert control()["rendered_frames"] - idle_frames <= 1, "Empty workspace keeps redrawing"
            checks.append("idle rendering stops on an empty workspace")
            control("workspace", 2)
            state = control()
            assert state["dmabuf_failures"] == 0
            (artifacts / "verification.json").write_text(json.dumps({"checks": checks, "state": state}, indent=2) + "\n")
        finally:
            if browser:
                browser.connection.close()
            try:
                control("quit")
            except (OSError, AssertionError, ValueError):
                pass
            try:
                process.wait(timeout=12)
            except subprocess.TimeoutExpired:
                raise AssertionError(f"Test compositor did not exit; left PID {process.pid} alone. See {artifacts}")
            remaining = {window["id"]: window["pid"] for window in parent_windows()}
            (artifacts / "parent-after.json").write_text(json.dumps(remaining))
            changed = {ident: pid for ident, pid in original.items() if remaining.get(ident) != pid}
            assert not changed, f"Original desktop windows changed during trial: {changed}"
    assert process.returncode == 0
    for check in checks:
        print(f"PASS: {check}")
    print("PASS: original desktop windows preserved; test compositor exited cleanly")


if __name__ == "__main__":
    run()
