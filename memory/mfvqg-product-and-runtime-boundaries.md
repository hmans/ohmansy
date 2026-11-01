---
data:
  area: project
  kind: architecture
  reviewed: "2026-11-01"
  status: current
id: mfvqg
title: Product and runtime boundaries
---
Ohmansy is the reusable NixOS desktop; try ohmansy is its Mac host. The root flake is independent of the ignored flakey reference. The old personal VM was deleted at the user's request and is no longer a builder.

The main product uses a preinstalled factory disk with first-boot owner setup and persistent private state. Live and installer ISOs are separate profiles. Shared desktop modules must not contain personal users, disk identities, or development SSH access.

The default backend has a windowless Swift coordinator and a nested QEMU helper that owns the single visible window. RuntimeChrome adapts a pinned engine. The original Apple Virtualization backend is separate; its clipboard support does not imply support in the accelerated backend.

Sources: [development workflow](../docs/ohmansy-development.md), [graphics](../docs/graphics.md), [flake](../flake.nix), [app instructions](../app/AGENTS.md).
