# Milestones

The single status surface. One line per slice, ordered by id inside its section: `<id> <slug> — <status> — <appetite>[ — <note>]`.

Two sections, live work first. Status is one of `shaped`, `active`, `done`, `cut`, or `reshaped`. A slice moves to `## closed` when its status becomes terminal — `done`, `cut`, or `reshaped` — and never moves back. A `reshaped` line names its successor id in the note; a `cut` line names what was cut.

What bounds this work is in the [charter](./charter.md); what could still change it is in [open questions](./open-questions.md).

## in flight

- 004 [composites-loops-and-recovery](./slices/004-composites-loops-and-recovery/README.md) — shaped — 3 sessions — adds composites, lazy loop rounds, and crash recovery
- 005 [orchestrator-conformance](./slices/005-orchestrator-conformance/README.md) — shaped — 2 sessions — vendor-neutral fixture and the orchestrator reference page
- 006 [provider-runners](./slices/006-provider-runners/README.md) — shaped — 3 sessions — adds `claude-runner` beside the existing `codex-runner` contract
- 007 [executor-workflow-adoption](./slices/007-executor-workflow-adoption/README.md) — shaped — 3 sessions — routes one real executor workflow through the accepted contract
- 008 [orchestration-cutover](./slices/008-orchestration-cutover/README.md) — shaped — 3 sessions — moves `oneshot`, `vetted`, and `prex` one at a time with rollback retained
- 009 [installation-and-retirement](./slices/009-installation-and-retirement/README.md) — shaped — 2 sessions — install and uninstall completeness plus the stale-reference sweep

## closed

- 001 [documentation-architecture-reset](./slices/001-documentation-architecture-reset/README.md) — done — 3 sessions — archive hashes and all documentation gates passed
- 002 [workflow-engine-go-no-go](./slices/002-workflow-engine-go-no-go/README.md) — done — 2 sessions — accepted the engine in ADR-0027, closed Q-001..Q-004, and published the contract
- 003 [linear-workflow-vertical](./slices/003-linear-workflow-vertical/README.md) — done — 3 sessions — landed the workspace, twelve verbs, the validator, per-file layer resolution, and the receipt contract; the registry grew past the accepted seed
