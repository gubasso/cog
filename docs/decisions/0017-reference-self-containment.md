# ADR-0017: Reference self-containment

## Context and Problem Statement

Some shipped skills depended on skill-source reference documents in the external DocsNNotes
repository. A fresh `cog` install should not require that private reference shelf for runtime
behavior.

## Considered Options

- Keep loading internal skill-source references from DocsNNotes.
- Copy reference prose into every consuming skill.
- Ship shared skill-source references with `cog` and resolve them through a command.

## Decision Outcome

Chosen option: **ship shared skill-source references with `cog` and resolve them through a command**.
Runtime skill-source references live in-repo under `skill-refs/`, install to
`$XDG_DATA_HOME/cog/skill-refs`, and resolve through `cog skill-refs root` or
`cog skill-refs path <rel>`. Project documentation remains under `docs/` following Diataxis.

External general references, including DocsNNotes shelves, are optional enhancers only. They must
degrade gracefully when absent and must never be load-bearing internal runtime dependencies.

This complements [ADR-0008](0008-skill-script-boundary.md): skills keep judgment and sequencing,
while deterministic resolution of shipped reference content lives in `cog`.

## Consequences

- Good: fresh installs can run shipped skills without the maintainer's DocsNNotes checkout.
- Good: shared reference material has one packaged location instead of being copied into skills.
- Bad: maintainers must keep the packaged reference corpus synchronized when source guidance
  changes.

## Status

Accepted. Enacted by [`cog skill-refs`](../../lib/commands/cmd_skill_refs.sh) and the packaged
`skill-refs/` tree.
