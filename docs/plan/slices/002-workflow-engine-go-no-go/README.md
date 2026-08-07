# 002 — Workflow engine go or no-go

## Goal

The project records one explicit accepted or rejected workflow-engine decision after Q-001 through Q-004 close.

## Appetite

2 implementation sessions. Chosen before the design below.

## Core

An ADR accepts or rejects the workflow engine, fixes its grammar and invocation boundary, and leaves no workflow-engine code written before that decision. [ADR-0027](../../../decisions/ADR-0027-accept-the-workflow-engine.md) is that record: it accepts the narrowed contract, and the four records it rests on settled engine selection, artifact passing, step exclusion, and loop convergence. The remainder funded evidence review and contract cleanup.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Record the accept-or-reject decision and every exit for Q-001 through Q-004.
- Publish the accepted grammar, engine registry, and validator rules as [workflow contract](../../../reference/workflow-contract.md), which owns them from here on. This plan keeps only the pointer.
- Register the eleven-engine seed for tracking so provider drift is re-checked rather than assumed.

## Out of scope

- Workflow-engine code, data files, commands, or runtime skills.
- Treating shaped successor slices as approval.
- Provider credential management or autonomous scheduling.

## Governed by

- `docs/reference/workflow-contract.md` — the published contract this slice produced.
- `docs/decisions/ADR-0023-select-workflow-engines-at-definition-or-call-site.md` — engine selection.
- `docs/decisions/ADR-0024-pass-step-artifacts-by-directory.md` — artifact passing and the descriptive input and output rule.
- `docs/decisions/ADR-0025-needs-is-the-only-edge-directive.md` — step exclusion.
- `docs/decisions/ADR-0026-judge-loop-convergence-with-a-prose-criterion.md` — loop convergence.
- `docs/decisions/ADR-0014-model-effort-and-power-grade.md` — the current tier concept that must remain intact unless a later decision changes only workflow use.
- `skill-refs/docs-design/06-appetite-and-scope.md` — fixed budget and cut order.
- `skill-refs/docs-design/07-plan-and-slices.md` — decision and successor-slice gate.
- `docs/reference/documentation-migration.md` — durable draft-fact ownership.

## Acceptance

```text
When Q-001 through Q-004 close, the project shall record one accepted or rejected workflow decision. -> test/integration/cmd_workflow.bats
If the proposal is rejected, then the milestone surface shall mark slices 003 through 009 `cut` and name the rejection. -> test/integration/cmd_workflow.bats
If the proposal is accepted, then the published contract shall enumerate all eleven engines and five invariants without creating runtime data in this slice. -> test/integration/cmd_workflow.bats
```

## Rabbit holes

- Specification expansion can consume the appetite — escape: decide only choices required for the go or no-go contract.
- Current provider rosters can drift during review — escape: treat the seed as proposal input and revalidate before acceptance.

## Done when

The ADR and Q-001..Q-004 exits are recorded. Q-001 exited through ADR-0023, which dissolved it by removing `--tier`; Q-002 through ADR-0027, which showed the grammar already admitted one legal shape; Q-003 through ADR-0025, which deleted the marker the question was about; and Q-004 through ADR-0024, which removed declared inputs. The durable contract migrated to `docs/reference/workflow-contract.md` and this plan keeps only pointers. A subsystem page waits for slice 003, because there is no built subsystem to describe yet and an empty scaffold is worse than none.

## Revisions

Engine-selection settlement: `Core`, `In scope`, and `Acceptance` changed when ADR-0023 removed `--tier`, renamed the per-step `cell:` to `engine:`, and cut the `cells:` override map. What changed them was evidence that `--tier` had no workable data source, since two of the five power-grade tiers name Codex cells the eleven-engine seed excludes as superseded, and that three writers for one value cost more than the one-off retune they bought.

Contract narrowing and migration: `Core`, `In scope`, and `Acceptance` changed again when ADR-0024 through ADR-0027 replaced declared output handles with directory passing, deleted the `sync:` marker in favour of `needs:`, made `until:` a judged prose criterion, and accepted the result. What changed them was evidence that a contract enforced at run time cannot bind a probabilistic producer, that `sync:` was depended on by two slices and declared by none, and that cog evaluating `until:` while the driver also reported an outcome left two authorities for one verdict.
