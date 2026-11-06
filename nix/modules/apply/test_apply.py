"""Workflow boundaries: never activate after failure or include outputs as source."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("apply", Path(__file__).with_name("apply.py"))
apply = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apply)


class ApplyTests(unittest.TestCase):
    def exercise(self, action="switch", build_only=False, failure=False):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            (base / "flake.lock").write_text("{}")
            (base / "flake.nix").write_text("{}")
            selection = "{ ohmansy.apps.obs.enable = true; }"
            (base / "apps.nix").write_text(selection)
            calls = []

            def run(*args):
                calls.append(args)
                if args[:2] == ("nix", "build"):
                    result = args[args.index("--out-link") + 1]
                    source = Path(args[-1].split("#")[0].removeprefix("path:"))
                    self.assertFalse(result.is_relative_to(source))
                    self.assertEqual((source / "apps.nix").read_text(), selection)
                    if failure:
                        raise subprocess.CalledProcessError(1, args)

            argv = ["apply", action, "--system", directory, "--apps", str(base / "apps.nix"),
                    "--release-source", "/nix/store/test-release"]
            if build_only:
                argv.append("--build-only")
            with patch.object(sys, "argv", argv), patch.object(apply.os, "geteuid", return_value=1000), patch.object(apply, "run", run):
                if failure:
                    with self.assertRaises(subprocess.CalledProcessError):
                        apply.main()
                else:
                    apply.main()
            self.assertEqual(calls[0][-3:], ("--override-input", "machine/ohmansy", "path:/nix/store/test-release"))
            activations = [call for call in calls if call[0] == "sudo"]
            self.assertEqual(len(activations), int(not failure and not build_only))
            if activations:
                self.assertEqual(activations[0][2], action)

    def test_switch(self):
        self.exercise()

    def test_boot(self):
        self.exercise("boot")

    def test_build_only(self):
        self.exercise(build_only=True)

    def test_failed_build(self):
        self.exercise(failure=True)

    def test_protected_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "machine"
            with patch.object(apply.shutil, "copytree", side_effect=PermissionError), patch.object(apply, "run") as run:
                apply.snapshot(Path("/etc/nixos"), destination)
            self.assertEqual(run.call_args.args[:2], ("sudo", sys.executable))
            self.assertEqual(run.call_args.args[-4:], (Path("/etc/nixos"), destination, apply.os.getuid(), apply.os.getgid()))


if __name__ == "__main__":
    unittest.main()
