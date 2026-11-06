"""Build the installed host with a personal app selection, then activate it."""
import argparse
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def snapshot(source, destination):
    """Read protected host configuration without changing its permissions."""
    try:
        shutil.copytree(source, destination, ignore=shutil.ignore_patterns(".git"))
    except PermissionError:
        shutil.rmtree(destination, ignore_errors=True)
        print("Authentication is needed to read the installed configuration.", flush=True)
        run("sudo", sys.executable, "-c", '''
import os, shutil, sys
source, destination, uid, gid = sys.argv[1:]
shutil.copytree(source, destination, ignore=shutil.ignore_patterns('.git'))
for root, directories, files in os.walk(destination):
    os.chown(root, int(uid), int(gid))
    for name in files:
        os.chown(os.path.join(root, name), int(uid), int(gid))
''', source, destination, os.getuid(), os.getgid())


def main():
    parser = argparse.ArgumentParser(prog="ohmansy-" + sys.argv[1], description=__doc__)
    parser.add_argument("action", choices=["switch", "boot"], help=argparse.SUPPRESS)
    parser.add_argument("--host", default="ohmansy")
    parser.add_argument("--system", type=Path, default=Path("/etc/nixos"))
    parser.add_argument("--apps", type=Path, default=Path(os.environ.get(
        "XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "ohmansy/apps.nix")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--release-source", type=Path, required=True, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error("Run as your normal user; activation requests sudo separately.")
    system = args.system.absolute()
    # A private snapshot makes home configuration an explicit flake input.
    # Reject relative imports implicitly by copying only this self-contained file.
    selection = args.apps.read_text()
    with tempfile.TemporaryDirectory(prefix="ohmansy-apply-") as directory:
        machine = Path(directory) / "machine"
        snapshot(system, machine)
        if not (machine / "flake.lock").is_file() or not (machine / "flake.nix").is_file():
            parser.error("The installed system must have a flake.nix and flake.lock.")
        root = Path(directory) / "configuration"
        root.mkdir()
        (root / "apps.nix").write_text(selection)
        (root / "flake.nix").write_text('''{
  inputs.machine.url = %s;
  outputs = { machine, ... }: {
    nixosConfigurations.selected = machine.nixosConfigurations.${%s}.extendModules {
      modules = [ ./apps.nix ];
    };
  };
}
''' % (json.dumps("path:" + str(machine)), json.dumps(args.host)))
        reference = "path:" + str(root)
        overrides = ["--override-input", "machine/ohmansy", "path:" + str(args.release_source)]
        run("nix", "flake", "lock", reference, *overrides)
        # Keep output links outside the flake source used again for activation.
        result = Path(directory) / "result"
        run("nix", "build", "--no-update-lock-file", "--out-link", result,
            reference + "#nixosConfigurations.selected.config.system.build.toplevel")
        print("Built:", result.resolve(), flush=True)
        if not args.build_only:
            # nixos-rebuild owns profile/boot handling; reuse the exact locked
            # snapshot built above, without upgrading the installed release pin.
            run("sudo", "nixos-rebuild", args.action, "--flake",
                reference + "#selected", "--no-update-lock-file")


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"ohmansy: {error}")
