# Ohmansy and try ohmansy

Independent NixOS desktop, plus its native macOS host.
Write the product name as **ohmansy** in all user-facing copy. Follow
[the design system](docs/design-system.md) for copy and shared button roles.
Use `apply_patch`, simple English, and Conventional Commits. Do not spawn agents
or push unless asked. Preserve unrelated changes.

## Goals

- Ship a fantastic looking Linux desktop environment
- Prevent focus stealing through newly spawned windows
- In dark mode, automatically apply color grading to apps that don't support it

## Session workflow

1. Inspect Git status and read [README.md](README.md).
2. Read [Means guidance](memory/MEANS.md), then run `means list --path memory`
   and search/read notes relevant to the task. Scoped AGENTS.md files point to
   area guides. Without Means, read the Markdown files directly.
3. Read ignored `.local/SESSION.md` if present. Verify live state before acting;
   local notes are not proof that a process, endpoint, or artifact still exists.
   Identify the current OS, architecture, and whether this is a Mac host,
   installed Linux system, or disposable live ISO. On Linux, start with
   [Linux development](docs/linux-development.md). Never assume a Mac path,
   SSH endpoint, or local handoff file exists on another machine.
4. Run checks appropriate to the change. Update relevant memory and local handoff
   notes, then report what was verified. Distinguish built, booted, and running.

## Essential boundaries

- Implement shared OS and desktop changes in this repo's reusable modules,
  packages, and defaults so they ship in ohmansy. Use the current installation
  to test them; keep machine-only settings in its local configuration.
- For desktop styling, apply and verify changes in the running session by
  default: reload Shine settings or checkout QML, or gracefully replace only
  Quickshell. Preserve the compositor and application windows. Do not require
  logout for these changes. See [runtime iteration](docs/linux-development.md#iterate-in-the-running-desktop).
- `flakey/` is ignored reference material, never an official flake input or staged
  content. Its old VM was deleted. Do not recreate it as a fallback.
- Keep credentials, VM state, generated bundles, and personal configuration out
  of Git. Keep accounts and disk identities out of reusable desktop modules.
- Never expose the host home directory to the guest.
- Run commands directly when the agent is inside the target Linux system.
  From another machine, use SSH or another explicit non-UI channel for commands
  and transfers. A local Linux agent does not need the SSH development bridge.
  Never type or paste commands into terminal windows through computer use.
  Never request passwords in chat.
- Do not overwrite a running app bundle. Use clean shutdown; force stop is a
  power cut. Preserve installed guest users, storage, and state versions.
- The stopped launcher must not capture Mac shortcuts. Preserve the single
  window and explicit input-lock behavior; read app memory before changing it.
- Live USB homes are temporary. Save work to persistent storage or an authorized
  Git remote before shutdown. Never activate a factory/live profile on an
  installed system; retain its machine configuration and release pin.

Detailed architecture, commands, troubleshooting, and verification live in
[Means memory](memory/MEANS.md). Keep this file short.
