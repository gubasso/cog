# Milestones

The single status surface. One line per slice, ordered by id inside its section: `<id> <slug> — <status> — <appetite>[ — <note>]`.

Two sections, live work first. Status is one of `shaped`, `active`, `done`, `cut`, or `reshaped`. A slice moves to `## closed` when its status becomes terminal — `done`, `cut`, or `reshaped` — and never moves back. A `reshaped` line names its successor id in the note; a `cut` line names what was cut.

What bounds this work is in the [charter](./charter.md); what could still change it is in [open questions](./open-questions.md).

Ids 002 through 009 are retired and must never be reused. They shaped the workflow engine, which returned to its defining phase on 2026-08-14: the slices, the ADRs, the contracts, and the shipped verbs were all removed from the repository together, and the design continues in the gitignored draft workspace. A slice returns here only when work on it is ready to start again.

## in flight

## closed

- 001 [documentation-architecture-reset](./slices/001-documentation-architecture-reset/README.md) — done — 3 sessions — archive hashes and all documentation gates passed
- 010 [plan-vault-retirement](./slices/010-plan-vault-retirement/README.md) — done — 3 sessions — removed the vault, the queues, the round layer, the spec pipeline, and executor match telemetry
- 011 [approval-gate-artifact-binding](./slices/011-approval-gate-artifact-binding/README.md) — done — 1 session — rebound the operator-approval gate onto the artifact it hashes
- 012 [cross-engine-claude-runner](./slices/012-cross-engine-claude-runner/README.md) — done — 2 sessions — added `claude-runner`, hoisted the shared runner mechanics, preflighted both runners, and exited Q-007
