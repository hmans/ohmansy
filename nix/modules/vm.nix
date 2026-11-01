{ lib, pkgs, ... }:
{
  # Guest integration only; disk layout and user accounts belong to each host.
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "xhci_pci" "usbhid" ];
  services.logind.settings.Login.HandlePowerKey = "poweroff";
  # Draw the greeter cursor in the composited image, as Niri does in this VM.
  # Supply its theme explicitly: without a desktop session, KWin cannot find
  # a default cursor theme. The compositor retains GPU acceleration.
  services.displayManager.sddm.wayland.compositor = "kwin";
  services.displayManager.sddm.settings.General.GreeterEnvironment =
    "QT_WAYLAND_SHELL_INTEGRATION=layer-shell,KWIN_FORCE_SW_CURSOR=1,XCURSOR_THEME=breeze_cursors,XCURSOR_PATH=${pkgs.kdePackages.breeze}/share/icons";
  services.displayManager.sddm.settings.Theme.CursorTheme = "breeze_cursors";
  environment.etc."ohmansy/niri.kdl".source = lib.mkForce ./desktop/vm.kdl;
  environment.etc."ohmansy/desktop.kdl".source = ./desktop/niri.kdl;
}
