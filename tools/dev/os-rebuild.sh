#!/usr/bin/env bash
# Rebuild the installed machine while developing the distribution locally.
set -euo pipefail
cd "$(dirname "$0")/../.."

usage() {
  cat <<'EOF'
Usage: bash tools/dev/os-rebuild.sh {build|test|boot|switch} [--dry-run]

Build the installed configuration with this ohmansy checkout:
  build   Build only; do not activate.
  test    Activate without changing the boot default.
  boot    Select for the next boot; leave the running system unchanged.
  switch  Activate and select for future boots.

--dry-run prints the command without invoking sudo or Nix.
OHMANSY_SYSTEM_FLAKE overrides /etc/nixos#ohmansy for custom machines.
Use an installed machine configuration, never a live or factory image target.
EOF
}

case "${1:-}" in
  build|test|boot|switch) action="$1"; shift ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

dry_run=false
if [[ "${1:-}" == --dry-run ]]; then
  dry_run=true
  shift
fi
if [[ $# != 0 ]]; then
  usage >&2
  exit 2
fi

if [[ "$(uname -s)" != Linux ]]; then
  echo "Run this task inside the installed NixOS system." >&2
  exit 1
fi

flake="${OHMANSY_SYSTEM_FLAKE:-/etc/nixos#ohmansy}"
command=(sudo nixos-rebuild "$action" --flake "$flake"
  --override-input ohmansy "git+file://$PWD" --no-write-lock-file)

printf 'Running:'
printf ' %q' "${command[@]}"
printf '\n'
if ! "$dry_run"; then
  exec "${command[@]}"
fi
