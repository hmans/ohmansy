---
data:
  area: tooling
  kind: verification
  reviewed: "2026-11-03"
  status: current
id: xmgvq
title: Build evidence and release readiness
---
Treat tests, packaging, image assembly, boot, and user confirmation as separate evidence. make test covers Swift, Python, and native adapter tests. A separate APP_BUNDLE path avoids overwriting a running bundle, but shares bundle IDs and preferences; it is not an isolated guest.

ARM CI successfully checked and built the factory in [run 41336375624](https://github.com/hmans/ohmansy/actions/runs/41336375624) on 2026-11-01. Ubuntu user-namespace restrictions required a scoped AppArmor profile for Nix-store unshare. Keep the exception narrow; do not disable AppArmor globally.

CI uploads preview artifacts, not releases. It does not establish successful boot. An existing dist bundle may contain an older factory: inspect its manifest. Installer end-to-end validation, notarized Mac distribution, accelerated audio, and additional displays remain separate work.

Sources: [CI](../.github/workflows/images.yml), [AppArmor profile](../.github/nix-userns.apparmor), [release requirements](../docs/ohmansy-development.md), [Makefile](../Makefile).

Accelerated text clipboard build and live checks are recorded in [Mac app validation](bta99-mac-app-implementation-and-validation.md). Both host and guest need the new integration; old factory artifacts remain old.
