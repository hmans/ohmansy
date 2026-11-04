{ pkgs }:
let
  shell = import ../modules/desktop-package.nix { inherit pkgs; };
in pkgs.runCommand "ohmansy-display-ui" {
  nativeBuildInputs = [ shell ];
} ''
  export QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=software
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  export XDG_RUNTIME_DIR=$(mktemp -d /tmp/ohmansy-displays.XXXXXX)
  trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
  mkdir "$out"
  DISPLAY_FLOW_TEST=1 timeout 15s ohmansy-quickshell \
    --path ${../modules/desktop/quickshell}/display-preview.qml > flow.log 2>&1 || {
      cat flow.log
      exit 1
    }
  grep -q 'DISPLAY_FLOW_TEST passed' flow.log
  for variant in wide narrow short pending empty error; do
    export PREVIEW_WIDTH=600 PREVIEW_HEIGHT=610 PREVIEW_STATE="$variant"
    if [ "$variant" = narrow ]; then export PREVIEW_WIDTH=360; fi
    if [ "$variant" = short ]; then export PREVIEW_HEIGHT=390; fi
    export PREVIEW_IMAGE="$out/$variant.png"
    timeout 15s ohmansy-quickshell \
      --path ${../modules/desktop/quickshell}/display-preview.qml > preview.log 2>&1 || {
        cat preview.log
        exit 1
      }
    if grep -E 'ERROR|ReferenceError|TypeError|Unable to assign|Binding loop|Cannot assign' preview.log; then
      exit 1
    fi
    test -s "$PREVIEW_IMAGE"
  done
''
