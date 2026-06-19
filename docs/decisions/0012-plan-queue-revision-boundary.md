# ADR-0012: Plan Queue Revision Boundary

## Context and Problem Statement

`runner-queue` must reconcile implementation plans with repository state after committed work,
before selecting more work. Without a revision boundary, remaining `todo` and `backlog` items can
drift from code that has already landed, causing duplicate work or missed regressions.

## Considered Options

- No revision step; rely on the next executor to notice drift.
- Runner-owned revision logic inside `runner-queue`.
- Dedicated project-local revision skill with deterministic `cog` scan, verify, and queue helpers.

## Decision Outcome

Chosen option: **Dedicated project-local revision skill with deterministic `cog` mechanics** —
revision needs judgment, but queue mutation, fingerprints, verification, and commit parsing must stay
machine-checkable.

The revision is adaptive: it may revise remaining `todo` and `backlog` plan or round files, mark
already implemented mutable items `done`, and append new rounds or plans for gaps. It never edits
recorded history for `done` items. The runner invokes it after every committed inner round and every
committed main plan, reconciling the main queue and all inner queues.

The revision subagent runs `.claude/skills/plans-revision` as a foreground sibling boundary. It
auto-applies allowed edits, verifies them with `cog plans-revision-verify`, and commits drift through
`/gc` itself. No drift is a no-op. Any scan, verification, or commit failure is fail-closed and stops
the parent runner.

## Verify Scope and Known Limitations

`cog plans-revision-verify` is the deterministic gate. It mechanically enforces, fail-closed: every
`done` item present in the before-scan still exists under the same `(queue_path, schema)`, is still
`done`, and keeps its queue-YAML `prompt`, `depends_on`, and `notes` fields unchanged; and every
after-queue re-validates. It *reports* (does not reject) mutable-item changes via `new_items` and
`status_changes`, and a `changed` flag from the coarse plans fingerprint.

Two immutability promises in this skill are therefore backed by skill discipline plus the coarse
plans fingerprint, **not** by a per-target deterministic check in verify:

- Mutable (`todo`/`backlog`) items must be mutated only via `cog queue-status-set` /
  `cog queue-append` (append-only, no reorder, no direct prompt/notes rewrite). Verify reports such
  changes but does not reject a hand-rewrite of a mutable item.
- A `done` item's recorded *prose* file content is not fingerprinted per item; verify compares only
  the queue-YAML metadata above. Editing a `done` item's prose file flips `changed` but still passes
  `completed_history_preserved`.

These are deliberate boundaries for this round: per-item mutable append-only enforcement and a
prompt→path prose fingerprint (with a fail-closed branch for unresolvable targets) are non-trivial
mechanics deferred as a candidate Round 3 hardening, not a defect in the Round 2 contract. The
runner's durable postcondition is "no drift, or a verified-and-committed revision" at the granularity
above; tightening verify can supersede this ADR later without editing it.

## Consequences

- Good: The runner gets a durable postcondition: either no drift or verified committed revision.
- Good: Deterministic queue writes remain limited to `cog queue-status-set` and `cog queue-append`.
- Bad: Revision spends one foreground subagent level from the fixed five-level depth budget.
- Bad: Verify's deterministic immutability check covers `done`-item queue metadata, not mutable-item
  append-only discipline or `done`-item prose content (see Verify Scope and Known Limitations).

## Status

Accepted
