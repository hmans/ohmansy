---
title: Ohmansy engineering memory
description: Durable project knowledge for future agent sessions. Public repository content.
schema:
  type: object
  properties:
    kind:
      type: string
      enum: [architecture, workflow, pitfall, verification]
      description: What the document helps an agent understand or do.
    area:
      type: string
      enum: [project, app, nix, tooling]
    status:
      type: string
      enum: [current, historical, provisional]
      description: Current guidance, retained history, or an unverified hypothesis.
    reviewed:
      type: string
      pattern: '^\d{4}-\d{2}-\d{2}$'
      description: Date the content was checked against source or observed evidence; not a promise of fresh runtime state.
  required: [kind, area, status, reviewed]
  additionalProperties: false
---
# Engineering memory workflow

This collection stores durable knowledge, not transcripts, credentials, or task
queues. The root AGENTS.md contains mandatory project rules. Scoped AGENTS.md
files point to area guides in this collection. User documentation remains in docs/.
Memory explains important relationships, evidence, and lessons; link to the
canonical source instead of copying long instructions.

## Read at session start

From the repository root:

```sh
means info --path memory
means list --path memory
means search cursor --path memory
means show ID --path memory
```

Search the task's area and read relevant documents before changing code. Use
`--filter area=nix` or another area when helpful. If means is unavailable, read
MEANS.md and the Markdown files directly. Do not install it just to read memory.
Use literal/text search by default. Do not configure embeddings or send content
to an embedding provider as part of routine maintenance.

Machine-wide embedding settings can make `create` or `update` require a provider
even for this collection. For offline writes, run Means with `XDG_CONFIG_HOME`
pointing to a temporary empty directory. Do not change the user's global config
or request credentials just to maintain these notes. Text search needs no embeddings.

## Maintain at task completion

- Record material discoveries, constraints, and verified fixes. Do not add a
  document for every turn, routine command, or speculative explanation.
- Search before creating. Update the existing topic when it is still the same
  subject. Keep titles concrete and use generated IDs for cross-references.
- Read with `means show ID --path memory --json` before updating. Supply the
  returned hash to `means update`; reconcile conflicts instead of overwriting.
  See `means create --help` and `means update --help` for JSON input formats.
- Separate observations from hypotheses. A build, successful boot, and user
  confirmation are different evidence. Cite paths, commands, or a CI run.
- Mark stale material historical, or replace it in place and explain the new
  state. Review dates must reflect an actual review. Verify live state again
  before acting on a VM, SSH endpoint, artifact, or process.
- Keep private/local details in ignored `.local/SESSION.md`, if needed. Never
  store passwords, key contents, tokens, logs, machine IDs, or personal configs
  in this collection. Do not copy the reference flake here.
- Run `means doctor --path memory` after changes. Review the diff as public
  content. Do not commit `.means/` caches or machine embedding configuration.

## Writing a useful memory

State the current rule or finding first. Explain why it matters, where the
implementation lives, and how it was verified. Include known limits and a
safe next check. Keep commands short and reusable; do not embed local account
names or absolute paths into shared instructions.
