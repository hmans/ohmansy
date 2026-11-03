"""Check the installed entry point and its included bindings, then validate KDL."""
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

entry, desktop, definitions = map(Path, sys.argv[1:])
entry_text = entry.read_text()
assert 'include "/etc/ohmansy/desktop.kdl"' in entry_text, "Entry point does not load desktop bindings"
assert 'include optional=true "~/.local/state/ohmansy/niri-appearance.kdl"' in entry_text, "Entry point does not load the desktop appearance palette"
assert entry_text.index('include "/etc/ohmansy/desktop.kdl"') < entry_text.index('include optional=true "~/.local/state/ohmansy/niri-appearance.kdl"'), "Appearance palette must override the desktop defaults"
expected = {
    binding["key"]: binding["action"]
    for group in json.loads(definitions.read_text())
    for binding in group["bindings"]
}
actual = dict(re.findall(
    r'^\s*(\S+)\s+[^\n]*hotkey-overlay-title="[^"]*"\s*\{ (.*); \}$',
    desktop.read_text(), re.MULTILINE,
))
assert actual == expected, f"Packaged bindings differ: missing={expected.keys() - actual.keys()}"
with tempfile.TemporaryDirectory() as directory:
    config = Path(directory) / "niri.kdl"
    config.write_text(entry_text.replace("/etc/ohmansy/desktop.kdl", str(desktop)))
    subprocess.run(["niri", "validate", "--config", str(config)], check=True)
