{ pkgs, ... }:
{
  imports = [ ./live.nix ];

  # A default, not a lock: the bar can still change the live user's preference.
  programs.dconf.enable = true;
  programs.dconf.profiles.user.databases = [{
    settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
  }];

  # Niri matches exact output names, not wildcards. Apply the live-session
  # default through IPC once outputs are ready, before starting the shell.
  systemd.user.services.ohmansy-live-scale = {
    description = "Ohmansy live desktop display scale";
    wantedBy = [ "niri.service" ];
    after = [ "niri.service" ];
    before = [ "quickshell.service" "ohmansy-wallpaper.service" ];
    partOf = [ "niri.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "ohmansy-live-scale" ''
        set -euo pipefail
        outputs=$(${pkgs.niri}/bin/niri msg --json outputs)
        while IFS= read -r output; do
          ${pkgs.niri}/bin/niri msg output "$output" scale 1.25
        done < <(printf '%s' "$outputs" | ${pkgs.jq}/bin/jq -r 'keys[]')
      '';
    };
  };
}
