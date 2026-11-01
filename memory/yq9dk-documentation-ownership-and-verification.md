---
data:
  area: project
  kind: workflow
  reviewed: "2026-11-01"
  status: current
id: yq9dk
title: Documentation ownership and verification
---
# Documentation

Check source code and command help before changing instructions. Use the
technical-writing skill when available. Keep user workflows here and durable
agent knowledge in memory/; avoid copying the same procedure into both.

- README.md is the short entry point and repository map.
- ohmansy-development.md describes the official flake and factory workflow.
- graphics.md describes the accelerated host and its constraints.
- guest-development.md and legacy-virtualization.md are historical/legacy
  references. Do not present their personal VM paths as current setup.

Document whether a result was built, booted, visually checked, or user-confirmed.
Date evidence that can become stale. Do not call a CI build an installation test
or claim a local app bundle contains the latest image without checking its manifest.

Use repository-relative links, check they resolve, and run git diff --check.
Documentation-only work does not need an OS image or app rebuild. Do not include
credentials or machine diagnostics. Put machine-specific handoff state in ignored
.local/SESSION.md and treat it as a hint to verify, not an instruction to execute.
