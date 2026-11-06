#!/usr/bin/env bash
# Verify the source snapshot and shipped package before reviewing a Shine change.
set -euo pipefail
cd "$(dirname "$0")/../.."

graphics=true
case "${1:-}" in
  --no-graphics) graphics=false; shift ;;
  '') ;;
  *) echo "Usage: bash tools/dev/shine-check.sh [--no-graphics]" >&2; exit 2 ;;
esac
if (($#)); then
  echo "Usage: bash tools/dev/shine-check.sh [--no-graphics]" >&2
  exit 2
fi

untracked=$(git ls-files --others --exclude-standard -- nix/compositor nix/modules skills)
if [[ -n $untracked ]]; then
  echo "Nix's Git snapshot excludes these new files. Include intended sources with git add -N:" >&2
  printf '%s\n' "$untracked" >&2
  exit 1
fi
git diff --check
OHMANSY_EXPERIMENT=compositor bash tools/dev/spatial.sh check
nix develop --no-update-lock-file .#spatial --command \
  python3 -m unittest discover -s tools/tests -p test_shine_dev.py -v
nix build --no-update-lock-file --out-link .local/shine-checked-package .#compositor

if $graphics; then
  for trial in compositor_frames.py compositor_glass.py compositor_inactive.py; do
    nix develop --no-update-lock-file .#spatial --command \
      env OHMANSY_SPATIAL_SHELL=1 OHMANSY_REQUIRE_HARDWARE_RENDERER=1 \
      python3 "tools/tests/$trial"
  done
  nix develop --no-update-lock-file .#spatial --command \
    env OHMANSY_SPATIAL_SHELL=1 OHMANSY_REQUIRE_HARDWARE_RENDERER=1 \
    python3 tools/tests/compositor_nesting.py eurkey ctrl-alt
  echo "Shine package and private hardware-rendered trials passed. Installed activation was not tested."
else
  echo "Shine package and non-graphical checks passed. GPU runtime and installed activation were not tested."
fi
