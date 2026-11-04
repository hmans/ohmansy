# Fixed actions only. Clipboard content and window titles are never shell code.
case "${1:-}" in
  menu)
    case "${2:-}" in apps|windows|clipboard|power|controls|notifications|shortcuts|displays) ;; *) exit 2 ;; esac
    systemctl --user start quickshell.service
    for _attempt in $(seq 1 40); do
      if quickshell ipc --path /etc/xdg/quickshell/ohmansy/shell.qml call launcher ping >/dev/null 2>&1; then
        exec quickshell ipc --path /etc/xdg/quickshell/ohmansy/shell.qml call launcher openMenu "$2"
      fi
      sleep 0.05
    done
    exit 1
    ;;
  consume-left|expel-left)
    plan=$(niri msg --json windows | jq -e '
      . as $windows | map(select(.is_focused))[0] as $focused
      | $focused.layout.pos_in_scrolling_layout[0] as $column
      | if $column == null then empty else
          [$windows[] | select(.workspace_id == $focused.workspace_id
            and .layout.pos_in_scrolling_layout != null)] as $tiled
          | {
              focused: $focused.id,
              current: ($tiled | map(select(.layout.pos_in_scrolling_layout[0] == $column))
                | sort_by(.layout.pos_in_scrolling_layout[1]) | map(.id)),
              left: ($tiled | map(select(.layout.pos_in_scrolling_layout[0] == $column - 1))
                | sort_by(.layout.pos_in_scrolling_layout[1]) | map(.id))
            }
        end
    ') || exit 0
    if [ "$1" = consume-left ]; then
      left_count=$(printf '%s' "$plan" | jq '.left | length')
      [ "$left_count" -gt 0 ] || exit 0
      window_id=$(printf '%s' "$plan" | jq '.left[0]')
      if [ "$left_count" -gt 1 ]; then
        niri msg action consume-or-expel-window-right --id "$window_id"
      fi
      niri msg action consume-or-expel-window-right --id "$window_id"
    else
      [ "$(printf '%s' "$plan" | jq '.current | length')" -gt 1 ] || exit 0
      window_id=$(printf '%s' "$plan" | jq '.current[-1]')
      focus_id=$(printf '%s' "$plan" | jq '
        if .focused == .current[-1] then .current[-2] else .focused end')
      niri msg action consume-or-expel-window-left --id "$window_id"
      niri msg action focus-window --id "$focus_id"
    fi
    ;;
  focus-window)
    [[ "${2:-}" =~ ^[0-9]+$ ]] || exit 2
    exec niri msg action focus-window --id "$2"
    ;;
  clipboard-list) exec cliphist list ;;
  clipboard-copy)
    [[ "${2:-}" =~ ^[0-9]+$ ]] || exit 2
    clipboard_tmp=$(mktemp)
    trap 'rm -f -- "$clipboard_tmp"' EXIT
    printf '%s\t' "$2" | cliphist decode > "$clipboard_tmp"
    wl-copy < "$clipboard_tmp"
    ;;
  notifications) exec makoctl history -j ;;
  lock) exec systemctl --user start ohmansy-lock.service ;;
  power-action)
    case "${2:-}" in
      lock) exec "$0" lock ;;
      logout) exec niri msg action quit ;;
      suspend)
        "$0" lock
        exec systemctl suspend
        ;;
      reboot) exec systemctl reboot ;;
      shutdown) exec systemctl poweroff ;;
      *) exit 2 ;;
    esac
    ;;
  control-action)
    case "${2:-}" in
      displays) exec "$0" menu displays ;;
      sound) command=(pavucontrol) ;;
      network) command=(nm-connection-editor) ;;
      bluetooth) command=(blueman-manager) ;;
      wallpaper) command=("$0" wallpaper-set) ;;
      ribbons)
        rm -f -- "${XDG_STATE_HOME:-$HOME/.local/state}/ohmansy/wallpaper"
        exec systemctl --user restart ohmansy-wallpaper.service
        ;;
      *) exit 2 ;;
    esac
    # GUI tools must survive closing or restarting the launcher.
    exec systemd-run --user --collect --quiet -- "${command[@]}"
    ;;
  wallpaper-set)
    image=$(zenity --file-selection --title="Choose wallpaper" \
      --file-filter="Images | *.png *.jpg *.jpeg *.webp *.bmp") || exit 0
    [ -f "$image" ] || exit 1
    state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/ohmansy"
    mkdir -p -- "$state_dir"
    wallpaper_tmp=$(mktemp "$state_dir/wallpaper.XXXXXX")
    trap 'rm -f -- "$wallpaper_tmp"' EXIT
    realpath -- "$image" > "$wallpaper_tmp"
    mv -- "$wallpaper_tmp" "$state_dir/wallpaper"
    systemctl --user restart ohmansy-wallpaper.service
    ;;
  *) exit 2 ;;
esac
