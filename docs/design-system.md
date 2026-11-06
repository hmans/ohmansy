# ohmansy design system

The shared QML components live in `nix/modules/ui/`. Use these components and
their theme tokens for new UI rather than assigning colors to individual buttons.

## Name and copy

Always write **ohmansy** in lowercase, including headings, window titles,
buttons, and sentence beginnings. This is a display-name rule; preserve existing
code identifiers, QML module names such as `Ohmansy.Ui`, and filesystem paths.

The experimental window manager and Wayland compositor is named **Shine**.
Use that capitalization for its titles, session label, and documentation.

Use short, direct headings and action labels. Avoid decorative step captions
such as “01 / WELCOME,” slogans, and repeated branding. The installer has one
brand label at the top and no branded footer. Numbered lists are fine when they
describe an actual sequence of steps.

## Button roles

Set `GlassButton.actionRole` according to what the action does:

| Role | Fill | Text | Use |
| --- | --- | --- | --- |
| `primary` | Muted purple glass | Near white | Main next action: Get started, Continue, Install, Shut down |
| `secondary` | Neutral slate glass | Near white | Supporting actions: Refresh, Show/Hide installation log |
| `return` | Subtle slate glass | Muted near white | Back, Cancel, return to disk selection or the desktop |

`Theme.qml` owns the `buttonPrimary`, `buttonSecondary`, and `buttonReturn`
fill and text tokens. Keep the existing glass treatment; do not replace it with
bright solid fills or invisible outlined buttons. Software rendering uses the
corresponding `Solid` tokens: primary `#51405f`, secondary `#30333f`, return
`#252835`. Hover and press use the shared surface feedback, keyboard focus
uses the shared outline, and disabled buttons reduce label and surface opacity.
Do not use color as the only indication of what a button does.

Use one primary action per screen. Destructive actions must name their effect
explicitly: “Erase disk and install ohmansy.” The installer also shows the disk
identity and an unchecked erasure acknowledgement before enabling that action.

Existing `primary: true` consumers map to the primary role; the default role is
secondary. New code should use `actionRole` explicitly. These shared styles
also apply to existing greeter and first-boot buttons.

## Type and surfaces

Use Inter through `Theme.fontFamily`. Shared controls use `Theme.radius` (14 px).
The desktop defaults to Source Sans 3 for Fontconfig sans-serif and
system-ui, with GTK's interface font set to Source Sans 3 11. The shell retains
Inter; browser and Electron interfaces use Source Sans 3.
Websites that specify their own fonts retain them. Installed systems need a
rebuild to receive these defaults; running browsers may need a restart.
Glass surfaces retain their translucent treatment where graphics support it,
while software rendering preserves the same muted color hierarchy.

Desktop notifications use `Ohmansy.Notifications`, shared by Shine and Niri.
Their cards and history panel use `GlassSurface`, `GlassButton`, and `Theme`
directly, so their font, corners, surfaces, and action roles stay consistent.
Critical messages include an Urgent label. Supporting notification actions use
the secondary button role; dismiss controls use the return role. Notification
popups never request keyboard focus; opening history does.

## Preview and verification

Keep the installer's main actions in a bottom bar outside the scrolling content.
Reserve its height in the content viewport so it never covers the form. Put Back
before the primary action; use a row where it fits and stack at widths below
560 px. Disk warnings and acknowledgement remain in the form; the fixed erase
button still requires explicit acknowledgement.

The content switches from two columns to one below 900 px. Narrow windows and
windows shorter than 650 px use smaller headings, fewer forced line breaks,
and tighter spacing. Use available height as well as width when adapting layouts.

Use `mise run installer-ui` for installer iteration. Shared UI components are
packaged by Nix, so restart the preview after changing their implementation.
Installer-local QML reloads on save. Run the `installer-ui` flake check to render
all screens at wide, compact, short, and narrow sizes and exercise confirmation
safeguards. The render check also verifies that action buttons stay within the
window, their labels fit, and the scrolling content stops above the action bar.
