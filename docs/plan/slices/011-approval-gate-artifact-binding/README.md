# 011 — Approval gate artifact binding

## Goal

The operator-approval gate names the artifact it binds, and no cog surface still asks the operator about a round.

## Appetite

1 implementation session. Chosen before the design below.

## Core

`cog gate` approves and checks one work artifact end to end, leaving the wording of the surrounding prose as remainder.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Rename the two gate flags and the record keys onto the artifact, bumping the three changed schemas.
- Retarget the approval-gate contract onto the single-artifact executor terminus.
- Update the three executor skills that surface the approve command to the operator.
- Update the mirrored command reference. Prose breadth is cut first.

## Out of scope

- The gate's forge resistance, its hash binding, and its TTL, all unchanged.
- Loop rounds in `review-loop`, `precommit-fix`, and `gc`, which are a different concept.

## Governed by

- `docs/decisions/ADR-0033-bind-the-approval-gate-to-one-artifact.md` — what the gate binds and why the flags moved.
- `docs/decisions/ADR-0022-forge-resistant-approval.md` — the approval mechanism that survives unchanged.
- `docs/decisions/ADR-0032-remove-the-plan-vault-and-the-round-layer.md` — the retirement that orphaned the vocabulary.
- `skill-refs/orchestration/approval-gate-contract.md` — the prose contract the executors read.

## Acceptance

```text
When an operator approves work, cog shall take the gate identity and the artifact under approval and reject a round-named flag. -> test/integration/cmd_gate.bats
When a gate executor reaches its terminus, the approval check shall bind the verdict to the artifact path and its current hash. -> test/integration/cmd_gate.bats
```

## Rabbit holes

- A bare `round` sweep can strip the review, commit, and workflow loops that legitimately count rounds — escape: every edit is anchored to the gate surface by name.
- A rename can drift into re-deciding the gate — escape: the hash binding, the TTL, and the proxy-mistrust rule are copied across untouched.

## Done when

The gate tests pass unskipped, no cog surface names a round outside a loop that counts them, and the `milestones.md` line flips.

## Revisions

None.
