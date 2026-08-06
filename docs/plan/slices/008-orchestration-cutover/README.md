# 008 — Orchestration cutover

<!-- markdownlint-configure-file { "MD043": { "headings": ["# 008 — Orchestration cutover","## Goal","## Appetite","## Core","## In scope","## Out of scope","## Governed by","## Acceptance","## Rabbit holes","## Done when","## Revisions"] } } -->

## Goal

Shipped `oneshot`, `vetted`, and `prex` behavior round-trips through workflows before old orchestrators are removed.

## Appetite

3 implementation sessions. Chosen before the design below.

## Core

All three public behaviors prove parity through workflows before any retirement, leaving nonessential cleanup depth as remainder.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Move each behavior one at a time and retain rollback until its parity test passes.
- Remove per-table `cmd_skill_lint.sh` entries for deleted skills, add workflow replacements, update producer-blind maps, and remove the dead type-2 review-loop boundary rule.
- Sweep the four non-skill files named by the retirement draft and rewrite telemetry to workflow keys.
- Keep executor-capability calibration as immutable historical evidence marked retired. Prose cleanup is cut first.

## Out of scope

- Deleting historical calibration or claiming it measured workflows.
- Changing user-visible behavior without a parity test.

## Governed by

- `docs/plan/slices/007-executor-workflow-adoption/README.md` — first adopted executor path.
- `docs/decisions/0010-executor-preparation-and-artifacts.md` — public behavior and artifacts.
- `docs/decisions/0017-skill-authoring-and-lint.md` — curated lint tables.
- `docs/explanation/executors.md` — current executor design.

## Acceptance

```text
When each shipped executor behavior runs through workflows, the system shall match its existing artifacts and terminal outcome. -> test/integration/cmd_executor_workflow.bats
When obsolete skills are removed, skill-lint tables, producer maps, telemetry keys, and four named non-skill references shall contain no stale identifier. -> test/integration/cmd_skill_lint.bats
```

## Rabbit holes

- Big-bang deletion can erase a rollback path — escape: cut over one behavior only after its parity case passes.
- Historical telemetry can be mistaken for workflow evidence — escape: mark it retired and immutable, never rewrite it.

## Done when

All three parity paths pass before old orchestrators are absent, cleanup assertions pass, and milestone 008 flips to `done`.

## Revisions

None.
