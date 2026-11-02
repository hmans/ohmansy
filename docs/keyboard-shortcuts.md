# Keyboard shortcuts

`Mod` is Niri's Super modifier. These bindings do not change the keyboard layout,
Alt/Super mapping, or Caps Lock behavior. Press **Mod+Shift+/** for the Quickshell
shortcut panel. Search by action, category, or key; use Up/Down or Page Up/Down
to scroll, and Escape to close. In the Mac host, lock guest input to send shortcuts that macOS would
otherwise intercept.

## Applications and desktop menus

| Shortcut | Action |
| --- | --- |
| Mod+Return | Open Foot |
| Mod+E | Open Files |
| Mod+Space | Application launcher |
| Mod+Shift+Space | Search open windows |
| Mod+Shift+V | Clipboard history; select an entry to copy it |
| Mod+N | Notification history; select an entry to read its body |
| Mod+Comma | Sound, network, Bluetooth, and wallpaper controls |
| Mod+X | Power menu |
| Mod+Alt+L | Lock the screen |
| Mod+Shift+E | Quit Niri with its confirmation prompt |

The launcher supports typing to filter, Up/Down to select, Enter to activate,
and Escape to close. Opening the same menu again closes it. Power actions that
end or suspend the session require confirmation, with Cancel selected first.

Clipboard history starts collecting when the desktop service runs. It uses
Cliphist's per-user database; notification history uses Mako's last 100 retained
notifications. Neither history is written to the system configuration or Git.
Bluetooth controls need a Bluetooth adapter; the development VM has none.

The wallpaper controls can select an image or return to animated ribbons.
An image selection is saved under the user's XDG state directory and survives
desktop restarts.

## Navigation and movement

| Shortcut | Action |
| --- | --- |
| Mod+W or Mod+Q | Close the focused window |
| Mod+Tab | Toggle overview |
| Mod+Left/Right | Focus a column, then the adjacent monitor at the edge |
| Mod+Up/Down | Focus a window, then the adjacent workspace at the edge |
| Mod+H/J/K/L | Focus left/down/up/right within the workspace |
| Mod+Shift+Left/Right | Move the column |
| Mod+Shift+Up/Down | Move the window, crossing workspace boundaries |
| Mod+Ctrl+Left/Right | Focus the adjacent monitor |
| Mod+Ctrl+Shift+Left/Right | Move the column to the adjacent monitor |
| Mod+Page Up/Down | Focus the adjacent workspace |
| Mod+Shift+Page Up/Down | Move the column to the adjacent workspace |

## Layout

| Shortcut | Action |
| --- | --- |
| Mod+R / Mod+Shift+R | Cycle column widths forward/backward |
| Mod+Ctrl+R / Mod+Ctrl+Shift+R | Cycle window heights forward/backward |
| Mod+Minus/Equal | Reduce/increase column width by 10% |
| Mod+F | Maximize column |
| Mod+Shift+F | Fullscreen window |
| Mod+Shift+C | Center column |
| Mod+Ctrl+C | Center visible columns together |
| Mod+U | Toggle column tabs |
| Mod+I | Pull a window into the column from the right |
| Mod+O | Split the bottom window into a column on the right |
| Mod+Shift+I | Pull the top window from the left column into this column |
| Mod+Shift+O | Split the bottom window into a column on the left |
| Mod+Shift+T | Toggle floating |

Column width presets are 25%, 33⅓%, 50%, 66⅔%, and 83⅓% of the working area.
Window heights use Niri's default presets.

## Screenshots and media

| Shortcut | Action |
| --- | --- |
| Print | Screenshot selection |
| Ctrl+Print | Screenshot screen |
| Alt+Print | Screenshot window |
| Volume up/down | Adjust volume by 3%, capped at 100% |
| Speaker/microphone mute | Toggle the default device's mute state |
| Play, next, previous | Control an MPRIS media player |

Screenshots exclude the pointer. Media keys also work while the screen is locked.

## Implementation and checks

Bindings and help labels share `nix/modules/desktop/shortcuts.json`.
The desktop module generates Niri's bindings from these definitions; the
Quickshell panel reads the installed copy. User-added bindings outside this
file are not listed in the panel. Fixed desktop actions are packaged
from `nix/modules/desktop/actions.sh`; launcher modes share the existing
Quickshell launcher. Clipboard data is restored by numeric history ID, never
evaluated as a command. Swaylock uses the system PAM configuration.

Run `node --test tools/tests/desktop-menus.test.mjs tools/tests/shortcuts.test.mjs` and
`python3 -m unittest tools.tests.test_desktop_actions` for menu and helper tests.
The Python helper tests require `jq`. Niri's `validate` command checks the KDL,
and the installed-system build runs ShellCheck on the packaged helper.
