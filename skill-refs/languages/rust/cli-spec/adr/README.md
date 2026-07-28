# ADRs

Architecture Decision Records for changes to this spec.

## Format

One file per decision: `NNNN-kebab-title.md`, where `NNNN` is a zero-padded sequence number. Numbers never get reused; superseded ADRs stay in place with a `**Status:** Superseded by ADR-NNNN` line at the top.

## Template

```markdown
# ADR-NNNN — Title

**Status:** Proposed | Accepted | Superseded by ADR-NNNN **Date:** YYYY-MM-DD

## Context

What's the situation that requires a decision? What constraints apply? Cite specific chapters of the spec or files in reference projects.

## Decision

What we're doing. One paragraph, declarative.

## Consequences

What changes after this decision: which chapters update, which templates update, which projects need migration. Include the explicit downsides.

## Alternatives considered

Brief notes on options that were rejected and why.
```

## When to write one

- Changing a rule in any chapter (e.g. swapping figment for config-rs).
- Adding or removing a default dependency.
- Changing the canonical directory tree.
- Choosing between mutually exclusive options when a chapter says "pick one".

Don't write an ADR for:

- Typo fixes, formatting, link updates.
- New examples added to existing chapters.
- New ADRs themselves.
