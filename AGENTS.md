# try ohmansy

Native macOS host for the independent Ohmansy NixOS desktop.
Use `apply_patch`, simple English, and Conventional Commits. Do not spawn agents
or push unless asked. Preserve unrelated changes.

## Session workflow

1. Inspect Git status and read [README.md](README.md).
2. Read [Means guidance](memory/MEANS.md), then run `means list --path memory`
   and search/read notes relevant to the task. Scoped AGENTS.md files point to
   area guides. Without Means, read the Markdown files directly.
3. Read ignored `.local/SESSION.md` if present. Verify live state before acting;
   local notes are not proof that a process, endpoint, or artifact still exists.
4. Run checks appropriate to the change. Update relevant memory and local handoff
   notes, then report what was verified. Distinguish built, booted, and running.

## Essential boundaries

- `flakey/` is ignored reference material, never an official flake input or staged
  content. Its old VM was deleted. Do not recreate it as a fallback.
- Keep credentials, VM state, generated bundles, and personal configuration out
  of Git. Keep accounts and disk identities out of reusable desktop modules.
- Never expose the host home directory to the guest.
- Use SSH or another explicit non-UI channel for guest commands and transfers.
  Never type or paste commands into terminal windows through computer use.
  Never request passwords in chat.
- Do not overwrite a running app bundle. Use clean shutdown; force stop is a
  power cut. Preserve installed guest users, storage, and state versions.
- The stopped launcher must not capture Mac shortcuts. Preserve the single
  window and explicit input-lock behavior; read app memory before changing it.

Detailed architecture, commands, troubleshooting, and verification live in
[Means memory](memory/MEANS.md). Keep this file short.
