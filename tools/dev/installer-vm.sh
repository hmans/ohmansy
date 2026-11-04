#!/usr/bin/env bash
# Button-friendly entry points for the local QEMU installer VM.
set -euo pipefail
cd "$(dirname "$0")/../.."

state="${OHMANSY_INSTALLER_STATE:-.local/installer-actions}"
iso="${OHMANSY_INSTALLER_ISO:-dist/installer-graphical/ohmansy-0.1.0-installer-x86_64-linux.iso}"
args=(--state "$state" --no-network)

case "${1:-}" in
  iso)
    if [[ -e "$state" ]]; then
      args+=(--rescue-iso "$iso")
    else
      args+=(--iso "$iso")
    fi
    ;;
  disk) ;;
  *)
    echo "Usage: bash tools/dev/installer-vm.sh {iso|disk}" >&2
    echo "Override paths with OHMANSY_INSTALLER_ISO and OHMANSY_INSTALLER_STATE." >&2
    exit 2
    ;;
esac

exec python3 tools/dev/linux-iso-vm.py "${args[@]}"
