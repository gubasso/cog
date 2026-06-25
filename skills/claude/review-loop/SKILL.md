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

# Review Loop

Each round invokes the Codex `review-oneshot` twin in orchestrator mode against the live diff.
Claude delegates finding triage to `/review-findings`, applies fixes marked `FIXED`, and repeats
until the review is clean, approved, genuinely stalled, explicitly limited, or aborted by the user.

Codex invocation mechanics are owned by `cog codex-runner` (`run-exec`, `gate`, `orientation`,
`finalize`, `explain-status`). Prepend `cog codex-runner orientation read-only` to every Codex review
prompt. Each review is a fresh one-shot; there is no Codex resume between rounds.

## Inputs

Handoff mode: `$ARGUMENTS` is a `review_loop_input.json` path. Validate it first:

```bash
cog review-loop-input validate --input "$ARGUMENTS"
```

Use `task`, `reviewed_plan`, and `stage4_review` as context. `plan_thread_id` and `impl_thread_id`
are informational.

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

Round 1 context includes the task, reviewed plan when present, and prior stage-4 findings when
present. Rounds 2+ include the same task/plan, previous triage, accumulated followups, a brief
summary of fixes since the previous round, and any user guidance.

The Codex twin captures the live diff itself. The context file carries intent and prior state.

## Review Round

Build `$RUN_DIR/round-N-prompt.txt` with `$review-oneshot <context> <output-marker>` and a
read-only orientation. Launch through `cog codex-runner run-exec` with `medium` effort for round 1
and `low` effort for later rounds. Use `finalize --max-wall <secs>` until it exits 0, 1, or 75;
exit 75 means still running and should be polled again.

Validate the runner result and ensure `$RUN_DIR/round-N-findings.json` is non-empty JSON with a
`findings` array.

Terminate immediately when `.findings == []` or `.decision == "approve"`.

## Triage

Invoke `/review-findings` inline with the round findings JSON, task context, reviewed plan, prior
triage, and accumulated followups. Save its structured report to `$RUN_DIR/round-N-triage.md`.
Append the report's `Followups` decisions, deferrals, and open questions to `$RUN_DIR/followups.md`.

Apply minimal code edits for findings marked `FIXED`. Pause only for `NEEDS_DISCUSSION`, errors, user
abort, or an explicit user limit.

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

Do not ask whether to continue between successful rounds.

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
