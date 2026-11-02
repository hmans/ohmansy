{ pkgs }:
let
  launcher = pkgs.writeShellScript "ohmansy-foot" ''
    # The appearance portal uses 1 for dark, 2 for light, and 0 for no preference.
    # Match the shell's light fallback when no preference is available.
    theme=light
    preference=$(${pkgs.glib}/bin/gdbus call --session --timeout 2 \
      --dest org.freedesktop.portal.Desktop \
      --object-path /org/freedesktop/portal/desktop \
      --method org.freedesktop.portal.Settings.Read \
      org.freedesktop.appearance color-scheme 2>/dev/null) || preference=
    case "$preference" in *"uint32 1"*) theme=dark ;; esac
    exec ${pkgs.foot}/bin/foot --override="main.initial-color-theme=$theme" "$@"
  '';
in pkgs.symlinkJoin {
  name = "ohmansy-foot-${pkgs.foot.version}";
  paths = [ pkgs.foot ];
  postBuild = ''
    rm "$out/bin/foot"
    ln -s ${launcher} "$out/bin/foot"
  '';
  meta = pkgs.foot.meta;
}
