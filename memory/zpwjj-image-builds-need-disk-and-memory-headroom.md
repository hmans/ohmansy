---
data:
  area: tooling
  kind: pitfall
  reviewed: "2026-11-01"
  status: current
id: zpwjj
title: Image builds need disk and memory headroom
---
Prefer ARM CI for full image assembly on a resource-constrained Mac. On 2026-11-01 a local image build coincided with QEMU SIGKILL, a low-swap host report, and almost no free host disk space. The guest had 24 GiB assigned on a 36 GiB host. The signature still verified. SIGKILL alone does not prove a signing failure or a specific memory cause.

The local allocation was reduced and the full build moved to CI, where it succeeded. Inspect host and guest free space, VM memory, and active builders before retrying heavy work.

Sparse disk logical size differs from allocated size. APFS shared blocks and Time Machine snapshots can delay free-space recovery after deletion. Check processes and open files before cleanup. Do not delete a VM, recovery data, or snapshots merely because they are large without authorization.

The old flakey VM, verification bundle, and obsolete ISO tests were removed at the user's request. They are not available fallbacks. Keep live inventory in ignored local notes. This is an incident lesson, not a current resource report.

Source: [build workflow and space requirement](../docs/ohmansy-development.md).
