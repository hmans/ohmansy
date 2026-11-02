---
data:
  area: app
  kind: pitfall
  reviewed: "2026-11-02"
  status: current
id: jbzm6
title: Cursor fixes span the host and guest
---
Diagnose host cursor visibility separately from guest cursor rendering. Input unlock must release held keys and balance host cursor hiding. The stopped launcher must not capture Mac shortcuts. Clicking the running guest locks input; leaving it or Control–Option–G releases it.

The Quickshell login screen now runs in its own Niri compositor. Its launch script explicitly selects Adwaita and sets XCURSOR_PATH to the theme store path. The VM module disables the separate cursor plane for both the greeter and desktop. Software cursor rendering does not mean software rendering for the whole desktop.

The former SDDM greeter needed an explicit Breeze theme path as well as its software cursor setting; this is historical evidence for keeping theme lookup explicit. The user confirmed the earlier cursor fixes on 2026-11-01. Preserve host input behavior across greeter changes and verify login/desktop transitions. Automated tests alone cannot prove cursor visibility.

Sources: [greeter module](../nix/modules/greeter.nix), [VM module](../nix/modules/vm.nix), [native adapter](../app/native/RuntimeChrome.m), [graphics](../docs/graphics.md).
