# ADR-0024: Skill reference self-containment golden rules

## Context and Problem Statement

Runtime skills had two load-bearing reference leaks: some pointed at the maintenance-only Codex
conventions document, and some resolved private DocsNNotes paths. Shipped skills must work from a
fresh `cog` install without private checkouts or source-repo maintenance docs.

## Considered Options

- Keep the references and rely on graceful degradation.
- Copy reference prose into each consuming skill.
- Make `cog codex-runner` and `skill-refs/` the runtime reference boundaries.

## Decision Outcome

Chosen option: **make `cog codex-runner` and `skill-refs/` the runtime reference boundaries** —
skills use the `cog codex-runner` command surface for Codex mechanics, and load-bearing shared
references live in `skill-refs/` and resolve with `cog skill-refs path <rel>`.

## Consequences

- Good: runtime skills are self-contained and installable without DocsNNotes.
- Good: `docs/reference/codex-conventions.md` stays maintenance-only.
- Bad: maintainers must import shared reference updates into `skill-refs/`.

## Status

Implemented. Extends [ADR-0017](0017-reference-self-containment.md) and
[ADR-0023](0023-skill-refs-unified-resource-sot.md), and is enforced by `cog skill-lint` over both
runtime `skills/**/SKILL.md` bodies and the runtime `skill-refs/**` references they load (the
`skill-refs/templates/**` deploy payload is exempt).
