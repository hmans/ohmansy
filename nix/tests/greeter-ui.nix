{ pkgs }:
pkgs.runCommand "ohmansy-greeter-ui"
  {
    nativeBuildInputs = [ (import ../modules/greeter-package.nix { inherit pkgs; }) ];
  }
  ''
    export QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=software OHMANSY_GREETER_STATIC=1
    export FONTCONFIG_FILE=${pkgs.makeFontsConf { fontDirectories = [ pkgs.inter ]; }}
    export HOME="$TMPDIR/home" XDG_RUNTIME_DIR="$TMPDIR/runtime"
    mkdir -m 700 -p "$HOME" "$XDG_RUNTIME_DIR" "$out"
    GREETER_FLOW_TEST=1 timeout 15s quickshell --path ${../modules/greeter}/preview.qml > flow.log 2>&1 || {
      cat flow.log
      exit 1
    }
    grep -q 'GREETER_FLOW_TEST passed' flow.log
    for size in wide compact narrow; do
      export PREVIEW_WIDTH=1100 PREVIEW_HEIGHT=720
      if [ "$size" = compact ]; then export PREVIEW_WIDTH=640 PREVIEW_HEIGHT=500; fi
      if [ "$size" = narrow ]; then export PREVIEW_WIDTH=360 PREVIEW_HEIGHT=620; fi
      for selected in niri ohmansy; do
        export PREVIEW_SESSION="$selected" PREVIEW_IMAGE="$out/$size-$selected.png"
        timeout 15s quickshell --path ${../modules/greeter}/preview.qml > render.log 2>&1 || {
          cat render.log
          exit 1
        }
        if grep -E 'ERROR|ReferenceError|TypeError|Unable to assign|Binding loop|Cannot assign' render.log; then exit 1; fi
        test -s "$PREVIEW_IMAGE"
      done
    done
  ''
