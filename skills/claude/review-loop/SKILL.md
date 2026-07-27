---
name: review-loop
description: >
  Automated review loop: Codex reviews uncommitted changes, Claude delegates
  triage to review-findings, applies fixes, and repeats until clean, approved,
  stalled, user-limited, or aborted.
argument-hint: "[task context or path to review_loop_input.json]"
context: fork
agent: general-purpose
allowed-tools: Bash Read Write Edit Skill
---

<!-- trigger-tests: "review loop", "keep reviewing until clean", "iterative code review", "multi-pass review with Codex" -->
<!-- cog-skill: input-fidelity -->

# Review Loop

Round 1 invokes the Codex `review-oneshot` twin in orchestrator mode against the live diff: a fresh
from-scratch review with full input (task, reviewed plan, context, changed files). Rounds 2+ resume
that same reviewer thread — warm context that retains every prior round — and in each resumed round
the reviewer both re-checks whether prior findings were resolved and performs a full re-review for new
regressions in the applied fixes. Claude delegates finding triage to `/review-findings`, applies fixes
marked `FIXED`, and repeats until the review is clean, approved, genuinely stalled, explicitly
limited, or aborted by the user.

**Completion contract.** The loop is complete only when `$RUN_DIR/summary.md` exists — assembled and
asserted by `cog review-loop-summary finalize --run-dir "$RUN_DIR"`, whose printed `REVIEW_LOOP_OK`
line is the run's trailing result line (see Terminate and Result Line Contract). `summary.md` is the
single exit artifact for every termination reason, including when the work looks finished after a
round's fixes. Reaching a clean or fixed state is not the end of the run; running `finalize` is. Its
two inputs — the narrative body (`summary-body.md`) and the termination reason
(`termination-reason.txt`) — are maintained as durable run-dir artifacts during the loop, so
termination is a single mechanical command with no narrative authored in the moment of stopping.
Triage narrative belongs in `summary.md`, never as a freeform reply.

Codex invocation mechanics are owned by `cog codex-runner` (`run-exec`, `run-resume`, `extract-thread`,
`gate`, `orientation`, `finalize`, `explain-status`). Prepend `cog codex-runner orientation read-only`
to every Codex review prompt. Round 1 runs cold via `run-exec`; rounds 2+ run warm via `run-resume`
against the round-1 reviewer thread.

**Context-brief gate.** Before dispatching to any fresh-context worker, build and validate its input
brief per `$(cog skill-refs path orchestration/context-brief-gate.md)` — build it with
`cog context-brief build --request` and confirm it with `cog context-brief validate`.

## Inputs

Handoff mode: `$ARGUMENTS` is a `review_loop_input.json` path. Validate it first:

```bash
cog review-loop-input validate --input "$ARGUMENTS"
```

Use `task`, `reviewed_plan`, and `implementation_review` as context. `plan_thread_id` and `impl_thread_id`
are informational. When the input carries an optional `context` value — a rich-context brief conforming
to `$(cog skill-refs path orchestration/context-brief-contract.md)` — use it verbatim as the round-1
context brief instead of assembling a new one.

Standalone mode: use `$ARGUMENTS`, conversation context, and read-only git inspection commands to
understand the work. If intent is unclear, ask one focused question before round 1.

An explicit user-supplied round limit is allowed. Otherwise rounds are uncapped and stop by the
termination rules below.

## Run Directory And Preflight

Create a run directory:

```bash
cog rundir review-loop
```

Run the sandbox gate once:

```bash
cog codex-runner gate sandbox "$RUN_DIR/preflight.json" || exit 1
SANDBOX_MODE="$(jq -r '.codex_session.sandbox_mode' "$RUN_DIR/preflight.json")"
```

Artifacts:

- `round-N-context.md`
- `round-N-prompt.txt`
- `round-N-findings.json`
- `round-N-events.jsonl`
- `round-N-stderr.log`
- `round-N-runner.json`
- `round-N-triage.md`
- `followups.md`
- `summary-body.md` (the narrative body, maintained after each round)
- `termination-reason.txt` (recorded when a termination condition fires)
- `summary.md`

## Round Context

Round 1 context is a best-constructed context brief at `$RUN_DIR/round-1-context.md` conforming to
`$(cog skill-refs path orchestration/context-brief-contract.md)`: the task as the raw request, a
well-oriented objective, and the reviewed plan plus prior implementation-review findings as context
and artifacts. When the handoff input already carries a `context` brief, write it to
`$RUN_DIR/round-1-context.md` verbatim; otherwise assemble it inline via `/context-builder`. Either
way, gate it before use:

```bash
cog context-brief validate "$RUN_DIR/round-1-context.md"
```

The Codex twin captures the live diff itself; the brief carries intent and prior state.

Rounds 2+ resume the round-1 reviewer thread, so the reviewer already retains the task, plan, and
every prior-round finding. The resumed round prompt is short: it carries only what is new — a brief
summary of fixes since the previous round, any user guidance, and the dual instruction to (a) confirm
whether prior findings were resolved and (b) re-review the current diff for new regressions. Prior
findings come from the reviewer's retained context, not a cold re-injection.

## Review Round

Round 1 (cold): build `$RUN_DIR/round-1-prompt.txt` with `$review-oneshot <context> <output-marker>`
and a read-only orientation. Launch through `cog codex-runner run-exec` with `medium` effort — the
HIGH tier's Codex cell (`gpt-5.5@medium`). After `finalize`, capture the reviewer thread id for resume:

```bash
cog codex-runner extract-thread "$RUN_DIR/round-1-events.jsonl" last
```

`round-1-runner.json` also surfaces `.thread_id` and `.account`; persist both for later rounds.

Rounds 2+ (warm): build `$RUN_DIR/round-N-prompt.txt` with the read-only orientation and the resumed
dual instruction above. Launch through `cog codex-runner run-resume --account <account>
--thread-id <thread-id>` with `low` effort — the MEDIUM tier's Codex cell (`gpt-5.5@low`).

For every round use `finalize --max-wall <secs>` until it exits 0, 1, or 75; exit 75 means still
running and should be polled again.

Validate the runner result and ensure `$RUN_DIR/round-N-findings.json` is non-empty JSON with a
`findings` array.

Terminate immediately when `.findings == []` or `.decision == "approve"`.

## Triage

Invoke `/review-findings` inline with the round findings JSON, task context, reviewed plan, prior
triage, and accumulated followups. Save its structured report to `$RUN_DIR/round-N-triage.md`.
Append the report's `Followups` decisions, deferrals, and open questions to `$RUN_DIR/followups.md`.

After each round, update `$RUN_DIR/summary-body.md` — the terminal narrative body — to the current
state under its required section headings: what was implemented across rounds, a `Files changed`
section, a `Remaining findings` section, and a `Followups` section. This per-round update is a hard
boundary postcondition, enforced in Terminate; keeping it current leaves termination as a single
mechanical command.

Apply minimal code edits for findings marked `FIXED`. Pause only for `NEEDS_DISCUSSION`, errors, user
abort, or an explicit user limit.

Applying a round's fixes is a continuation point, not a stopping point. After applying the `FIXED`
edits for a round that has no `NEEDS_DISCUSSION`, run the next (resumed) round to confirm the fixes
hold and surface regressions. The loop ends only when a termination condition in Terminate is met, and
it ends by running `finalize` to write `summary.md`.

After round 2 and later, compute deterministic progress:

```bash
cog review-loop-progress --current "$RUN_DIR/round-N-findings.json" --previous "$RUN_DIR/round-(N-1)-findings.json" --json
```

Use `new[]`, `recurring[]`, `resolved[]`, and `churn_ratio` to judge whether the loop is genuinely
stalling on repeated unresolvable findings. The stall decision remains prose judgment.

## Terminate

Stop on:

- empty findings;
- `decision == "approve"`;
- orchestrator-judged stall;
- explicit user round limit;
- `NEEDS_DISCUSSION` requiring user input;
- user abort;
- runner or validation error.

Do not ask whether to continue between successful rounds. "Fixes applied" is not in this list and is
never terminal — only the conditions above are. Each condition maps to one termination reason: empty
findings → `findings-empty`, approve → `decision-approve`, stall → `stall`, user round limit →
`user-limit`, `NEEDS_DISCUSSION` → `needs-discussion`, user abort → `user-abort`, runner or validation
error → `error`.

Per-round postcondition (hard boundary check): every round boundary completes only once
`$RUN_DIR/summary-body.md` is current — it carries `Files changed`, `Remaining findings`, and
`Followups` sections plus what was implemented across rounds. `finalize` reads this file; a round that
applied fixes but left the body stale or unwritten is incomplete. Confirm the body is current before
advancing to the next round or terminating.

On whichever condition fires, terminate with two commands. First record the reason (`<reason>` is the
mapped value above); then run the single terminal command, whose printed `REVIEW_LOOP_OK` line is the
reply's trailing block with nothing after it:

```bash
cog review-loop-summary set-reason --run-dir "$RUN_DIR" --reason <reason>
cog review-loop-summary finalize --run-dir "$RUN_DIR"
```

`finalize` reads the maintained `summary-body.md` and recorded reason, derives the round count and
`Per-round counts` section from `round-N-findings.json`, assembles `$RUN_DIR/summary.md`, and fails
closed if the body is absent, empty, or missing a required section — `cog` never fabricates a
narrative. On success it prints the canonical `REVIEW_LOOP_OK <run-dir> rounds=<n> reason=<reason>`
line. It is idempotent: a re-run against an already-valid `summary.md` re-emits that same line.

Recovery (body-less run): when a boundary owner or parent orchestrator inherits a run whose
`summary-body.md` was never written — a child that stopped after applying fixes without maintaining the
body — it recovers by supplying the narrative it independently verified:

```bash
cog review-loop-summary set-reason --run-dir "$RUN_DIR" --reason <reason>
cog review-loop-summary finalize --run-dir "$RUN_DIR" --body-file <verified-body.md>
```

`--body-file` is used only when `summary-body.md` is absent; the supplied file must carry the same
required sections (`Files changed`, `Remaining findings`, `Followups`) and passes the identical
fail-closed checks, so `cog` still fabricates no narrative. The recovery `finalize` prints the same
canonical `REVIEW_LOOP_OK` line and stays idempotent.

When the loop cannot reach a summary at all — a runner or validation error before any round produced
findings — end instead with `cog msg failed review-loop "<reason>"` so the caller receives a definite
`REVIEW_LOOP_FAILED` signal rather than silence.

## Result Line Contract

<!-- cog-terminal-contract: REVIEW_LOOP_OK -->

Every run ends with exactly one canonical status line, emitted as the trailing block of the reply with
nothing after it:

- `REVIEW_LOOP_OK <run-dir> rounds=<n> reason=<reason>` — surfaced verbatim from
  `cog review-loop-summary finalize`, which prints it only after `summary.md` is written and asserted;
  a boundary-owner recovery finalize (`finalize --body-file`) emits this identical line, so the
  handshake is unchanged whether the run terminated normally or was recovered;
- `REVIEW_LOOP_FAILED <reason>` — from `cog msg failed review-loop "<reason>"` when no summary could
  be produced.

This line is the run's machine-readable handshake: a caller reads it to confirm completion. Per-round
detail, triage narrative, and followups live in `summary.md`. The run is complete — and this line is
emitted — only once `cog review-loop-summary finalize` has written and asserted `summary.md`.

## Guardrails

- Codex never edits code; it reviews in read-only mode.
- Claude applies only triaged `FIXED` changes.
- Never mutate git state from this skill.
- Keep deterministic mechanics in `cog`; keep triage and stall judgment in skill prose.
