# ADR-0025: SoT executor delegation

## Context and Problem Statement

Some skills duplicated shared judgment workflows inline, which made their behavior drift. The reference case is review-loop reimplementing finding triage that belongs in review-findings.

## Considered Options

- Keep duplicating shared workflow prose in each caller.
- Move all judgment into shell commands.
- Delegate shared judgment workflows to one canonical executor skill.

## Decision Outcome

Chosen option: **delegate shared judgment workflows to one canonical executor skill** — callers keep sequencing and context assembly, while the executor skill owns the reusable judgment contract and output shape.

## Consequences

- Good: one reviewable source of truth for shared judgment behavior.
- Good: callers can persist structured outputs without re-coding the workflow.
- Bad: executor skills need stable input and output contracts for callers.

## Status

Implemented. The reference case is `review-loop` delegating triage to `review-findings`.
