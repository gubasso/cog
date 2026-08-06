# Milestones

<!-- markdownlint-configure-file { "MD043": { "headings": ["# Milestones"] } } -->

The single status surface. Status is one of `shaped`, `active`, `done`, `cut`, or `reshaped`. A `reshaped` row names its successor id in the note; a `cut` row names what was cut.

What bounds this work is in the [charter](./charter.md); what could still change it is in [open questions](./open-questions.md).

| id  | slice                                                                                       | status | appetite   | note                                                     |
| --- | ------------------------------------------------------------------------------------------- | ------ | ---------- | -------------------------------------------------------- |
| 001 | [documentation-architecture-reset](./slices/001-documentation-architecture-reset/README.md) | done   | 3 sessions | Archive hashes and all documentation gates passed.       |
| 002 | [workflow-engine-go-no-go](./slices/002-workflow-engine-go-no-go/README.md)                 | active | 2 sessions | Closes Q-001..Q-004 and accepts or rejects the proposal. |
| 003 | [linear-workflow-vertical](./slices/003-linear-workflow-vertical/README.md)                 | shaped | 3 sessions | Conditional on an accepted go decision in 002.           |
| 004 | [composites-loops-and-recovery](./slices/004-composites-loops-and-recovery/README.md)       | shaped | 3 sessions | Conditional on an accepted go decision in 002.           |
| 005 | [orchestrator-conformance](./slices/005-orchestrator-conformance/README.md)                 | shaped | 2 sessions | Conditional on an accepted go decision in 002.           |
| 006 | [provider-runners](./slices/006-provider-runners/README.md)                                 | shaped | 3 sessions | Conditional on an accepted go decision in 002.           |
| 007 | [executor-workflow-adoption](./slices/007-executor-workflow-adoption/README.md)             | shaped | 3 sessions | Conditional on an accepted go decision in 002.           |
| 008 | [orchestration-cutover](./slices/008-orchestration-cutover/README.md)                       | shaped | 3 sessions | Conditional on an accepted go decision in 002.           |
| 009 | [installation-and-retirement](./slices/009-installation-and-retirement/README.md)           | shaped | 2 sessions | Conditional on an accepted go decision in 002.           |
