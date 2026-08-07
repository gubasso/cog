# Template — ADR

Copy the block below into `<project>/docs/decisions/template.md`, and name each filled record `ADR-<number>-<decision>.md` — the `ADR-` prefix is required, on the record but not on this template. Filled ADRs must stay at or below 350 words. Keep each field brief; split separate decisions into separate ADRs. The five sections below are a fixed shape shared by every record and by this template; [the heading-shape template](./template-heading-shapes.md) ships the gate that holds it.

```markdown
# ADR-NNNN: <short title naming the choice, not the task>

## Context and Problem Statement

<2-3 sentences. What problem? Why does it matter?>

## Considered Options

- <option 1>
- <option 2>
- <option 3>

## Decision Outcome

Chosen option: `<option 1>` — <one sentence: why>.

## Consequences

- Good: <positive trade-off>
- Bad: <negative trade-off>

## Status

<Ideation | Proposed | Accepted | Implemented | Deprecated | Superseded | Rejected>

<If Implemented: link to the code that enacts it. If Superseded: link to the successor. If Deprecated: say why it no longer applies. If a later ADR changes part of a decision that still stands, keep the status and add "Amended by ADR-NNNN — <what changed>" here, so no reader follows a stale detail.>
```
