{ pkgs }:
let
  python = pkgs.python3.withPackages (p: [ p.dbus-next p.evdev ]);
  touchpadFixture = pkgs.writeText "shine-touchpad-fixture.py" ''
    import time
    from evdev import UInput, AbsInfo, ecodes as e
    capabilities = {
        e.EV_KEY: [e.BTN_LEFT, e.BTN_TOUCH, e.BTN_TOOL_FINGER, e.BTN_TOOL_DOUBLETAP, e.BTN_TOOL_TRIPLETAP],
        e.EV_ABS: [
            (e.ABS_X, AbsInfo(0, 0, 2000, 0, 0, 20)),
            (e.ABS_Y, AbsInfo(0, 0, 1200, 0, 0, 20)),
            (e.ABS_MT_SLOT, AbsInfo(0, 0, 4, 0, 0, 0)),
            (e.ABS_MT_TRACKING_ID, AbsInfo(0, 0, 65535, 0, 0, 0)),
            (e.ABS_MT_POSITION_X, AbsInfo(0, 0, 2000, 0, 0, 20)),
            (e.ABS_MT_POSITION_Y, AbsInfo(0, 0, 1200, 0, 0, 20)),
        ],
    }
    with UInput(capabilities, name='Shine fixture touchpad', input_props=[e.INPUT_PROP_POINTER, e.INPUT_PROP_BUTTONPAD]):
        while True:
            time.sleep(1)
  '';
  probe = pkgs.writeText "shine-keyring-probe.py" ''
    import asyncio
    import json
    import os
    from pathlib import Path
    from dbus_next.aio import MessageBus

    runtime = Path(os.environ['XDG_RUNTIME_DIR'])
    keys = ['DBUS_SESSION_BUS_ADDRESS', 'WAYLAND_DISPLAY', 'SSH_AUTH_SOCK']
    (runtime / 'shine-child-env.json').write_text(json.dumps({k: os.environ.get(k) for k in keys}))

    async def main():
        bus = await MessageBus().connect()
        name = 'org.freedesktop.secrets'
        root = '/org/freedesktop/secrets'
        intro = await bus.introspect(name, root)
        service = bus.get_proxy_object(name, root, intro).get_interface('org.freedesktop.Secret.Service')
        path = await service.call_read_alias('default')
        assert path != '/', 'Fixture login keyring was not created'
        await service.call_lock([path])
        unlocked, prompt_path = await service.call_unlock([path])
        assert prompt_path != '/', 'Locked fixture must require a real graphical prompt'
        intro = await bus.introspect(name, prompt_path)
        prompt = bus.get_proxy_object(name, prompt_path, intro).get_interface('org.freedesktop.Secret.Prompt')
        done = asyncio.get_running_loop().create_future()
        prompt.on_completed(lambda dismissed, result: done.set_result(dismissed))
        await prompt.call_prompt("")
        assert not await asyncio.wait_for(done, timeout=30), 'Prompt dismissed'
        intro = await bus.introspect(name, path)
        props = bus.get_proxy_object(name, path, intro).get_interface('org.freedesktop.DBus.Properties')
        assert not (await props.call_get('org.freedesktop.Secret.Collection', 'Locked')).value
        (runtime / 'shine-keyring-unlocked').touch()
        bus.disconnect()

    asyncio.run(main())
  '';
  keyringTrial = pkgs.writeShellScript "shine-keyring-fixture" ''
    set -eu
    exec ${python}/bin/python3 ${probe}
  '';
in
pkgs.testers.runNixOSTest {
  name = "shine-two-monitors";
  nodes.machine = { ... }: {
    virtualisation.memorySize = 2048;
    virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci,max_outputs=2" ];
    # Headless QEMU only reports its first console connected. Force the second
    # guest connector on so the test exercises two independent KMS scanouts.
    boot.kernelParams = [ "video=Virtual-2:1280x800@60e" ];
    hardware.graphics.enable = true;
    hardware.uinput.enable = true;
    services.udev.extraRules = ''
      SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Shine fixture touchpad", ENV{ID_INPUT}="1", ENV{ID_INPUT_TOUCHPAD}="1", ENV{ID_INPUT_MOUSE}="0", ENV{ID_INPUT_TOUCHSCREEN}="0"
    '';
    systemd.services.shine-touchpad-fixture = {
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" "systemd-udevd.service" ];
      serviceConfig.ExecStart = "${python}/bin/python3 ${touchpadFixture}";
    };
    security.polkit.enable = true;
    users.users.alice = { isNormalUser = true; uid = 1000; linger = true; initialPassword = "shinefixture"; };
    services.gnome.gnome-keyring.enable = true;
    security.pam.services.greetd.enableGnomeKeyring = true;
    fonts.packages = [ pkgs.dejavu_fonts ];
    environment.systemPackages = [ pkgs.foot pkgs.python3 pkgs.kbd pkgs.openssh ];
    # Model a portal left running across logout. On restart it cannot become
    # ready until the new compositor dispatches a Wayland round trip. A blocking
    # restart in SESSION_SETUP deadlocks the second login before its event loop.
    systemd.user.services.xdg-desktop-portal = {
      serviceConfig = {
        Type = "notify";
        NotifyAccess = "all";
        TimeoutStartSec = 120;
        ExecStart = pkgs.writeShellScript "shine-portal-readiness-fixture" ''
          set -eu
          ${pkgs.wayland-utils}/bin/wayland-info >/dev/null
          ${pkgs.systemd}/bin/systemd-notify --ready
          exec ${pkgs.coreutils}/bin/sleep infinity
        '';
      };
    };
    services.greetd = {
      enable = true;
      settings = let
        command = "${pkgs.writeShellScript "shine-test-session" ''
          # Seed only this disposable VM's first autologin, before Secret
          # Service initialization. The later password login uses PAM alone.
          if [ ! -f "$HOME/.local/share/keyrings/login.keyring" ]; then
            printf shinefixture | ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --unlock >/dev/null
          fi
          exec ${import ../modules/compositor-session-package.nix { inherit pkgs; }}/bin/ohmansy-compositor-session \
            --no-clients --config /run/user/1000/shine-test.toml \
            --control-socket /run/user/1000/shine.sock 2>/run/user/1000/shine-session.log
        ''}";
      in {
        initial_session = { user = "alice"; inherit command; };
        default_session = { user = "greeter"; command = "${pkgs.greetd}/bin/agreety --cmd ${command}"; };
      };
    };
  };
  testScript = ''
    import json
    start_all()
    machine.wait_for_file("/run/user/1000/shine.sock", timeout=60)
    def control(action="status", value=None, **fields):
        request = dict(action=action, **fields)
        if value is not None:
            request["value"] = value
        script = "import json,socket; s=socket.socket(socket.AF_UNIX); s.connect('/run/user/1000/shine.sock'); s.sendall(" + repr((json.dumps(request)+"\n").encode()) + "); print(s.makefile().readline())"
        import shlex
        response = json.loads(machine.succeed("python3 -c " + shlex.quote(script)))
        assert response["ok"], response
        return response["state"]
    state = control()
    assert state["backend"] == "drm", state
    assert len(state["outputs"]) == 2, state
    # Requesting the current VT must not leave rendering suspended waiting for
    # an activation event that will never arrive.
    frames = state['rendered_frames']
    machine.send_key('ctrl-alt-f1')
    for attempt in range(100):
        state = control()
        if state['rendered_frames'] > frames:
            break
        import time
        time.sleep(.1)
    assert state['rendered_frames'] > frames, state
    import shlex
    def as_user(command):
        return machine.succeed("runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus sh -ec " + shlex.quote(command))
    def manager_environment():
        return dict(line.split('=', 1) for line in as_user('systemctl --user show-environment').splitlines() if '=' in line)
    environment = manager_environment()
    assert environment['WAYLAND_DISPLAY'] == state['wayland_display'], environment
    assert environment['XDG_CURRENT_DESKTOP'] == 'ohmansy', environment
    assert environment['DISPLAY'] == "", environment
    assert environment['SSH_AUTH_SOCK'] == '/run/user/1000/gcr/ssh', environment
    control('launch', program='${keyringTrial}', args=[])
    machine.wait_for_file('/run/user/1000/shine-child-env.json', timeout=15)
    child = json.loads(machine.succeed('cat /run/user/1000/shine-child-env.json'))
    assert child['DBUS_SESSION_BUS_ADDRESS'] == 'unix:path=/run/user/1000/bus', child
    assert child['WAYLAND_DISPLAY'] == state['wayland_display'], child
    assert child['SSH_AUTH_SOCK'] == environment['SSH_AUTH_SOCK'], child
    import time
    for attempt in range(100):
        if len(control()['windows']) == 1:
            break
        time.sleep(.1)
    if len(control()['windows']) != 1:
        print(machine.succeed('cat /run/user/1000/shine-session.log'))
        print(machine.succeed('journalctl -b --no-pager -p warning'))
    assert len(control()['windows']) == 1, control()
    # Type a public fixture password into the VM's standard keyring dialog.
    machine.send_chars('shinefixture')
    machine.send_key('ret')
    machine.wait_for_file('/run/user/1000/shine-keyring-unlocked', timeout=20)
    as_user('set +e; SSH_AUTH_SOCK=/run/user/1000/gcr/ssh ssh-add -l >/dev/null; result=$?; test "$result" = 1')
    def touchpad_options(enabled):
        flag = 'true' if enabled else 'false'
        text = '# Fixture preferences\n[input.keyboard]\nlayout="us"\n[input.touchpad]\ntap=' + flag + '\nnatural_scroll=' + flag + '\n[layout]\ngap=20\n[animations]\nenabled=false\n[bindings]\n"Mod+B"={action="fullscreen"}\n[[window_rules]]\nmatch={app_id="shine-drm-first"}\ndefault_column_width={pixels=700}\n'
        script = 'from pathlib import Path; Path("/run/user/1000/shine-test.toml").write_text(' + repr(text) + ')'
        as_user('python3 -c ' + shlex.quote(script))
        for attempt in range(100):
            state = control()
            pads = [d for d in state['input_devices'] if d['touchpad']]
            if pads and all(d['tap'] == enabled and d['natural_scroll'] == enabled for d in pads):
                return
            time.sleep(.1)
        print(machine.succeed('journalctl -b -u shine-touchpad-fixture --no-pager'))
        print(machine.succeed('cat /run/user/1000/shine-session.log'))
        raise AssertionError(state)
    touchpad_options(True)
    touchpad_options(False)
    touchpad_options(True)
    control("launch", program="foot", args=["--app-id=shine-drm-first", "sleep", "300"])
    machine.wait_until_succeeds("pgrep foot")
    import time
    for attempt in range(100):
        state = control()
        if len(state["windows"]) == 1 and state["rendered_frames"] > 2:
            break
        time.sleep(.1)
    assert len(state["windows"]) == 1, state
    assert state['windows'][0]['width'] == 700, state
    first = state["windows"][0]["id"]
    control("move-output-next")
    state = control()
    assert state["windows"][0]["output"] == state["outputs"][1]["name"], state
    control("scale", 150)
    state = control()
    assert [o["scale"] for o in state["outputs"]] == [1.25, 1.5], state
    control("output", 1)
    control("launch", program="foot", args=["--app-id=shine-drm-second", "sleep", "300"])
    for attempt in range(100):
        state = control()
        if len(state["windows"]) == 2:
            break
        time.sleep(.1)
    assert len(state["windows"]) == 2, state
    assert len({w["output"] for w in state["windows"]}) == 2, state
    machine.send_key('meta_l-b')
    for attempt in range(100):
        state = control()
        if state['fullscreen'] == state['focused']:
            break
        time.sleep(.1)
    assert state['fullscreen'] == state['focused'] and state['focused'] is not None, state
    machine.send_key('meta_l-b')
    for attempt in range(100):
        if control()['fullscreen'] is None:
            break
        time.sleep(.1)
    assert control()['fullscreen'] is None, control()
    control('resize', 2000)
    available = control()['outputs'][0]['work_area'][2] - 2 * control()['preferences']['layout']['gap']
    presets = [max(200, int(available * ratio + .5)) for ratio in [1/3, .5, 2/3]]
    focused = control()['focused']
    for key, expected in [('meta_l-r', presets[0]), ('meta_l-r', presets[1]),
                          ('meta_l-r', presets[2]), ('meta_l-r', presets[0]),
                          ('meta_l-shift-r', presets[2])]:
        machine.send_key(key)
        for attempt in range(100):
            state = control()
            if next(w for w in state['windows'] if w['id'] == focused)['width'] == expected:
                break
            time.sleep(.1)
        assert next(w for w in state['windows'] if w['id'] == focused)['width'] == expected, state
    machine.send_key("meta_l-dot")
    for attempt in range(100):
        state = control()
        if state["active_output"] == state["outputs"][1]["name"]:
            break
        time.sleep(.1)
    assert state["active_output"] == state["outputs"][1]["name"], state
    assert all(w["render_density"] == 2 for w in state["windows"]), state
    identities = {w['id'] for w in state['windows']}
    first_name, second_name = [o['name'] for o in state['outputs']]
    alternate = next(m for m in state['outputs'][1]['modes'] if m['width'] == 1024 and m['height'] == 768)
    control('configure-outputs', outputs=[{'name': second_name, 'mode': f"1024x768@{alternate['refresh']/1000}"}])
    for attempt in range(100):
        state = control()
        if state['outputs'][1]['physical_size'] == [1024, 768]:
            break
        time.sleep(.1)
    assert state['outputs'][1]['physical_size'] == [1024, 768], state
    assert state['config_error'] is None, state
    width = state['outputs'][1]['logical_size'][0]
    control('configure-outputs', outputs=[{'name': first_name, 'position': [width, 0]},
                                         {'name': second_name, 'position': [0, 0], 'primary': True}])
    control('save-config')
    machine.wait_for_file('/run/user/1000/shine-test.toml', timeout=10)
    # Force only guest virtual connectors; no host displays are involved.
    machine.succeed(f"echo off > /sys/class/drm/card0-{second_name}/status")
    # sysfs force changes do not emit a hotplug event by themselves.
    machine.succeed('echo change > /sys/class/drm/card0/uevent')
    for attempt in range(100):
        state = control()
        if len(state['outputs']) == 1:
            break
        time.sleep(.1)
    assert len(state['outputs']) == 1, state
    assert {w['id'] for w in state['windows']} == identities, state
    assert all(w['output'] == first_name for w in state['windows']), state
    machine.succeed(f"echo on > /sys/class/drm/card0-{second_name}/status")
    machine.succeed('echo change > /sys/class/drm/card0/uevent')
    for attempt in range(100):
        state = control()
        if len(state['outputs']) == 2 and state['outputs'][1]['physical_size'] == [1024, 768]:
            break
        time.sleep(.1)
    assert len(state['outputs']) == 2, state
    assert state['outputs'][0]['position'] == [width, 0], state
    assert state['outputs'][1]['position'] == [0, 0] and state['outputs'][1]['primary'], state
    assert state['outputs'][1]['physical_size'] == [1024, 768], state
    assert {w['id'] for w in state['windows']} == identities, state
    machine.send_key("ctrl-alt-f2")
    try:
        machine.wait_until_succeeds("test $(cat /sys/class/tty/tty0/active) = tty2", timeout=15)
    except Exception:
        print(machine.succeed('cat /run/user/1000/shine-session.log'))
        print(machine.succeed("journalctl -b -u greetd --no-pager"))
        print(control())
        raise
    before = control()["rendered_frames"]
    machine.succeed("chvt 1")
    machine.wait_until_succeeds("test $(cat /sys/class/tty/tty0/active) = tty1", timeout=15)
    for attempt in range(100):
        state = control()
        if state["rendered_frames"] > before:
            break
        time.sleep(.1)
    assert state["rendered_frames"] > before, state
    assert first in [w["id"] for w in state["windows"]], state
    # Animate a same-output reorder through native libinput, including its
    # interruption by the reverse shortcut. Client dimensions must stay fixed.
    script = 'from pathlib import Path; p=Path("/run/user/1000/shine-test.toml"); s=p.read_text(); assert "enabled=false" in s; p.write_text(s.replace("enabled=false", "enabled=true\\nduration_ms=1000"))'
    as_user('python3 -c ' + shlex.quote(script))
    for attempt in range(100):
        if control()['preferences']['animations']['enabled']:
            break
        time.sleep(.1)
    assert control()['preferences']['animations']['enabled']
    control('output', 1)
    control('launch', program='foot', args=['--app-id=shine-drm-movement', 'sleep', '120'])
    for attempt in range(100):
        moving_window = next((w for w in control()['windows'] if w['app_id'] == 'shine-drm-movement' and w['surface_size']), None)
        if moving_window:
            break
        time.sleep(.1)
    assert moving_window
    ident = moving_window['id']
    control('focus', ident)
    dimensions = moving_window['client_geometry'][2:]
    machine.send_key('meta_l-shift-left', delay=.15)
    for attempt in range(30):
        state = control()
        if next(w for w in state['windows'] if w['id'] == ident)['moving']:
            break
        time.sleep(.02)
    assert next(w for w in state['windows'] if w['id'] == ident)['moving'], state
    assert state['focused'] == state['keyboard_focus'] == ident, state
    machine.send_key('meta_l-shift-right', delay=.15)
    for attempt in range(100):
        state = control()
        if not any(w['moving'] for w in state['windows']) and state['viewport'] == state['viewport_target']:
            break
        time.sleep(.05)
    assert not any(w['moving'] for w in state['windows']), state
    assert state['viewport'] == state['viewport_target'], state
    assert state['focused'] == state['keyboard_focus'] == ident
    assert next(w for w in state['windows'] if w['id'] == ident)['client_geometry'][2:] == dimensions
    time.sleep(.5)
    machine.screenshot("shine-two-monitors")
    as_user('systemctl --user start xdg-desktop-portal.service')
    assert as_user('systemctl --user is-active xdg-desktop-portal.service').strip() == 'active'
    control("quit")
    machine.wait_until_succeeds('test ! -e /run/user/1000/shine.sock', timeout=15)
    for attempt in range(100):
        environment = manager_environment()
        if 'WAYLAND_DISPLAY' not in environment:
            break
        time.sleep(.1)
    assert 'WAYLAND_DISPLAY' not in environment, environment
    assert 'XDG_CURRENT_DESKTOP' not in environment, environment
    # A real password login must retain PAM's unlock, before any fixture helper
    # can call --unlock. The earlier autologin only tests graphical prompting.
    machine.wait_until_succeeds("grep -aq 'login:' /dev/vcs1", timeout=20)
    machine.send_chars('alice\n')
    machine.wait_until_succeeds("grep -aq 'Password:' /dev/vcs1", timeout=20)
    machine.send_chars('shinefixture\n')
    machine.wait_for_file('/run/user/1000/shine.sock', timeout=30)
    # The socket is created before setup; require an IPC response and shell
    # layers too, proving the event loop and desktop actually started.
    machine.wait_until_succeeds("runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus systemctl --user is-active xdg-desktop-portal.service", timeout=20)
    assert control()['backend'] == 'drm'
    for attempt in range(100):
        state = control()
        if all(any(layer['namespace'] == 'ohmansy-shine-bar' for layer in output['layers'])
            for output in state['outputs']):
            break
        time.sleep(.1)
    assert all(any(layer['namespace'] == 'ohmansy-shine-bar' for layer in output['layers'])
        for output in state['outputs']), state
    # Ask the bus itself, without activating Secret Service as a side effect.
    machine.wait_until_succeeds("runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus sh -c 'busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus NameHasOwner s org.freedesktop.secrets | grep -qx \"b true\"'", timeout=15)
    locked = as_user('busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/login org.freedesktop.Secret.Collection Locked').strip()
    assert locked == 'b false', locked
    # Repeated activation must reach the same initialized daemon and must not
    # prompt or relock the login keyring.
    owner = as_user('busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s org.freedesktop.secrets').strip()
    for attempt in range(3):
        time.sleep(1)
        assert as_user('busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/login org.freedesktop.Secret.Collection Locked').strip() == 'b false'
        assert as_user('busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s org.freedesktop.secrets').strip() == owner
    assert not control()['windows'], control()
    control('quit')
  '';
}
