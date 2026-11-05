{ pkgs }:
let
  python = pkgs.python3.withPackages (p: [ p.pillow ]);
  session = import ../modules/compositor-session-package.nix { inherit pkgs; enableKeyring = false; };
in
pkgs.testers.runNixOSTest {
  name = "shine-screenshots";
  nodes.machine = {
    virtualisation.memorySize = 2048;
    virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci,max_outputs=2" ];
    boot.kernelParams = [ "video=Virtual-2:1280x800@60e" ];
    hardware.graphics.enable = true;
    security.polkit.enable = true;
    users.users.alice = { isNormalUser = true; uid = 1000; };
    fonts.packages = [ pkgs.dejavu_fonts ];
    environment.systemPackages = [ pkgs.foot pkgs.wl-clipboard python ];
    services.greetd = {
      enable = true;
      settings = {
        default_session = { command = "${pkgs.greetd}/bin/agreety --cmd ${session}/bin/ohmansy-compositor-session"; user = "greeter"; };
        initial_session = {
          user = "alice";
          command = "${pkgs.writeShellScript "shine-screenshots-session" ''
            exec ${session}/bin/ohmansy-compositor-session --no-clients \
              --control-socket /run/user/1000/shine.sock --config /run/user/1000/screenshot.toml \
              2>/run/user/1000/screenshot-session.log
          ''}";
        };
      };
    };
    system.stateVersion = "26.05";
  };
  testScript = ''
    import json
    import shlex
    import time

    start_all()
    machine.wait_for_file('/run/user/1000/shine.sock', timeout=60)

    def control(action='status', **fields):
        payload = (json.dumps(dict(action=action, **fields)) + '\n').encode()
        code = "import socket; s=socket.socket(socket.AF_UNIX); s.connect('/run/user/1000/shine.sock'); s.sendall(" + repr(payload) + "); print(s.makefile().readline())"
        reply = json.loads(machine.succeed('python3 -c ' + shlex.quote(code)))
        assert reply['ok'], reply
        return reply['state']

    def wait_for(predicate):
        for attempt in range(100):
            state = control()
            if predicate(state):
                return state
            time.sleep(.1)
        raise AssertionError(state)

    state = wait_for(lambda s: len(s['outputs']) == 2 and all(any(layer['namespace'] == 'ohmansy-shine-bar'
        for layer in o['layers']) for o in s['outputs']))
    assert state['backend'] == 'drm', state
    names = [o['name'] for o in state['outputs']]
    # Keep software-rendered VM captures small and explicitly test mixed scale.
    control('configure-outputs', outputs=[{'name': name, 'mode': '1280x800', 'scale': scale}
                                         for name, scale in zip(names, [1.25, 1.5])])
    wait_for(lambda s: all(o['physical_size'] == [1280, 800] for o in s['outputs']))

    def capture(label, shortcut=False):
        before = control()
        if shortcut:
            machine.send_key('print')
        else:
            control('screenshot-screen', path='/home/alice/' + label + '.png')
        state = wait_for(lambda s: s.get('screenshot') and s['screenshot'] != before.get('screenshot'))
        shot = state['screenshot']
        assert 'error' not in shot and shot['clipboard'], shot
        assert shot['output'] == before['active_output'], shot
        assert state['focused'] == before['focused'], state
        assert state['keyboard_focus'] == before['keyboard_focus'], state
        assert [shot['width'], shot['height']] == [1280, 800], shot
        machine.succeed('runuser -u alice -- env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY='
                        + shlex.quote(state['wayland_display'])
                        + ' wl-paste --no-newline --type image/png > /tmp/copied.png')
        code = ('from pathlib import Path; from PIL import Image; '
                + 'p=Path(' + repr(shot['path']) + '); assert p.read_bytes() == Path("/tmp/copied.png").read_bytes(); '
                + 'im=Image.open(p); assert im.size == (1280,800); '
                + 'assert len(im.getcolors(1280*800)) > 1')
        machine.succeed('python3 -c ' + shlex.quote(code))
        try:
            state = wait_for(lambda s: any(layer['namespace'] == 'ohmansy-screenshot-result'
                for output in s['outputs'] if output['name'] == shot['output']
                for layer in output['layers']))
        except AssertionError:
            print(machine.succeed('cat /run/user/1000/screenshot-session.log'))
            print(machine.succeed('journalctl -b --no-pager -n 100'))
            raise
        assert state['keyboard_focus'] == before['keyboard_focus'], state
        machine.copy_from_vm(shot['path'], 'screenshots')
        return shot

    capture('empty-desktop')
    machine.screenshot('screenshot-result')
    for index in (1, 2):
        control('output', value=index)
        control('launch', program='foot', args=['--app-id=shot-' + str(index), '--override=colors-dark.background=226644', 'sleep', '300'])
        wait_for(lambda s: len(s['windows']) == index)
        capture('monitor-' + str(index))
    capture('print', shortcut=True)
    wait_for(lambda s: not any(s['modifiers'].values()))
    control('fullscreen')
    capture('fullscreen')
    control('fullscreen')
    assert control()['fullscreen'] is None, control()
    machine.screenshot('shine-screenshots')
    control('quit')
  '';
}
