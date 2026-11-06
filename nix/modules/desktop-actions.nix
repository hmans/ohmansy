{ pkgs }:
pkgs.writeShellApplication {
  name = "ohmansy-desktop";
  runtimeInputs = with pkgs; [
    coreutils jq cliphist wl-clipboard systemd niri quickshell
    pavucontrol networkmanagerapplet blueman zenity
  ];
  text = builtins.readFile ./desktop/actions.sh;
}
