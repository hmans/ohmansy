---
data:
  area: app
  kind: pitfall
  reviewed: "2026-11-01"
  status: current
id: jbzm6
title: Cursor fixes span the host and guest
---
Diagnose host cursor visibility separately from guest cursor rendering. Input unlock must release held keys and balance host cursor hiding. The stopped launcher must not capture Mac shortcuts. Clicking the running guest locks input; leaving it or Control–Option–G releases it.

SDDM logged “Unable to load any cursor theme”. KWin with a software cursor alone was insufficient. The working module also selects Breeze explicitly, including its store path in XCURSOR_PATH. Niri disables the separate cursor plane. Software cursor rendering does not mean software rendering for the whole desktop.

The user confirmed both host and guest login cursor fixes on 2026-11-01. Preserve these settings across greeter changes and verify login/desktop transitions. Automated tests alone cannot prove cursor visibility.

Sources: [VM module](../nix/modules/vm.nix), [desktop assets](../nix/modules/desktop/), [native adapter](../app/native/RuntimeChrome.m), [graphics](../docs/graphics.md).
