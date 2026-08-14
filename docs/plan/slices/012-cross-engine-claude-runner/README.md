# 012 — Cross-engine Claude runner

## Goal

A Codex-hosted skill dispatches Claude the way a Claude-hosted skill dispatches Codex, and the `executor-oneshot` `good-input` route performs the cross-engine review it exists for.

## Appetite

2 implementation sessions. Chosen before the design below.

## Core

`cog claude-runner` launches a durable Claude job from a Codex host and classifies it from artifacts alone, leaving the shared-mechanics hoist and the `codex-runner` preflight retrofit as remainder.

## In scope

This is the ordered negotiable remainder, cut last-first from the bottom of the list.

- Add `cog claude-runner` with the verb set a caller already knows from `codex-runner`: `run-exec`, `finalize`, and `gate`. The exit-code protocol is unchanged — `0` done ok, `1` done failed, `75` still running — because the whole point is that a Codex host drives it with the same `$?` branch a Claude host uses today.
- Check version and authentication preconditions before creating the durable state file, per [ADR-0031](../../../decisions/ADR-0031-preflight-provider-preconditions-before-the-durable-job.md). This is the load-bearing part: `claude-session` execs its child, so wrapper and agent status ranges overlap and a runner that launches first cannot tell them apart afterwards.
- Restore the Codex `executor-oneshot` `good-input` route to a real cross-engine call and delete the interim same-engine degrade the skill currently narrates.
- Let the caller supply the engine that actually prepared, so `executor-summary.json` records the host that ran rather than the engine the flow table assigns. Only the twin knows its own host; `(executor, engine, route)` cannot separate the two `executor-oneshot` twins because both pass `--engine codex`.
- Hoist the provider-neutral mechanics `codex-runner` carries today into a shared helper both runners source: the absolute-artifact-path guard, the prompt/output collision guard, the state-file label derivation, the launch working-directory resolution, and the run-directory snapshot and proof verbs. Extract each one as `claude-runner` reaches it, not as a separate pass, because a second copy is cheap to avoid while the second runner is being written and expensive to unpick afterwards.
- Retrofit the same preflight onto `codex-runner`, which lacks it today. Cut first.

## Out of scope

- Credential management. Reporting a precondition is diagnosis; satisfying one is account management, rejected by [ADR-0009](../../../decisions/ADR-0009-orchestration-and-durable-jobs.md) and by [ADR-0031](../../../decisions/ADR-0031-preflight-provider-preconditions-before-the-durable-job.md).
- Any vendor-neutral runner contract or capability table. That surface belonged to the withdrawn workflow engine and stays in the draft workspace. Sharing mechanics that are already provider-neutral is not that surface: a helper both runners call is not a contract either runner answers to.
- A third provider, and any registry of providers.

## Governed by

- `docs/decisions/ADR-0031-preflight-provider-preconditions-before-the-durable-job.md` — why preconditions are checked before the durable job exists, and why status stays artifact-classified.
- `docs/decisions/ADR-0009-orchestration-and-durable-jobs.md` — the durable-job model and the foreground rule the new runner inherits.
- `docs/reference/orchestration-contract.md` — the launch, classify, and access rules both runners answer to.
- `docs/plan/open-questions.md` — Q-007, which this slice exits.

## Acceptance

```text
When a Codex host dispatches Claude, the runner shall launch a detached durable job and classify its outcome from artifacts alone. -> test/integration/claude_runner.bats
If a version or authentication precondition fails, then the runner shall report it and create no durable state file. -> test/integration/claude_runner.bats
When a twin reports the engine that prepared its work, the executor summary shall record that engine rather than the flow-table default. -> test/integration/cmd_executor.bats
When shared mechanics move to a helper, the codex runner shall keep its observable behavior unchanged. -> test/integration/codex_runner.bats
```

## Rabbit holes

- A shared runner abstraction over both providers invites the vendor-neutral contract this slice excludes — escape: the line is drawn at provider behavior. Argument-vector construction, effort and access spelling, precondition shape, resume identity, and status classification stay duplicated per runner, because the two CLIs disagree on every one of them and a translation layer over that disagreement needs correcting on each provider release. Only mechanics that are already provider-neutral move, and the durable-job layer both runners stand on is shared today without either owning a contract.
- Reading provider prose to classify an ambiguous exit status — escape: the preflight exists precisely so the status never needs disambiguating; no runner parses stderr text.
- Re-opening which engine reviews which route — escape: the flow table is unchanged, and only the recorded host is corrected.

## Done when

The named integration tests pass unskipped, the Codex `executor-oneshot` `good-input` route names no degrade, Q-007 leaves `open-questions.md`, and the `milestones.md` line flips.

## Revisions

2026-08-14, before work started: added the provider-neutral mechanics hoist to the remainder, second-from-bottom. Raised by asking why the two runners are separate commands rather than one command with an engine flag. The answer kept the commands separate — the flag would unify exactly the surface where the two CLIs disagree, and half its options would be illegal for each engine — but it found real duplication one level down, in mechanics that carry nothing provider-shaped. Placed above the `codex-runner` retrofit because deferring it means unpicking a second copy rather than not writing one.
