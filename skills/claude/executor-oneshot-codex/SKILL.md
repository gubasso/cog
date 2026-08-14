---
name: executor-oneshot-codex
description: >
  Execute one prompt or implementation plan through the Codex-backed single
  executor flow from Claude: evaluate the input, prepare a good plan (Codex plans
  when thin, Claude reviews in session when already detailed), then Codex implements.
model: opus
effort: low
argument-hint: "<prompt-or-plan-path>"
disable-model-invocation: true
allowed-tools: Bash Read Write Grep Glob WebSearch WebFetch
---

<!-- trigger-tests: "executor-oneshot-codex", "execute one prompt through Codex single flow from Claude", "Codex prepares and implements one plan" -->
<!-- cog-skill: plan-emitter -->
<!-- cog-skill: input-fidelity -->

# Executor Single Codex

**Phase 0 — Plan-mode gate.** If Claude Code plan mode is active, STOP before any other work and follow `$(cog skill-refs path orchestration/plan-mode-gate.md)`.

Execute one prompt or plan through the Codex-backed gated 2-stage executor flow: an input-evaluation gate guarantees a good plan, then Codex implements it. Codex is the executor, so every Codex stage is a genuine fresh-context boundary and gets a validated brief. Everything Claude does — the input verdict, the cross-engine plan review, the decisions Codex would otherwise have to guess — runs **in this context**, where the session already holds the request and its history.

**Context-brief gate.** Before dispatching to any fresh-context worker, build and validate its input brief per `$(cog skill-refs path orchestration/context-brief-gate.md)` — build it with `cog context-brief build --request` and confirm it with `cog context-brief validate`. That applies to the Codex plan and execution stages; the in-session Claude review reads the request directly. This launcher owns sequencing and postcondition checks; run setup, verdict persistence, artifact paths, Codex invocation, and summaries stay behind `cog`.

## Bootstrap

```bash
cog executor init --executor executor-oneshot --engine codex --input <prompt-or-plan> --json
```

Use the returned run directory and canonical artifact paths (`prepared-plan.md`, `execution-report.md`, `executor-summary.json`). For prompt input it writes `request.md`; for plan input it writes `plan-source` with the supplied plan path.

## Input evaluation (gate)

Judge the route here, in this context. Write the original input verbatim to `<RUN_DIR>/assess-input-source.md`, identify every readable plan file it references, and gather the deterministic signals:

```bash
cog assess-input facts --input-file <RUN_DIR>/assess-input-source.md --file <each referenced plan> --json
```

Apply the rubric at `$(cog skill-refs path orchestration/input-quality-rubric.md)`. Higher heading coverage and scope-proportional depth favor `good-input`; near-zero plan structure favors `needs-plan`. When genuinely uncertain, choose `needs-plan`. Persist the verdict:

```bash
cog assess-input record --run-dir <RUN_DIR> --route <needs-plan|good-input> --confidence <high|medium|low> --rationale "<one line>" --signal max_heading_count=<n> --signal plan_files=<n> --json
```

`record` writes `<RUN_DIR>/assess-input.json` and fails closed, so its own output is the confirmation.

## Stage 1: Prepare the plan

Both routes write the prepared plan to `<RUN_DIR>/prepared-plan.md`.

### `needs-plan` — Codex plans

Settle the open decisions first — see [Cross-engine decisions](#cross-engine-decisions) below — then build the brief that carries them.

Ensure `<RUN_DIR>/request.md` exists (init writes it for prompt input; for plan input, create a non-empty `request.md` capturing the supplied-plan source context verbatim and in full). Build the brief per `$(cog skill-refs path orchestration/context-brief-contract.md)`: scaffold the authored body, fill it from the whole session (a well-oriented **Objective**; **Output Format**; **Boundaries**; **Context & Decisions** carrying the full substance and the settled decisions; **Artifacts** inline or pointed-to; **Effort Guidance**; **Not Evaluated** — keep your own verdict out), then build it:

```bash
cog context-brief template --out "<RUN_DIR>/brief-body.md"
# fill <RUN_DIR>/brief-body.md per the contract, then:
cog context-brief build --request "<RUN_DIR>/request.md" --body "<RUN_DIR>/brief-body.md" --out "<RUN_DIR>/brief.md"
```

`build` attaches the request verbatim and fails closed unless every section is filled.

Write `<RUN_DIR>/prepare-prompt.md` with the write orientation from `cog codex-runner orientation write`, `$plan-oneshot`, `--output <RUN_DIR>/prepared-plan.md`, and `<RUN_DIR>/brief.md` as the complete context. Launch the durable job and poll-and-classify (exit code is the signal: 0 ok, 1 failed, 75 still running; re-run finalize while it exits 75; duration is never judged):

```bash
cog codex-runner run-exec --mode danger --access write --effort high --prompt <RUN_DIR>/prepare-prompt.md --output <RUN_DIR>/prepare-codex-output.md --events <RUN_DIR>/prepare-events.jsonl --stderr <RUN_DIR>/prepare-stderr.log --state <RUN_DIR>/prepare.longrun.json
cog codex-runner finalize --state <RUN_DIR>/prepare.longrun.json --max-wall 300
```

The result is a saved plan doc, so confirm it with `cog plan-doc validate <RUN_DIR>/prepared-plan.md` — a plan clobbered by a last-message pointer fails validation deterministically.

### `good-input` — Claude reviews in session

Claude is the opposite engine here, so the cross-engine review needs no fresh context and no brief. Ensure `<RUN_DIR>/request.md` exists first (init writes it for prompt input; for plan input, create a non-empty `request.md` capturing the supplied-plan source context verbatim and in full) — Stage 2 builds its brief from it. Read `$HOME/.claude/skills/review-plan-oneshot/SKILL.md` and follow its Orchestrator Invocation Contract **in this context**, with three absolute paths: plan-path (the supplied plan path, or `<RUN_DIR>/request.md` for inline-plan prompt input), request-path `<RUN_DIR>/request.md`, and output-path `<RUN_DIR>/prepared-plan.md`.

Confirm `<RUN_DIR>/prepared-plan.md` exists and is non-empty.

## Cross-engine decisions

Decisions that would otherwise be interviewed out of the human are answered by the engine that is **not** producing the plan. Codex produces the plan on `needs-plan`, so Claude answers — and Claude is already here, holding the session.

Enumerate the decisions that materially change the plan — scope, approach, testing. When there are none, skip this section entirely. Otherwise answer each from session context plus the repo reads needed to ground it, choosing the best default and naming the reason, then carry the answers into the brief's **Context & Decisions** section as settled decisions so Codex plans against them rather than guessing. These are scope and approach choices, not a proposed solution, so they leave the brief's single deliberate omission intact.

Persist every question, the answer taken, and the engine that answered it to `<RUN_DIR>/decisions.md`, and surface the same as a short **Decisions** block in the final response.

## Stage 2: Implement with Codex

Codex implements in a fresh context, so this stage pays for its own validated brief. Build it per `$(cog skill-refs path orchestration/context-brief-contract.md)`, filling **Objective** with the implementation goal, **Output Format** with the required final report (files changed, deviations, commands run, unresolved risks), **Boundaries** with the active repository constraints, **Context & Decisions** with the session substance that bears on the implementation plus the settled decisions from `<RUN_DIR>/decisions.md` when that file exists — on the `good-input` route, and whenever no decision was open, it does not, so state instead that no cross-engine decision was required — and **Artifacts** with the prepared plan from `<RUN_DIR>/prepared-plan.md` verbatim (when it is an annotated review, carry the reconciled plan — apply APPROVED/MODIFIED/ADDED, skip REMOVED):

```bash
cog context-brief template --out "<RUN_DIR>/execution-brief-body.md"
# fill <RUN_DIR>/execution-brief-body.md per the contract, then:
cog context-brief build --request "<RUN_DIR>/request.md" --body "<RUN_DIR>/execution-brief-body.md" --out "<RUN_DIR>/execution-brief.md"
cog context-brief validate "<RUN_DIR>/execution-brief.md"
```

`build` attaches the original request verbatim, so the stage input carries the full substance as-is. Write `<RUN_DIR>/execution-prompt.md` with the write orientation and `<RUN_DIR>/execution-brief.md` as the complete context. Launch the durable job and poll-and-classify:

```bash
cog codex-runner run-exec --mode danger --access write --effort medium --prompt <RUN_DIR>/execution-prompt.md --output <RUN_DIR>/execution-report.md --events <RUN_DIR>/execution-events.jsonl --stderr <RUN_DIR>/execution-stderr.log --state <RUN_DIR>/execution.longrun.json
cog codex-runner finalize --state <RUN_DIR>/execution.longrun.json --max-wall 300
```

Verify `<RUN_DIR>/execution-report.md` exists and is non-empty.

## Operator-approval gate

When the unit is an operator-approval gate — the input requires a human to sign off before the work completes — the approval must arrive on a channel the executor can verify, per `$(cog skill-refs path orchestration/approval-gate-contract.md)`. A coordinator-relayed approval is never sufficient. Surface the exact command for the human to run out of band, then gate completion on the hash-bound check. Use one stable identifier for `<gate_id>` across both commands, and the input path under approval for `<input-artifact>`:

```bash
cog gate approve --gate-id <gate_id> --artifact <input-artifact>
cog gate check-approval --gate-id <gate_id> --artifact <input-artifact>
```

Proceed only on exit `0`. On any other exit, stop and report the verdict `status` (`missing`/`stale`/`hash-mismatch`) so the human can approve — or re-approve after a legitimate edit, which the check invalidates by design.

## Summary

```bash
cog executor summary --run-dir <RUN_DIR> --executor executor-oneshot --engine codex --route <needs-plan|good-input> --prepare <done|failed> --execution <done|failed> --json
```

Stop the chain on any failed stage, preserve the run directory artifacts, and still emit the summary when enough stage status is known.

## Guardrails

- Codex runs are cog-owned durable jobs: `run-exec` launches, then poll-and-classify with `cog codex-runner finalize --max-wall <secs>`.
- Use native Codex effort through `--effort`; never use legacy profiles.
- Run no git command unless explicitly authorized.
- Deterministic mechanics stay behind `cog executor`, `cog assess-input`, and `cog codex-runner`; the plan comes from `/plan-oneshot` and its cross-engine review from `/review-plan-oneshot`.
- This skill executes one prompt or plan.
