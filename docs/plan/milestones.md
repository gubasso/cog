# Milestones

<!-- markdownlint-configure-file { "MD043": { "headings": ["# Milestones","## in flight","## closed"] } } -->

The single status surface. One line per slice, ordered by id inside its section: `<id> <slug> — <status> — <appetite>[ — <note>]`.

Two sections, live work first. Status is one of `shaped`, `active`, `done`, `cut`, or `reshaped`. A slice moves to `## closed` when its status becomes terminal — `done`, `cut`, or `reshaped` — and never moves back. A `reshaped` line names its successor id in the note; a `cut` line names what was cut.

What bounds this work is in the [charter](./charter.md); what could still change it is in [open questions](./open-questions.md).

## in flight

- 002 [workflow-engine-go-no-go](./slices/002-workflow-engine-go-no-go/README.md) — active — 2 sessions — closes Q-001..Q-004 and accepts or rejects the proposal
- 003 [linear-workflow-vertical](./slices/003-linear-workflow-vertical/README.md) — shaped — 3 sessions — conditional on an accepted go decision in 002
- 004 [composites-loops-and-recovery](./slices/004-composites-loops-and-recovery/README.md) — shaped — 3 sessions — conditional on an accepted go decision in 002
- 005 [orchestrator-conformance](./slices/005-orchestrator-conformance/README.md) — shaped — 2 sessions — conditional on an accepted go decision in 002
- 006 [provider-runners](./slices/006-provider-runners/README.md) — shaped — 3 sessions — conditional on an accepted go decision in 002
- 007 [executor-workflow-adoption](./slices/007-executor-workflow-adoption/README.md) — shaped — 3 sessions — conditional on an accepted go decision in 002
- 008 [orchestration-cutover](./slices/008-orchestration-cutover/README.md) — shaped — 3 sessions — conditional on an accepted go decision in 002
- 009 [installation-and-retirement](./slices/009-installation-and-retirement/README.md) — shaped — 2 sessions — conditional on an accepted go decision in 002

## closed

- 001 [documentation-architecture-reset](./slices/001-documentation-architecture-reset/README.md) — done — 3 sessions — archive hashes and all documentation gates passed
