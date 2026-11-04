#!/usr/bin/env bash
# Build a local installer and publish a host-readable ISO for QEMU.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p .local/nix-build dist/installer
exec 9>.local/installer-build.lock
flock 9
export TMPDIR="$PWD/.local/nix-build"
build_args=(build --no-update-lock-file --max-jobs 2 --cores 4
  --out-link .local/installer-build .#installer-iso)

if command -v nix >/dev/null 2>&1; then
  nix "${build_args[@]}"
  result="$(readlink -f .local/installer-build)"
elif [[ -x .local/nix-portable ]]; then
  export NP_LOCATION="$PWD/.local" NP_RUNTIME=bwrap
  .local/nix-portable nix "${build_args[@]}" --option sandbox false
  # The portable store is mounted at /nix only inside its runtime.
  result="$NP_LOCATION/.nix-portable$(readlink .local/installer-build)"
else
  echo "Nix is required (native nix or .local/nix-portable)." >&2
  exit 1
fi

shopt -s nullglob
images=("$result"/iso/*.iso)
if [[ ${#images[@]} -ne 1 ]]; then
  echo "Expected exactly one installer ISO in $result/iso." >&2
  exit 1
fi
temporary=$(mktemp dist/installer/.installer-XXXXXX.iso)
trap 'rm -f "$temporary"' EXIT
cp --reflink=auto "${images[0]}" "$temporary"
chmod 644 "$temporary"
mv -f "$temporary" dist/installer/ohmansy-installer.iso
echo "Built dist/installer/ohmansy-installer.iso"
