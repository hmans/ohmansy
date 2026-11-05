"""Keep btop's managed theme in step with the desktop appearance."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


def sync(theme_directory, mode):
    directory = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "btop"
    themes = directory / "themes"
    themes.mkdir(parents=True, exist_ok=True)
    target = themes / "ohmansy.theme"
    source = Path(theme_directory) / f"{mode}.theme"
    if target.is_symlink() and target.readlink() == source:
        return
    with tempfile.TemporaryDirectory(prefix=".ohmansy-", dir=themes) as temporary:
        link = Path(temporary) / "theme"
        link.symlink_to(source)
        link.replace(target)
    # btop handles SIGUSR2 by reloading its config and theme. No process is normal.
    subprocess.run(["pkill", "-USR2", "-u", str(os.getuid()), "-x", "btop"], check=False)


def appearance():
    result = subprocess.run(
        ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
        capture_output=True, text=True, check=False,
    )
    return "dark" if "prefer-dark" in result.stdout else "light"


def prepare(theme_directory):
    sync(theme_directory, appearance())
    directory = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "btop"
    try:
        with (directory / "btop.conf").open("x") as config:
            config.write('color_theme = "ohmansy"\ntheme_background = false\n')
    except FileExistsError:
        pass


def main():
    command, theme_directory = sys.argv[1:3]
    if command == "prepare":
        prepare(theme_directory)
    elif command == "sync":
        sync(theme_directory, sys.argv[3])
    elif command == "watch":
        # Subscribe before reading so a change during startup cannot be missed.
        with subprocess.Popen(
            ["stdbuf", "-oL", "gsettings", "monitor", "org.gnome.desktop.interface", "color-scheme"],
            stdout=subprocess.PIPE, text=True,
        ) as monitor:
            sync(theme_directory, appearance())
            for _line in monitor.stdout:
                sync(theme_directory, appearance())
            raise SystemExit(monitor.wait() or 1)
    else:
        raise SystemExit(f"Unknown command: {command}")


if __name__ == "__main__":
    main()
