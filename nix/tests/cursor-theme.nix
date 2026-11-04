{ pkgs }:
let
  cursor = import ../modules/cursor-theme.nix { inherit pkgs; };
in
pkgs.runCommand "ohmansy-wayland-cursor-theme"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    unset XCURSOR_THEME XCURSOR_SIZE XCURSOR_PATH
    . ${cursor.environment}
    test "$XCURSOR_THEME" = Adwaita
    test "$XCURSOR_SIZE" = 24
    python3 - <<'PY'
    import ctypes
    library = ctypes.CDLL('${pkgs.libxcursor}/lib/libXcursor.so.1')
    library.XcursorLibraryLoadImage.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
    library.XcursorLibraryLoadImage.restype = ctypes.c_void_p
    library.XcursorImageDestroy.argtypes = [ctypes.c_void_p]
    for theme in [b'default', b'Adwaita']:
        for size in [24, 48]:
            for icon in [b'default', b'left_ptr', b'xterm', b'hand2', b'crosshair']:
                image = library.XcursorLibraryLoadImage(icon, theme, size)
                assert image, (theme, size, icon)
                library.XcursorImageDestroy(image)
    PY
    export XCURSOR_THEME=custom-user-theme XCURSOR_SIZE=36 XCURSOR_PATH=/custom/icons
    . ${cursor.environment}
    test "$XCURSOR_THEME" = custom-user-theme
    test "$XCURSOR_SIZE" = 36
    test "$XCURSOR_PATH" = /custom/icons:${cursor.package}/share/icons
    touch "$out"
  ''
