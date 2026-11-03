---
data:
  area: tooling
  kind: pitfall
  reviewed: "2026-11-03"
  status: current
id: zpwjj
title: Image builds need disk and memory headroom
---
Prefer ARM CI for full image assembly on a resource-constrained Mac. On 2026-11-01 a local image build coincided with QEMU SIGKILL, a low-swap host report, and almost no free host disk space. The guest had 24 GiB assigned on a 36 GiB host. The signature still verified. SIGKILL alone does not prove a signing failure or a specific memory cause.

Native x86 factory assembly (2026-11-03) exhausted a 16 GiB RAM-backed `/tmp`:
systemd-repart needed both a 9.1 GiB temporary root filesystem and the 9.6 GiB
final disk. Reusing compiled packages with single-user Nix's `TMPDIR` on persistent
SSD storage succeeded. Store space alone is insufficient; inspect the build
workspace too. Zstandard decompression preserves the store artifact's read-only
mode, so make the private raw copy owner-writable before resizing or booting it.

The local allocation was reduced and the full build moved to CI, where it succeeded. Inspect host and guest free space, VM memory, and active builders before retrying heavy work.

Sparse disk logical size differs from allocated size. APFS shared blocks and Time Machine snapshots can delay free-space recovery after deletion. Check processes and open files before cleanup. Do not delete a VM, recovery data, or snapshots merely because they are large without authorization.

The old flakey VM, verification bundle, and obsolete ISO tests were removed at the user's request. They are not available fallbacks. Keep live inventory in ignored local notes. This is an incident lesson, not a current resource report.

Routine host cleanup is now available through `mise run clean`, with a dry-run preview. The allowlist removes build caches and obsolete generated artifacts while preserving the current app, factory package, and all VM state. Guest deletion requires an explicit `--retire-vm NAME`; process/open-file inspection and the runtime lock guard active guests. See the cleanup section in the development guide. Never select a guest from stale handoff notes alone. The current guest is small enough that deleting old source snapshots or collecting its Nix store is not necessarily the main space saving.

Source: [build workflow and space requirement](../docs/ohmansy-development.md).
