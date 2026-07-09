# ADR-0074: Forge-resistant operator-approval gate

## Context and Problem Statement

An operator-approval gate is a queue round that must not complete on machine judgment alone: a human
signs off before the executor flips the round to `done`. A gate executor runs in a fresh context
reached only through its orchestrating coordinator, so it must reject any coordinator-relayed approval
("the user said yes") as unverifiable — proxy-mistrust. Without a side channel this deadlocks: the
executor can never be satisfied. A live run broke the deadlock by hand-editing `queue-rounds.yaml`,
which defeats the gate and should not be the mechanism.

## Considered Options

- Keep hand-editing the queue as the documented override (forgeable, defeats the gate).
- Let the coordinator relay approval with a token (still coordinator-controlled, still forgeable).
- A hash-bound approval file the human writes via a `cog` verb and the executor reads itself.

## Decision Outcome

Chosen option: **hash-bound approval file.** New `cog gate` subverbs, backed by
`lib/functions/fn_gate_approval.sh`, own the mechanics. `cog gate approve --round-id --round-path`
writes `${XDG_STATE_HOME}/cog/approvals/<round-id>.json` binding the approval to the SHA-256 of the
round file at approval time. `cog gate check-approval` exits `0` only when a matching approval exists,
its recorded hash still equals the round file's current hash (editing the round after approval
invalidates it → `hash-mismatch`), and it is within TTL (default 900s → `stale`); a missing file is
`missing`. `cog gate prune-approvals` clears expired files. The rule is codified once in
`skill-refs/orchestration/approval-gate-contract.md`; gate executors reference it rather than inlining.
Because the file lives outside the coordinator's reach and the check re-hashes the round now, a relayed
claim can never satisfy the gate — and never needs to.

## Consequences

- Good: the deadlock is resolved without a forgeable override; edit-after-approval and staleness are
  caught deterministically; the contract is a single source of truth.
- Bad: the human must run one out-of-band command; approvals are machine-local state (not in the repo),
  pruned on a TTL.

## Status

Implemented — enacted in `lib/functions/fn_gate_approval.sh`, `lib/commands/cmd_gate.sh`, `bin/cog`,
`skill-refs/orchestration/approval-gate-contract.md`, and the `executor-oneshot`/`runner-plan` skills.
