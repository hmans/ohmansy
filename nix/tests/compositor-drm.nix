{ pkgs }:
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
    users.users.alice = { isNormalUser = true; uid = 1000; };
    fonts.packages = [ pkgs.dejavu_fonts ];
    environment.systemPackages = [ pkgs.foot pkgs.python3 pkgs.kbd ];
    services.greetd = {
      enable = true;
      settings = let
        command = "${import ../modules/compositor-package.nix { inherit pkgs; }}/bin/ohmansy-compositor --backend drm --no-clients --mod-key super --control-socket /run/user/1000/shine.sock";
      in {
        initial_session = { user = "alice"; inherit command; };
        default_session = { user = "alice"; inherit command; };
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
  '';
}
