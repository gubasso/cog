# ADR-0051: Requirement IDs for round coverage

## Context and Problem Statement

ADR-0050 defines recursive round splitting and requires scope conservation, but count-based coverage is too weak: a child can invent a new criterion while losing a parent criterion and still preserve the same count. Text-only matching is also brittle when a splitter moves surrounding detail or lightly rewords prose.

The split loop needs a stable requirement identity that lives in the round files, works with existing markdown checklists, and can be introduced without changing the plan writer first.

## Decision Outcome

Use inline, plan-scoped requirement IDs on acceptance criteria:

```text
- [ ] (R3) The command fails closed when coverage loses a parent requirement.
```

`cog round-req stamp` owns allocation. It scans the plan directory for the current max, assigns monotonic `R1`, `R2`, ... IDs to untagged non-boilerplate acceptance criteria, and never renumbers existing IDs. `cog round-req list` reads IDs and normalized criterion text. `cog round-split coverage` keys on IDs when present and falls back to normalized criterion text for legacy untagged criteria.

Ownership is:

- caller stamps before grading so seam hints and coverage can use IDs;
- splitter stamps defensively before writing children and after adding new child criteria;
- evaluator reads IDs only and recommends stamping when inputs are unstamped.

The Template-A queue completion criteria are bookkeeping, not implementation requirements, and are excluded from stamping, listing, and coverage.

## Consequences

- Good: a child cannot mask a lost parent criterion by adding unrelated work.
- Good: existing markdown checklist rendering remains compatible.
- Good: the system can adopt IDs idempotently without changing the plan writer first.
- Bad: IDs are only plan-scoped, so cross-plan uniqueness is not guaranteed.
- Deferred: a global or cross-session requirement registry, if a future workflow needs one.
