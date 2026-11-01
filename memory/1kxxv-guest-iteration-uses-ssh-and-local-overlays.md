---
data:
  area: nix
  kind: workflow
  reviewed: "2026-11-01"
  status: current
id: 1kxxv
title: Guest iteration uses SSH and local overlays
---
Use SSH for commands and transfers. Never type or paste commands into terminal windows through computer use: earlier synthetic input dropped key releases and left keys repeating. Slower typing is not a workaround.

Read ignored .local/SESSION.md for local connection details, then verify guest identity. Pass the current SSH port and verified host-key file explicitly; tooling defaults may target the retired builder. QMP-added forwarding disappears when the host engine exits, but survives a guest reboot. Development SSH stays in a local guest overlay, not shipped images.

For routine edits, build a host configuration that preserves the installed owner, storage, state versions, and development overlay. Never activate factory or live profiles on an installed guest. Prefer boot activation for login-manager changes, then a planned restart. Build, boot selection, and running generation are distinct.

Source snapshots avoid sharing the host home. Full image builds test provisioning and releases, not every desktop edit.

Sources: [workflow](../docs/ohmansy-development.md), [guest tooling](../tools/dev/guest-dev.py), [Nix instructions](../nix/AGENTS.md).
