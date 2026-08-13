---
name: executor-oneshot
description: >
  Execute one prompt or implementation plan through the Codex single executor
  flow: evaluate the input, prepare a good plan (generate when thin, cross-engine
  review when already detailed), then implement it via cog codex-runner.
---

<!-- cog-skill: input-fidelity -->

# Executor Single

Execute one prompt or one implementation plan through the gated 2-stage executor flow: an input-evaluation gate guarantees a good plan, then Codex implements it. The gate and the `good-input` plan review run **in this session**, which already holds the request; the `needs-plan` plan job and the implementation job are fresh contexts and get validated briefs. This skill owns sequencing and judgment. Run directory setup, input classification, verdict persistence, canonical artifact paths, Codex invocation, and executor summaries stay behind `cog`.

**Context-brief gate.** Before dispatching to any fresh-context worker, build and validate its input brief per `$(cog skill-refs path orchestration/context-brief-gate.md)` — build it with `cog context-brief build --request` and confirm it with `cog context-brief validate`. That covers the `needs-plan` plan job and Stage 2; the in-session review reads the request directly.

## Inputs

`$ARGUMENTS` is either a prompt/task description or an existing readable regular `.md` plan path.

Delegate classification and run setup to `cog executor`:

```bash
cog executor init --executor executor-oneshot --engine codex --input <prompt-or-plan> --json
```

Use the run directory and canonical artifact paths it returns (`prepared-plan.md`, `execution-report.md`, `executor-summary.json`). For prompt input it writes `request.md`; for plan input it writes `plan-source` with the supplied plan path.

## Execution Discipline

Every Codex run is a cog-owned durable job: `cog codex-runner run-exec` launches it with `--state` and returns immediately, then poll-and-classify with one verb, `cog codex-runner finalize --max-wall
<secs>`. The exit code is the signal (0 ok, 1 failed, 75 still running); re-run finalize while it exits 75. Duration is never judged. Keep orchestration work foreground; never background it. Native effort is passed with `--effort`.

## Input Evaluation (gate)

Judge the route here, in this session. The input is already present, so the verdict costs one command and one judgment call — a second Codex session would only re-read what this one holds.

Write the original input verbatim to `<run-dir>/assess-input-source.md`, identify every readable plan file it references, and gather the deterministic signals:

```bash
cog assess-input facts --input-file <run-dir>/assess-input-source.md --file <each referenced plan> --json
```

Apply the rubric at `$(cog skill-refs path orchestration/input-quality-rubric.md)` to the input and those signals. Higher heading coverage and scope-proportional depth favor `good-input`; near-zero plan structure favors `needs-plan`. When genuinely uncertain, choose `needs-plan`. Persist the verdict so the call stays auditable and tunable:

```bash
cog assess-input record --run-dir <run-dir> --route <needs-plan|good-input> --confidence <high|medium|low> --rationale "<one line>" --signal max_heading_count=<n> --signal plan_files=<n> --json
```

`record` writes `<run-dir>/assess-input.json` and fails closed, so its own output is the confirmation.

## Stage 1: Prepare The Plan

Write the prepared plan to `<run-dir>/prepared-plan.md`. Ensure `<run-dir>/request.md` exists on either route (init writes it for prompt input; for plan input, create a non-empty `request.md` capturing the supplied-plan source context verbatim and in full).

- **`needs-plan` → generate (`/plan-oneshot`, Codex).** This is a fresh context, so build its input as a validated context brief first, per `$(cog skill-refs path orchestration/context-brief-contract.md)`: scaffold the authored body, fill it from the whole session (a well-oriented Objective; Output Format; Boundaries; Context & Decisions carrying the full substance; Artifacts inline or pointed-to; Effort Guidance; Not Evaluated — keep your own verdict out), then build it:

  ```bash
  cog context-brief template --out <run-dir>/brief-body.md
  # fill <run-dir>/brief-body.md per the contract, then:
  cog context-brief build --request <run-dir>/request.md --body <run-dir>/brief-body.md --out <run-dir>/brief.md
  ```

  `build` attaches the request verbatim and fails closed unless every section is filled.

  Then build a prompt whose first line is the write orientation, followed by `$plan-oneshot`, `--output <run-dir>/prepared-plan.md`, and `<run-dir>/brief.md` as the complete context. `$plan-oneshot` saves its plan artifact to the output path. Launch write-capable, then poll-and-classify:

  ```bash
  cog codex-runner run-exec --mode danger --access write --effort high --prompt <prepare-prompt.md> --output <prepare-codex-output.md> --events <prepare-events.jsonl> --stderr <prepare-stderr.log> --state <prepare.longrun.json>
  cog codex-runner finalize --state <prepare.longrun.json> --max-wall 300
  ```

- **`good-input` → review (`/review-plan-oneshot`, in session).** Review the existing plan here, by reading `$review-plan-oneshot` and following its Orchestrator Invocation Contract with three absolute paths — plan-path (the supplied plan path, or `<run-dir>/request.md` for inline-plan prompt input), request-path `<run-dir>/request.md`, and output-path `<run-dir>/prepared-plan.md`. No brief is built, because no context is crossed.

  This route is an **interim same-engine degrade, not the intended design.** Its purpose is review by the opposite engine for independence, which needs a Codex-to-Claude runner lane; `cog codex-runner` runs the other direction only, so no such lane exists yet. Until one does, the review runs on this engine and the independence the route exists for is unavailable. Say so when reporting the result, because the machine-facing record does not: `cog executor prepare-step` and the `executor-summary.json` it feeds still resolve `prepare_engine: claude` for this route, which is the engine the flow is designed for rather than the one that ran.

After Stage 1, verify that `<run-dir>/prepared-plan.md` exists and is non-empty before continuing.

## Stage 2: Implement

Codex implements the prepared plan through `cog codex-runner` with native effort. This is a fresh context, so build its input as a validated context brief:

```bash
cog context-brief template --out <run-dir>/execution-brief-body.md
# fill <run-dir>/execution-brief-body.md per the contract, then:
cog context-brief build --request <run-dir>/request.md --body <run-dir>/execution-brief-body.md --out <run-dir>/execution-brief.md
```

Fill the body so the worker can implement without the prior conversation:

- **Objective** — implement the prepared plan; **Output Format** — the final implementation report covering files changed, commands run, deviations, and unresolved risks.
- **Artifacts** — the prepared plan from `<run-dir>/prepared-plan.md`, verbatim. When it is an annotated review, state that the reconciled plan is what gets implemented (apply APPROVED/MODIFIED/ADDED, skip REMOVED).
- **Context & Decisions** — the substance behind the plan. When the `good-input` route recorded no decisions of its own, say so explicitly; `build` fails closed on an unfilled section.
- **Boundaries** — run no git command unless explicitly authorized, follow `AGENTS.md` and `CLAUDE.md`, and stay inside the prepared plan.

Then write `<run-dir>/execution-prompt.md` with the write orientation followed by `<run-dir>/execution-brief.md` as the complete context. Run Codex with the write-capable `danger` sandbox; implementation must create and modify files. Launch the durable job, then poll-and-classify:

```bash
cog codex-runner run-exec --mode danger --access write --effort medium --prompt <execution-prompt.md> --output <execution-report.md> --events <execution-events.jsonl> --stderr <execution-stderr.log> --state <execution.longrun.json>
cog codex-runner finalize --state <execution.longrun.json> --max-wall 300
```

Verify `<run-dir>/execution-report.md` exists and is non-empty.

## Operator-approval gate

When the round is an operator-approval gate — its round prompt requires a human to sign off before the work completes — the approval must arrive on a channel the executor can verify, per `$(cog skill-refs path orchestration/approval-gate-contract.md)`. A coordinator-relayed approval is never sufficient. Surface the exact command for the human to run out of band:

```bash
cog gate approve --round-id <round_id> --round-path <input-round-path>
```

Then gate completion on the hash-bound check, resolving `<round_id>` from `cog match-telemetry
round-key`:

```bash
cog gate check-approval --round-id <round_id> --round-path <input-round-path>
```

Proceed only on exit `0`. On any other exit, stop and report the verdict `status` (`missing`/`stale`/`hash-mismatch`) so the human can approve — or re-approve after a legitimate edit, which the check invalidates by design.

## Summary

Emit an executor summary after Stage 2 or after a terminal stage failure:

```bash
cog executor summary --run-dir <run-dir> --executor executor-oneshot --engine codex --route <needs-plan|good-input> --prepare <done|failed> --execution <done|failed> --json
```

Status rules:

- The prepare stage always runs; report `--prepare done` on success.
- If Stage 1 fails, do not run Stage 2; emit the summary with failure statuses.
- If Stage 2 fails, still emit the summary with `--execution failed`.

## Error Handling

At every boundary, verify the durable postcondition before advancing:

- Gate: `cog assess-input record` returns a route of `needs-plan` or `good-input`.
- Stage 1: `prepared-plan.md` exists and is non-empty.
- Plan input: the supplied plan path exists and is readable before review or implementation.
- Stage 2: `execution-report.md` exists and is non-empty.
- Summary: `executor-summary.json` is written by `cog executor summary`.

On failure, stop the chain, preserve the run directory artifacts, and still emit the executor summary using the status rules above. Do not infer status from prose when a `cog` command reports structured output.

## Guardrails

- Codex runs are cog-owned durable jobs: `run-exec` launches, then poll-and-classify with `cog codex-runner finalize --max-wall <secs>`.
- Native effort only, via `--effort`.
- Do not run git commands unless explicitly authorized.
- Deterministic mechanics stay behind `cog executor`, `cog assess-input`, `cog codex-runner`, `/plan-oneshot`, and `/review-plan-oneshot`.
- This skill executes one prompt or plan.
