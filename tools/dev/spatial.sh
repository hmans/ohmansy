#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo"

action=${1:-run}
if (($#)); then shift; fi
case "$action" in
  run|check|integration) ;;
  *) echo "Usage: bash tools/dev/spatial.sh [run|check|integration] [arguments...]" >&2; exit 2 ;;
esac

# Nix supplies native libraries and NixOS's patched rustup. Mise owns the Rust
# version. Cargo retains incremental builds between runs; no OS activation.
if [[ ${OHMANSY_SPATIAL_SHELL:-0} != 1 ]]; then
  exec nix develop --no-update-lock-file .#spatial --command \
    env OHMANSY_SPATIAL_SHELL=1 bash "$0" "$action" "$@"
fi

if ! mise where rust >/dev/null 2>&1; then
  version=$(python3 -c 'import tomllib; print(tomllib.load(open("mise.toml", "rb"))["tools"]["rust"]["version"])')
  rustup toolchain install "$version" --profile minimal --component rustfmt --component clippy
  toolchain=$(rustup which --toolchain "$version" rustc)
  mise link "rust@$version" "${toolchain%/bin/rustc}"
fi
export CARGO_TARGET_DIR="$repo/.build/spatial"
experiment=${OHMANSY_EXPERIMENT:-spatial}
case "$experiment" in
  spatial|compositor) ;;
  *) echo "Unknown experiment: $experiment" >&2; exit 2 ;;
esac
manifest="$repo/experiments/$experiment/Cargo.toml"
if [[ $experiment == compositor ]]; then
  manifest="$repo/nix/compositor/Cargo.toml"
fi
if [[ $action == integration ]]; then
  mise exec -- cargo build --locked --manifest-path "$manifest"
  exec python3 tools/tests/compositor_integration.py "$@"
fi
if [[ $action == check ]]; then
  mise exec -- cargo fmt --manifest-path "$manifest" --check
  mise exec -- cargo test --locked --manifest-path "$manifest"
  exec mise exec -- cargo clippy --locked --manifest-path "$manifest" --all-targets -- -D warnings
fi
exec mise exec -- cargo run --locked --manifest-path "$manifest" -- "$@"
