# ADR-0021: Ship lean deploy payloads

<!-- markdownlint-configure-file { "MD043": { "headings": ["# ADR-0021: Ship lean deploy payloads","## Context and Problem Statement","## Considered Options","## Decision Outcome","## Consequences","## Status"] } } -->

## Context and Problem Statement

Templates copied into user projects can accumulate mirrored invariants and defensive runtime checks. Payloads should contain only what makes the domain work, with cross-file guarantees tested at the source.

## Considered Options

- Defensive templates with repeated checks
- Documentation-only templates
- Minimal payloads with local actionable notes and source-tree tests

## Decision Outcome

Chosen option: `Use minimal payloads with local actionable notes and source-tree tests` — it reduces deployed complexity without losing invariant coverage.

## Consequences

- Generated projects receive smaller artifacts.
- Repository tests must own cross-file invariants.

## Status

Implemented

Enacted by [skills and resources](../explanation/skills-and-resources.md) and the [governance payload](../../skill-refs/templates/governance/AGENTS.md).
