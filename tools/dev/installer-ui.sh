#!/usr/bin/env bash
# Run the mock installer against working-tree QML for immediate UI edits.
set -euo pipefail
cd "$(dirname "$0")/../.."

export PREVIEW_PAGE="${1:-welcome}"
case "$PREVIEW_PAGE" in
  welcome|disks|confirm|progress|done|failed) ;;
  *) echo "Usage: bash tools/dev/installer-ui.sh [welcome|disks|confirm|progress|done|failed]" >&2; exit 2 ;;
esac
export OHMANSY_INSTALLER_QML="$PWD/nix/modules/installer/preview.qml"
export OHMANSY_RIBBONS="file://$PWD/nix/modules/greeter/scene/Ribbons.qml"

if command -v nix >/dev/null 2>&1; then
  exec nix run --no-update-lock-file .#installer-preview
elif [[ -x .local/nix-portable ]]; then
  # Portable Nix may not be able to load the host's graphics drivers.
  export QT_QUICK_BACKEND="${QT_QUICK_BACKEND:-software}"
  export NP_LOCATION="$PWD/.local" NP_RUNTIME=bwrap
  export TMPDIR="$PWD/.local/nix-build"
  mkdir -p "$TMPDIR"
  exec .local/nix-portable nix run --no-update-lock-file --option sandbox false .#installer-preview
else
  echo "Nix is required. Enter the project's Linux development environment first." >&2
  exit 1
fi
