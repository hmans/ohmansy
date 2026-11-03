---
data:
  area: tooling
  kind: workflow
  reviewed: "2026-11-03"
  status: current
id: b4jpz
title: Host tooling and publication workflow
---
# Host development, build, and release tools

Read [root instructions](../AGENTS.md). Run commands from the
repository root unless the tool explicitly supports another working directory.

## Boundaries

- dev/ manages SSH source snapshots and isolated image tests. It must not send
  the host home directory, personal reference flake, keys, or local VM state.
- build/ assembles and signs the Mac bundle. Keep the engine checksum pin and
  stable signing identity. Never modify the installed source runtime app.
- release/ packages images, source archives, manifests, and checksums. Source
  must match the image build. Keep outputs outside Git and refuse accidental
  replacement of release artifacts.
- Runtime code belongs in app/runtime/. Avoid dependencies from shipped code
  on these host-only tools. Update callers, CLI examples, and tests after moves.

## Guest work

Use SSH with an explicit target, identity, port, and verified host key. Read
ignored local session notes if present; confirm the endpoint and running system.
The guest-dev defaults may describe an older builder. Never disable host-key
checking to get around a mismatch or assume the old personal VM still exists.

Sync into a new snapshot. Preserve installed owner, storage, and development
overlays when building an installed host. Factory/live targets are image outputs,
not replacements for the current guest configuration. Private development guests
opt in with the shipped `ohmansy-dev enable --public-key ...` command. The host's
`guest-dev.py bridge --state .local/VM --port PORT --public-key KEY.pub` updates
QMP, persists only the loopback port in local development.json, and prints the
guest command. `unbridge` removes the forward; guest `disable` removes managed
access. Older app bundles do not read that state setting. The manual
prepare-access generator remains available for custom flakes. The first activation
needs the owner's password in their own terminal. Never use terminal UI automation.

Image profiles import `nix/modules/image-policy.nix` and reject development markers,
SSH access or keys, extra owner accounts, and custom sudo rules during system
build evaluation. The standard live-console wheel rule is allowed. Source archives
exclude `tools/dev/` and `.local/`. Flake checks exercise rejected configurations;
Python tests cover generation and archive exclusion. These checks do not certify
arbitrary input disks passed to the packaging tools.

QMP is the lifecycle/control channel. Use an explicit state directory. The
gpu-probe `shutdown` action requests a clean shutdown; `stop` sends QEMU `quit`
and is a power cut if the guest is running. Confirm shutdown before quitting the
engine or deleting state. Never treat a PID file as proof of process identity.

## Validation and publication

Run Python tests with `python3 -m unittest discover -s tools/tests -p 'test_*.py'`.
Use make test when runtime behavior is affected. Check changed CLI entry points
with --help and test actual packaging when paths or bundle layout change.

Check host and guest disk headroom before image builds. Prefer the ARM CI runner
for full image assembly on a resource-constrained Mac. Do not overwrite or delete
a VM to make space. Use a disposable disk for installer tests.

This repository is public. Before an authorized push, inspect the exact changed
files for secrets and generated artifacts. Scan reachable history before first
publication or a history rewrite. Use redacted secret-scanner output and keep
reports under .local/. Do not push unless the current task authorizes it.

CI actions are pinned. The AppArmor exception in .github/ permits user namespaces
only for the Nix unshare executable on disposable runners; do not replace it
with a global security disable. CI artifacts are not public GitHub releases.
