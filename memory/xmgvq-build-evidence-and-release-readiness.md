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

PC live USB support (2026-11-03): x86_64 outputs `iso` and `iso-nvidia` use the shared desktop without VM-only scaling, software cursor, or host clipboard. ARM live/installer outputs retain those settings through `profiles/live-vm.nix`. NVIDIA uses open kernel modules plus the locked stable userspace driver; the PC live profile has no Ohmansy installer action. All-system flake evaluation passed, as did Python packaging tests and actionlint. The new x86 CI job is configured to build the NVIDIA live ISO; this evaluation is not evidence of image assembly or a physical RTX 3060 Ti boot. See the development guide for USB testing.

The NVIDIA PC live ISO subsequently built successfully in [run 41660933001](https://github.com/hmans/ohmansy/actions/runs/41660933001), commit fc03e0a. On 2026-11-03 the user confirmed a physical PC boot with RTX 3060 Ti; screenshots show Niri, two detected displays, Firefox, and the current Fish/Starship prompt. The static cat wallpaper is visible instead of ribbons. Subsequent QSG_INFO logs confirmed hardware rendering on NVIDIA through OpenGL ES 3.2. Our desktop-only GL function loader failed before shader compilation, triggering the static fallback. The renderer now supports desktop GL and ES; both paths passed real-render checks using llvmpipe on ARM Linux. The updated renderer has not yet been tested on physical NVIDIA hardware or included in a new ISO. Audio remains unverified.

CI run 41677487964 (2026-11-03, d3bb091): the ARM checks, factory build, and artifact upload passed. The PC job stopped before ISO assembly in the customization check: xdg-terminal-exec reported a printf I/O error. Its --print-cmd output was piped to grep -q, which can exit before the producer finishes under pipefail. Capture the complete output to a file before matching it. The corrected customization check passed on the ARM development guest; x86 CI verification remains pending. Do not disable the terminal-selection assertion or retry this race as an infrastructure failure.

The corrected check subsequently passed in [run 41680332938](https://github.com/hmans/ohmansy/actions/runs/41680332938)
(2026-11-03, fe26843). Both image jobs succeeded and uploaded their artifacts.
This confirms the x86 checks and NVIDIA live ISO assembly for that revision;
it does not establish a boot or installation.
