---
data:
  area: app
  kind: pitfall
  reviewed: "2026-11-04"
  status: current
id: jbzm6
title: Cursor fixes span the host and guest
---
Diagnose host cursor visibility separately from guest cursor rendering. Input unlock must release held keys and balance host cursor hiding. The stopped launcher must not capture Mac shortcuts. Entering the visible running guest in the active window locks input; leaving it or Control–Option–G releases it. Manual release remains effective until a new entry or click. Hover capture fails silently if permission or the event tap is unavailable.

The Quickshell login screen now runs in its own Niri compositor. Its launch script explicitly selects the shared Bibata Modern Classic default and sets XCURSOR_PATH to the packaged theme assets. The VM module disables the separate cursor plane for both the greeter and desktop. Software cursor rendering does not mean software rendering for the whole desktop.

The former SDDM greeter needed an explicit Breeze theme path as well as its software cursor setting; this is historical evidence for keeping theme lookup explicit. The user confirmed the earlier cursor fixes on 2026-11-01. Preserve host input behavior across greeter changes and verify login/desktop transitions. Automated tests alone cannot prove cursor visibility.

Sources: [greeter module](../nix/modules/greeter.nix), [VM module](../nix/modules/vm.nix), [native adapter](../app/native/RuntimeChrome.m), [graphics](../docs/graphics.md).

Native host cursor experiment (2026-11-02, removed at user request): a tested
host adapter converted QEMU cursor sprites into NSCursor with owned pixels,
correct color/alpha and HiDPI hotspot scaling. It did not work end to end:
the signed prototype received no cursor sprites, even after removing Niri's
disable-cursor-plane setting. DRM state showed the cursor plane unused.
An isolated DRM fd probe exposed one plane with atomic mode and two after
setting DRM_CLIENT_CAP_CURSOR_PLANE_HOTSPOT. This matches the virtio/Smithay
limitation reported in https://github.com/niri-wm/niri/issues/3904.

A future attempt must first establish guest compositor virtual-cursor-plane
and hotspot support, then verify cursor sprites reach QEMU. Removing the debug
flag or adding host rendering alone is insufficient. The prototype, its tests,
and its local preference were removed; retain the working software-cursor
configuration. No experiment branch or implementation was retained in Git.
