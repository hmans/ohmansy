"""Process cleanup regressions; no graphical display is needed."""
import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

spec = importlib.util.spec_from_file_location(
    'test_display', Path(__file__).resolve().parents[1] / 'dev/compositor-test-display.py')
display = importlib.util.module_from_spec(spec)
spec.loader.exec_module(display)


class ProcessCleanupTests(unittest.TestCase):
    def test_exception_stops_and_reaps_the_process(self):
        with self.assertRaisesRegex(ValueError, 'fixture'):
            with display.process_group([sys.executable, '-c', 'import time; time.sleep(60)'],
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as process:
                raise ValueError('fixture')
        self.assertIsNotNone(process.returncode)
        with self.assertRaises(ProcessLookupError):
            os.killpg(process.pid, 0)

    def test_stubborn_child_is_killed_after_its_group_leader_exits(self):
        with tempfile.TemporaryDirectory() as directory:
            ready = Path(directory) / 'ready'
            code = f'''
import os, pathlib, signal, time
ready = pathlib.Path({str(ready)!r})
if os.fork() == 0:
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    ready.write_text(str(os.getpid()))
    time.sleep(60)
else:
    while not ready.exists():
        time.sleep(.01)
'''
            process = subprocess.Popen([sys.executable, '-c', code], start_new_session=True,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                process.wait(timeout=5)
                child = int(ready.read_text())
                display.stop(process, timeout=.1)

                def alive():
                    try:
                        # An orphan may briefly remain as a zombie until init
                        # reaps it. It must no longer be a running process.
                        return Path(f'/proc/{child}/stat').read_text().rsplit(')', 1)[1].split()[0] != 'Z'
                    except FileNotFoundError:
                        return False

                deadline = time.monotonic() + 2
                while alive() and time.monotonic() < deadline:
                    time.sleep(.01)
                self.assertFalse(alive(), 'Child ignored SIGTERM and survived group cleanup')
            finally:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=5)


if __name__ == '__main__':
    unittest.main()
