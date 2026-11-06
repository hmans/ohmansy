"""Exercise preview lifecycle with real subprocesses and a fake compositor; no GPU."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import runpy

SCRIPT = Path(__file__).resolve().parents[1] / 'dev/shine-dev.py'


class ShineDevelopmentTests(unittest.TestCase):
    def test_altgr_parent_uses_control_option_without_changing_its_layout(self):
        select = runpy.run_path(str(SCRIPT))['modifier_for']
        parent = {'preferences': {'input': {'keyboard': {'layout': 'eu', 'options': 'lv3:lalt_switch'}}}}
        self.assertEqual(select(parent), 'ctrl-alt')
        self.assertEqual(select(parent, 'super-alt'), 'super-alt')
        self.assertEqual(select({}), 'super-alt')
        self.assertEqual(parent['preferences']['input']['keyboard']['options'], 'lv3:lalt_switch')

    def test_build_failure_preserves_preview_shader_edits_skip_build_and_rust_restarts_only_preview(self):
        with tempfile.TemporaryDirectory(prefix='shine-dev-check-') as temporary:
            root = Path(temporary)
            source = root / 'nix/compositor/src'
            source.mkdir(parents=True)
            rust = source / 'main.rs'
            rust.write_text('valid')
            (source.parent / 'Cargo.toml').write_text('fixture')
            (source.parent / 'Cargo.lock').write_text('fixture')
            tools = root / 'tools'
            tools.mkdir()
            runtime = root / 'runtime'
            runtime.mkdir()
            target = root / 'target/debug'
            target.mkdir(parents=True)
            events = root / 'events.jsonl'

            def executable(path, code):
                path.write_text(f'#!{sys.executable}\n' + code)
                path.chmod(0o700)

            executable(tools / 'mise', '''import json, os
from pathlib import Path
text = Path('nix/compositor/src/main.rs').read_text()
with open(os.environ['FIXTURE_EVENTS'], 'a') as f:
    f.write(json.dumps({'event':'build','text':text})+'\\n')
raise SystemExit(1 if text == 'broken' else 0)
''')
            executable(tools / 'dbus-run-session', '''import os,sys
assert sys.argv[1] == '--'
os.execv(sys.argv[2], sys.argv[2:])
''')
            executable(target / 'ohmansy-compositor', '''import json,os,socket,sys
def record(event):
    with open(os.environ['FIXTURE_EVENTS'],'a') as f: f.write(json.dumps(event)+'\\n')
args=sys.argv[1:]
path=args[args.index('--control-socket')+1]
assert args[args.index('--backend')+1]=='winit'
assert args[args.index('--mod-key')+1]=='super-alt'
assert os.environ['OHMANSY_REQUIRE_HARDWARE_RENDERER']=='1'
assert os.environ['OHMANSY_SHINE_SHADER_DIR'].endswith('/nix/compositor/src')
record({'event':'start','pid':os.getpid()})
with socket.socket(socket.AF_UNIX) as listener:
    listener.bind(path); listener.listen()
    while True:
        connection,_=listener.accept()
        with connection:
            request=json.loads(connection.makefile('rb').readline())
            state={'pid':os.getpid(),'wayland_display':'fixture-wayland','graphics':{'acceleration':os.environ.get('FIXTURE_ACCELERATION','hardware'),'renderer':'Fixture GPU','device':'fixture'}}
            connection.sendall(json.dumps({'ok':True,'state':state}).encode()+b'\\n')
        if request['action']=='quit':
            record({'event':'quit','pid':os.getpid()});break
''')
            env = {**os.environ, 'PATH': str(tools)+os.pathsep+os.environ['PATH'],
                   'CARGO_TARGET_DIR': str(root / 'target'), 'XDG_RUNTIME_DIR': str(runtime),
                   'FIXTURE_EVENTS': str(events)}
            env.pop('OHMANSY_COMPOSITOR_CONTROL', None)
            launcher = ('import runpy; from pathlib import Path; '
                        f'module=runpy.run_path({str(SCRIPT)!r}); '
                        f'raise SystemExit(module["run"](Path({str(root)!r})))')

            def records():
                return [json.loads(line) for line in events.read_text().splitlines()] if events.exists() else []

            def wait_for(predicate):
                deadline = time.monotonic()+15
                while time.monotonic() < deadline:
                    if result := predicate():
                        return result
                    time.sleep(.05)
                self.fail('Timed out: '+(root / 'watcher.log').read_text())

            with (root / 'watcher.log').open('w') as log:
                watcher = subprocess.Popen([sys.executable, '-c', launcher], env=env,
                                           stdout=log, stderr=subprocess.STDOUT)
                try:
                    connection = root / '.local/shine-dev/connection.json'
                    wait_for(connection.exists)
                    first = json.loads(connection.read_text())['pid']
                    (source / 'frame.frag').write_text('shader-only edit')
                    time.sleep(.8)
                    self.assertEqual(len([e for e in records() if e['event']=='build']), 1)
                    rust.write_text('broken')
                    wait_for(lambda: any(e.get('text')=='broken' for e in records()))
                    time.sleep(.3)
                    self.assertEqual(json.loads(connection.read_text())['pid'], first)
                    self.assertFalse(any(e['event']=='quit' for e in records()))
                    rust.write_text('fixed')
                    wait_for(lambda: len([e for e in records() if e['event']=='start'])==2)
                    wait_for(lambda: json.loads(connection.read_text())['pid'] != first)
                    self.assertIn({'event':'quit','pid':first}, records())
                    watcher.send_signal(signal.SIGINT)
                    self.assertEqual(watcher.wait(timeout=10), 0)
                    self.assertFalse(connection.exists())
                    self.assertEqual(len([e for e in records() if e['event']=='quit']), 2)
                    # A compositor reporting software rendering must be stopped.
                    rejected = subprocess.run([sys.executable, '-c', launcher],
                        env={**env, 'FIXTURE_ACCELERATION':'software'}, stdout=log,
                        stderr=subprocess.STDOUT, timeout=15)
                    self.assertNotEqual(rejected.returncode, 0)
                    self.assertIn('did not verify hardware rendering', (root / 'watcher.log').read_text())
                finally:
                    if watcher.poll() is None:
                        watcher.send_signal(signal.SIGTERM)
                        watcher.wait(timeout=10)


if __name__ == '__main__':
    unittest.main()
