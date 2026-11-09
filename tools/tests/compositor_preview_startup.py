#!/usr/bin/env python3
"""Measure real portal and Quickshell readiness on the preview's private bus."""
import os
from pathlib import Path
import runpy
import signal
import subprocess
import tempfile
import time
import compositor_support as trial


def run():
    trial.ensure_test_display()
    base=trial.ROOT/'.local/compositor-tests'
    base.mkdir(parents=True,exist_ok=True)
    artifacts=Path(tempfile.mkdtemp(prefix='preview-startup-',dir=base))
    print(f'Artifacts: {artifacts}',flush=True)
    prepare=runpy.run_path(str(trial.ROOT/'tools/dev/shine-dev.py'))['preview_environment']
    env=prepare(os.environ,artifacts)
    env['QT_QPA_PLATFORMTHEME']='xdgdesktopportal'
    env['QT_QPA_PLATFORM']='wayland'
    env['OHMANSY_WALLPAPER_IMAGE']=''
    config=artifacts/'config.toml';config.write_text('[animations]\nenabled=false\n')
    control=trial.Control(artifacts/'control.sock')
    with (artifacts/'session.log').open('w') as log:
        process=subprocess.Popen(['dbus-run-session','--',str(trial.BINARY),'--no-clients',
            '--config',str(config),'--control-socket',control.path,'--close-after','60'],
            env=env,stdout=log,stderr=log,start_new_session=True)
        try:
            state=trial.wait_for(control)
            started=time.monotonic()
            control('launch',program=os.environ['OHMANSY_COMPOSITOR_SHELL'])
            control('launch',program='gnome-text-editor',args=['--standalone'])
            def ready():
                state=control()
                layers={layer['namespace'] for output in state['outputs'] for layer in output['layers']}
                return {'ohmansy-shine-bar','ohmansy-wallpaper'}<=layers and any(w['app_id']=='org.gnome.TextEditor' and w['surface_size'] for w in state['windows'])
            trial.wait_for(ready,timeout=12,description='preview shell and GTK editor without portal timeout')
            elapsed=time.monotonic()-started
            print(f'Quickshell layers and editor ready in {elapsed:.2f}s',flush=True)
            contents=(artifacts/'session.log').read_text()
            assert 'Successfully activated service \'org.freedesktop.portal.Desktop\'' in contents, 'Did not exercise real portal activation'
            assert "Activating service name='org.freedesktop.secrets'" not in contents, 'Preview tried to activate a keyring'
            assert 'Timeout was reached' not in contents, 'Portal startup still timed out'
            assert elapsed<12, elapsed
            control('quit');process.wait(timeout=10)
        finally:
            if process.poll() is None:
                try: control('quit');process.wait(timeout=5)
                except (OSError,AssertionError,subprocess.TimeoutExpired): pass
            try: os.killpg(process.pid,signal.SIGTERM)
            except ProcessLookupError: pass
            process.wait(timeout=10)
    print('PASS: real private portal, Quickshell and GTK startup without keyring activation')


if __name__=='__main__':run()
