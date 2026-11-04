#!/usr/bin/env python3
"""Exercise disposable native clients in a nested compositor on a Niri desktop.

All window operations target the test compositor's private socket. Keyboard
events use a test-only path into the compositor's normal key handler. They do
not touch the parent desktop's input devices. No terminal command text is typed.
Original desktop window identities are checked after clean shutdown.
"""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / ".build/spatial/debug/ohmansy-compositor"
TEST_CONTROL = None


def send_keys(keycodes, modifiers=()):
    assert TEST_CONTROL is not None
    held = [{"ctrl": 29, "alt": 56, "shift": 42}[modifier] for modifier in modifiers]
    for code in held:
        TEST_CONTROL("key", code=code, pressed=True)
    for code in keycodes:
        TEST_CONTROL("key", code=code, pressed=True)
        time.sleep(.05)
        TEST_CONTROL("key", code=code, pressed=False)
        time.sleep(.15)
    for code in reversed(held):
        TEST_CONTROL("key", code=code, pressed=False)
    time.sleep(.1)


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
    return json.loads(subprocess.check_output(["niri", "msg", "--json", "windows"]))


class Control:
    def __init__(self, path):
        self.path = str(path)

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


def window_for(control, app):
    return next((window for window in control()["windows"] if window["app_id"] == app), None)


def keys(control, pid, window_id, keycodes, modifiers=(), gui_only=False):
    state = control("focus", window_id)
    assert state["pid"] == pid
    focused = next(window for window in state["windows"] if window["id"] == state["focused"])
    if gui_only:
        assert focused["app_id"] in {"firefox", "org.gnome.TextEditor"}, focused
    selection_updates = state["selection_updates"]
    send_keys(keycodes, modifiers)
    if "ctrl" in modifiers and 46 in keycodes:
        wait_for(lambda: control()["selection_updates"] > selection_updates, description="clipboard publication")


def run():
    global TEST_CONTROL
    os.chdir(ROOT)
    base = ROOT / ".local/compositor-tests"
    base.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix="run-", dir=base))
    original = {window["id"]: window["pid"] for window in parent_windows()}
    (artifacts / "parent-before.json").write_text(json.dumps(original))
    previous_focus = next((window["id"] for window in parent_windows() if window["is_focused"]), None)
    control = Control(artifacts / "control.sock")
    TEST_CONTROL = control
    checks = []
    print(f"Artifacts: {artifacts}", flush=True)
    browser = None
    with (artifacts / "session.log").open("w") as log:
        process = subprocess.Popen([str(BINARY), "--no-clients", "--test-input", "--control-socket", control.path, "--close-after", "180", "--report", str(artifacts / "state.json")], stdout=log, stderr=log)
        try:
            wait_for(control, description="compositor control socket")
            own = wait_for(lambda: next((window for window in parent_windows() if window.get("pid") == process.pid), None), description="test window")
            if own["is_focused"] and previous_focus in {window["id"] for window in parent_windows()}:
                subprocess.run(["niri", "msg", "action", "focus-window", "--id", str(previous_focus)], check=True, stdout=subprocess.DEVNULL)
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
            assert browser.script("return window.devicePixelRatio") == 2
            control("focus", firefox["id"])
            browser.script("document.querySelector('#clipboard').value='';document.querySelector('#clipboard').focus();return true")
            keys(control, process.pid, firefox["id"], [35], gui_only=True)
            wait_for(lambda: browser.script("return document.querySelector('#clipboard').value") == "h", timeout=3, description="initial native browser typing")
            wait_for(lambda: control()["dmabuf_imports"] > 0, description="GPU buffer imports")
            assert window_for(control, "ohmansy-nested-client")["width"] == terminal_width
            checks.append("Firefox, GTK editor, terminal, GPU imports, and 2x rendering")

            widths = {window["id"]: window["width"] for window in control()["windows"]}
            control("terminal")
            control("terminal")
            wait_for(lambda: len(control()["windows"]) == 5, description="five live columns")
            assert all(next(window for window in control()["windows"] if window["id"] == ident)["width"] == width for ident, width in widths.items())
            keys(control, process.pid, firefox["id"], [35], ("ctrl", "alt"))
            wait_for(lambda: control()["focused"] == editor["id"], description="Ctrl+Alt+H directional focus")
            keys(control, process.pid, editor["id"], [38], ("ctrl", "alt"))
            wait_for(lambda: control()["focused"] == firefox["id"], description="Ctrl+Alt+L directional focus")
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
            keys(control, process.pid, firefox["id"], [31], ("ctrl", "alt"))
            assert control()["display_scale"] == 1.5, "Ctrl+Alt+S must cycle display scale"
            wait_for(lambda: abs(control()["viewport"] - control()["viewport_target"]) < 1, description="viewport animation")
            assert browser.script("return window.devicePixelRatio") == 2
            checks.append("workspaces, fullscreen, and 150% presentation with 2x browser content")

            keys(control, process.pid, firefox["id"], [], gui_only=True)
            browser.script("document.querySelector('#choice').focus(); return true")
            send_keys([57])
            wait_for(lambda: browser.script("return document.querySelector('#choice').matches(':open')"), timeout=5, description="browser dropdown")
            control("screenshot", path=str(artifacts / "popup.png"))
            send_keys([108, 28])
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
            send_keys([103, 28])
            wait_for(lambda: browser.script("return document.querySelector('#choice').selectedIndex") == 0, description="pointer-opened dropdown selection")

            popup_events = control()["popup_events"]
            keys(control, process.pid, editor["id"], [68], gui_only=True)
            wait_for(lambda: control()["popup_events"] > popup_events, timeout=5, description="GTK native menu")
            assert control()["popup_grabs"] > 0
            send_keys([1])
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
            keys(control, process.pid, firefox["id"], [46], ("ctrl",), gui_only=True)
            keys(control, process.pid, editor["id"], [30, 47, 30, 46], ("ctrl",), gui_only=True)
            control("focus", firefox["id"])
            browser.script("const field=document.querySelector('#clipboard');field.value='';field.focus();return true")
            keys(control, process.pid, firefox["id"], [47], ("ctrl",), gui_only=True)
            wait_for(lambda: browser.script("return document.querySelector('#clipboard').value") == text, description="browser/editor clipboard round trip")
            keys(control, process.pid, editor["id"], [30], ("ctrl",), gui_only=True)
            keys(control, process.pid, editor["id"], [35, 18, 38, 38, 24], gui_only=True)
            keys(control, process.pid, editor["id"], [30, 46], ("ctrl",), gui_only=True)
            control("focus", firefox["id"])
            browser.script("document.querySelector('#clipboard').focus();document.querySelector('#clipboard').select();return true")
            keys(control, process.pid, firefox["id"], [47], ("ctrl",), gui_only=True)
            wait_for(lambda: browser.script("return document.querySelector('#clipboard').value") == "hello", description="native GTK typing and copy")
            checks.append("GUI typing and clipboard in both directions between GTK and Firefox")

            control("screenshot", path=str(artifacts / "desktop.png"))
            wait_for(lambda: (artifacts / "desktop.png").exists(), description="rendered desktop image")
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
