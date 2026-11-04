# Spatial window experiment

The ohmansy spatial lab is a Rust and OpenGL playground for window scale,
perspective, and animation. It runs as an ordinary Wayland window inside the
current Niri desktop. Existing applications remain in place.

For real interactive Wayland clients, use `mise run compositor` instead. See
[nested compositor development](compositor-development.md). The lab described
here is the separate capture-based rendering experiment.

## Run

```sh
mise run spatial
```

On a fresh NixOS checkout, bootstrap with `bash tools/dev/spatial.sh run` once.
The launcher enters the pinned Nix development environment, installs the Rust
version from `mise.toml` through NixOS's patched rustup, and registers it with
mise. This avoids the generic Linux loader problem in mise's Rust installer.
Cargo keeps incremental build outputs in ignored `.build/spatial/`. No OS
rebuild, logout, or compositor replacement is needed.

The lab captures up to sixteen current Niri windows at startup. Select a card
or an entry in the window list to bring it forward. Use:

- Left and Right arrows to select a window.
- Drag across the scene to orbit.
- Scroll over the scene to zoom.
- Scale, Tilt, Depth, Spacing, and Distance to adjust the presentation.
- R or **Reset view** to restore the view.
- **Refresh windows** to capture the current windows again.
- **Test surfaces** for generated images with fine detail at 2x resolution.

Closing the lab closes only the preview. It does not stop application processes,
send commands to terminal windows, or change the desktop configuration.

## What this proves

The renderer uses textured rectangles in a perspective scene. Texture coordinates
are perspective-correct; mipmaps filter windows that recede into the background.
Pointer selection uses the inverse of the same transform used for rendering.
The window list reports each source image's actual pixel dimensions.

This is a capture viewer, not a Wayland compositor yet. Captures are snapshots;
clicking them selects the card rather than interacting with the original app.
Moving or closing the original window does not change its existing capture until
the next refresh. Captured images retain their source resolution: the lab does
not ask existing applications to render at 2x. The generated test surfaces do
contain 2x detail for experimenting with minification.

Niri's screenshot action also updates the clipboard. Before capture, the lab
reads every advertised regular-clipboard format, then restores them after capture
if the selection still matches its screenshot. It leaves a newer selection alone.
A small source process keeps the restored clipboard available after the lab
closes and exits when that clipboard source is replaced. The primary selection
is untouched. Screenshot notifications or entries in clipboard history may still
appear. Capture files use a private temporary directory that is removed after
loading; no window images are written into the repository.

## Development checks

```sh
mise run spatial-check
mise run spatial -- --demo
mise run spatial -- --demo --close-after 10
mise run spatial -- --demo --close-after 10 --screenshot .local/spatial.png
```

The check task runs formatting, perspective-picking tests, and Clippy. The demo
option needs no window capture. The deadline closes only the preview itself.
The built executable's `--capture-check` exercises real window capture and
clipboard restoration without opening the preview.

The source is in `experiments/spatial/`. Keep experiments outside the installed
desktop until their behavior is ready to ship. A later compositor can reuse the
scene transforms and renderer while replacing snapshots with live Wayland
surfaces and routing input to their clients.
