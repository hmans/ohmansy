{ pkgs }:
pkgs.runCommand "ohmansy-installer-ui" {
  nativeBuildInputs = [ (import ../modules/greeter-package.nix { inherit pkgs; }) ];
} ''
  export QT_QPA_PLATFORM=offscreen QSG_RHI_BACKEND=software OHMANSY_GREETER_STATIC=1
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME"
  export XDG_RUNTIME_DIR=$(mktemp -d /tmp/ohmansy-ui.XXXXXX)
  trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
  mkdir "$out"
  INSTALLER_FLOW_TEST=1 timeout 20s quickshell --path ${../modules/installer}/preview.qml > "$TMPDIR/flow.log" 2>&1 || {
    cat "$TMPDIR/flow.log"
    exit 1
  }
  grep -q 'INSTALLER_FLOW_TEST passed' "$TMPDIR/flow.log"
  for size in wide compact short narrow; do
    if [ "$size" = wide ]; then
      export PREVIEW_WIDTH=1180 PREVIEW_HEIGHT=800
    elif [ "$size" = compact ]; then
      export PREVIEW_WIDTH=640 PREVIEW_HEIGHT=540
    elif [ "$size" = short ]; then
      export PREVIEW_WIDTH=1024 PREVIEW_HEIGHT=500
    else
      export PREVIEW_WIDTH=420 PREVIEW_HEIGHT=600
    fi
    for page in welcome disks confirm progress done failed; do
      export PREVIEW_PAGE="$page" PREVIEW_IMAGE="$out/$size-$page.png"
      timeout 20s quickshell --path ${../modules/installer}/preview.qml > "$TMPDIR/preview.log" 2>&1 || {
        cat "$TMPDIR/preview.log"
        exit 1
      }
      if grep -E 'ERROR|ReferenceError|TypeError|Unable to assign|Binding loop|Cannot assign' "$TMPDIR/preview.log"; then
        exit 1
      fi
      test -s "$PREVIEW_IMAGE"
    done
  done
''
