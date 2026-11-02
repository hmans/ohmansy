{ pkgs }:
# Quickshell 0.3.0 confuses cancel_session acknowledgements with authentication
# success. Keep this patch scoped to the greeter and test delayed replies.
pkgs.quickshell.overrideAttrs (old: {
  patches = (old.patches or []) ++ [ ./greeter/quickshell-greetd-cancel.patch ];
})
