{ pkgs }:
let
  python = pkgs.python3.withPackages (p: [ p.dbus-next ]);
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
    # Disposable VM fixture only; no real account credential or host keyring.
    printf shinefixture | ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --unlock >/dev/null
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
    security.polkit.enable = true;
    users.users.alice = { isNormalUser = true; uid = 1000; linger = true; };
    services.gnome.gnome-keyring.enable = true;
    security.pam.services.greetd.enableGnomeKeyring = true;
    fonts.packages = [ pkgs.dejavu_fonts ];
    environment.systemPackages = [ pkgs.foot pkgs.python3 pkgs.kbd pkgs.openssh ];
    services.greetd = {
      enable = true;
      settings = let
        command = "${import ../modules/compositor-session-package.nix { inherit pkgs; }}/bin/ohmansy-compositor-session --no-clients --control-socket /run/user/1000/shine.sock";
      in {
        initial_session = { user = "alice"; inherit command; };
        default_session = { user = "alice"; command = "${pkgs.coreutils}/bin/sleep infinity"; };
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
    assert len(control()['windows']) == 1, control()
    # Type a public fixture password into the VM's standard keyring dialog.
    machine.send_chars('shinefixture')
    machine.send_key('ret')
    machine.wait_for_file('/run/user/1000/shine-keyring-unlocked', timeout=20)
    as_user('set +e; SSH_AUTH_SOCK=/run/user/1000/gcr/ssh ssh-add -l >/dev/null; result=$?; test "$result" = 1')
    control("launch", program="foot", args=["--app-id=shine-drm-first", "sleep", "300"])
    machine.wait_until_succeeds("pgrep foot")
    import time
    for attempt in range(100):
        state = control()
        if len(state["windows"]) == 1 and state["rendered_frames"] > 2:
            break
        time.sleep(.1)
    assert len(state["windows"]) == 1, state
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
    machine.send_key("meta_l-dot")
    for attempt in range(100):
        state = control()
        if state["active_output"] == state["outputs"][1]["name"]:
            break
        time.sleep(.1)
    assert state["active_output"] == state["outputs"][1]["name"], state
    assert all(w["render_density"] == 2 for w in state["windows"]), state
    machine.send_key("ctrl-alt-f2")
    try:
        machine.wait_until_succeeds("test $(cat /sys/class/tty/tty0/active) = tty2", timeout=15)
    except Exception:
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
    time.sleep(.5)
    machine.screenshot("shine-two-monitors")
    control("quit")
    machine.wait_until_succeeds('test ! -e /run/user/1000/shine.sock', timeout=15)
    for attempt in range(100):
        environment = manager_environment()
        if 'WAYLAND_DISPLAY' not in environment:
            break
        time.sleep(.1)
    assert 'WAYLAND_DISPLAY' not in environment, environment
    assert 'XDG_CURRENT_DESKTOP' not in environment, environment
  '';
}
