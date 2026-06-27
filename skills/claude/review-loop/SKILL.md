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

**Completion contract.** The loop is complete only when `$RUN_DIR/summary.md` exists, written via
`cog review-loop-summary build` (Final Output). This is the single exit artifact for every
termination reason — including when the work looks finished after a round's fixes. Reaching a clean
or fixed state is not the end of the run; writing `summary.md` is.

Codex invocation mechanics are owned by `cog codex-runner` (`run-exec`, `run-resume`, `extract-thread`,
`gate`, `orientation`, `finalize`, `explain-status`). Prepend `cog codex-runner orientation read-only`
to every Codex review prompt. Round 1 runs cold via `run-exec`; rounds 2+ run warm via `run-resume`
against the round-1 reviewer thread.

<!-- cog-context-brief-gate -->

**Context-brief gate.** Before `/review-loop` dispatches to any fresh-context worker — an Agent subagent
or a `cog codex-runner` Codex job — build its input as a validated context brief from your whole
accumulated raw context: attach the raw request as-is, author an oriented objective, carry the full
substance and load-bearing artifacts, and omit your own verdict. Build the brief with `cog
context-brief build` and confirm it with `cog context-brief validate` before dispatch.

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
and a read-only orientation. Launch through `cog codex-runner run-exec` with `medium` effort (the
Codex HIGH cell). After `finalize`, capture the reviewer thread id for resume:

```bash
cog codex-runner extract-thread "$RUN_DIR/round-1-events.jsonl" last
```

`round-1-runner.json` also surfaces `.thread_id` and `.account`; persist both for later rounds.

Rounds 2+ (warm): build `$RUN_DIR/round-N-prompt.txt` with the read-only orientation and the resumed
dual instruction above. Launch through `cog codex-runner run-resume --account <account>
--thread-id <thread-id>` with `low` effort (the Codex MEDIUM cell).

For every round use `finalize --max-wall <secs>` until it exits 0, 1, or 75; exit 75 means still
running and should be polled again.

Validate the runner result and ensure `$RUN_DIR/round-N-findings.json` is non-empty JSON with a
`findings` array.

Terminate immediately when `.findings == []` or `.decision == "approve"`.

## Triage

Invoke `/review-findings` inline with the round findings JSON, task context, reviewed plan, prior
triage, and accumulated followups. Save its structured report to `$RUN_DIR/round-N-triage.md`.
Append the report's `Followups` decisions, deferrals, and open questions to `$RUN_DIR/followups.md`.

Apply minimal code edits for findings marked `FIXED`. Pause only for `NEEDS_DISCUSSION`, errors, user
abort, or an explicit user limit.

Applying a round's fixes is a continuation point, not a stopping point. After applying the `FIXED`
edits for a round that has no `NEEDS_DISCUSSION`, run the next (resumed) round to confirm the fixes
hold and surface regressions. The loop ends only when a termination condition below is met, and it
ends by writing `summary.md`.

After round 2 and later, compute deterministic progress:

```bash
cog review-loop-progress --current "$RUN_DIR/round-N-findings.json" --previous "$RUN_DIR/round-(N-1)-findings.json" --json
```

Use `new[]`, `recurring[]`, `resolved[]`, and `churn_ratio` to judge whether the loop is genuinely
stalling on repeated unresolvable findings. The stall decision remains prose judgment.

## Termination

Stop on:

- empty findings;
- `decision == "approve"`;
- orchestrator-judged stall;
- explicit user round limit;
- `NEEDS_DISCUSSION` requiring user input;
- user abort;
- runner or validation error.

Do not ask whether to continue between successful rounds. On whichever condition fires, proceed
directly to Final Output and write `summary.md`; every termination path ends there.

## Final Output

Write the narrative body to `$RUN_DIR/summary-body.md` with these required section headings, each
followed by its content (`cog` fails closed when a required narrative section is absent):

- what was implemented across rounds;
- a `Files changed` section: files changed across the loop;
- a `Remaining findings` section: findings still open at termination;
- a `Followups` section: accumulated followups and important decisions.

Then assemble and validate the terminal summary as the mandatory final step. `cog` derives the round
count and `Per-round counts` section from `round-N-findings.json`, prepends the title and termination
reason, writes `$RUN_DIR/summary.md`, and fails closed if the result is empty, missing its title or
termination reason, or missing a required narrative section:

```bash
cog review-loop-summary build --run-dir "$RUN_DIR" \
  --termination-reason <reason> --body "$RUN_DIR/summary-body.md"
```

`<reason>` is one of `findings-empty`, `decision-approve`, `stall`, `user-limit`, `needs-discussion`,
`user-abort`, or `error`. Report total rounds and the termination reason to the user.

## Guardrails

- Codex never edits code; it reviews in read-only mode.
- Claude applies only triaged `FIXED` changes.
- Never mutate git state from this skill.
- Keep deterministic mechanics in `cog`; keep triage and stall judgment in skill prose.
