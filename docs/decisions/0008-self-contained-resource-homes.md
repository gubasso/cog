# ADR-0008: Use self-contained resource homes

<!-- markdownlint-configure-file { "MD043": { "headings": ["# ADR-0008: Use self-contained resource homes","## Context and Problem Statement","## Considered Options","## Decision Outcome","## Consequences","## Status"] } } -->

## Context and Problem Statement

Shipped workflows must be understandable from a fresh clone and installed payload. Prose read by models and structured data computed by the CLI require distinct owners.

## Considered Options

- Depend on external local shelves
- Put all resources under data
- Keep prose in skill-refs and CLI data in data

## Decision Outcome

Chosen option: `Keep prose in skill-refs and CLI data in data` — it preserves repository self-containment and executable data ownership.

## Consequences

- Fresh clones contain all load-bearing knowledge.
- Public links remain further reading only.

## Status

Implemented

Enacted by [skills and resources](../explanation/skills-and-resources.md) and [`skill-refs`](../../skill-refs/docs-design/README.md).
