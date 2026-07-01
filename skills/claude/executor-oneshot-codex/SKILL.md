---
name: executor-oneshot-codex
description: >
  Execute one prompt or implementation plan through the Codex-backed single
  executor flow from Claude: evaluate the input, prepare a good plan (Codex plans
  when thin, Claude reviews when already detailed), then Codex implements.
model: opus
effort: low
argument-hint: "<prompt-or-plan-path>"
disable-model-invocation: true
allowed-tools: Bash Read Write Agent Grep Glob
---

<!-- trigger-tests: "executor-oneshot-codex", "execute one prompt through Codex single flow from Claude", "Codex prepares and implements one plan" -->
<!-- cog-skill: plan-emitter -->
<!-- cog-skill: input-fidelity -->

# Executor Single Codex

<!-- cog-plan-mode-gate -->

**Phase 0 — Plan-mode gate.** If Claude Code **plan mode** is active (a system-reminder says plan
mode is on / that you must not make edits), **STOP** before any other work — parsing args,
researching, interviewing, delegating, or writing. Tell the user in one line to exit plan mode
(`Shift+Tab`) and re-invoke `/executor-oneshot-codex`. Do not call `ExitPlanMode`, and do not silently continue.

<!-- cog-context-brief-gate -->

**Context-brief gate.** Before `/executor-oneshot-codex` dispatches to any fresh-context worker — an Agent subagent
or a `cog codex-runner` Codex job — build its input as a validated context brief from your whole
accumulated raw context: attach the raw request as-is, author an oriented objective, carry the full
substance and load-bearing artifacts, and omit your own verdict. Build the brief with `cog
context-brief build` and confirm it with `cog context-brief validate` before dispatch.

Execute one prompt or plan through the Codex-backed gated 2-stage executor flow: an input-evaluation
gate guarantees a good plan, then Codex implements it. This launcher owns sequencing and postcondition
checks; deterministic run setup, the quality verdict, producer resolution, artifact paths, Codex
invocation, and summaries stay behind `cog`.

## Bootstrap

Delegate classification and run setup to:

```bash
cog executor init --executor executor-oneshot --engine codex --input <prompt-or-plan> --json
```

Use the returned run directory and canonical artifact paths (`prepared-plan.md`, `execution-report.md`,
`executor-summary.json`). For prompt input it writes `request.md`; for plan input it writes
`plan-source` with the supplied plan path.

## Input Evaluation (gate)

Determine whether the input already carries a good plan or needs one built. Delegate the verdict to the
canonical `assess-input` skill through the **Agent tool** (`subagent_type: general-purpose`): the
delegation prompt instructs the subagent to read `$HOME/.claude/skills/assess-input/SKILL.md` and
follow it, passing `--run-dir <RUN_DIR>` and the original input verbatim and in full. Read the route
from `<RUN_DIR>/assess-input.json` and confirm with `cog assess-input validate
<RUN_DIR>/assess-input.json`. Resolve the prepare-stage producer:

```bash
cog executor prepare-step --executor executor-oneshot --engine codex --route <needs-plan|good-input> --json
```

## Stage 1: Prepare The Plan

Write the prepared plan to `<RUN_DIR>/prepared-plan.md`.

Build the producer's input as a validated context brief first. Ensure `<RUN_DIR>/request.md` exists
(init writes it for prompt input; for plan input, create a non-empty `request.md` capturing the
supplied-plan source context verbatim and in full). Build the brief per
`$(cog skill-refs path orchestration/context-brief-contract.md)`: scaffold the authored body, fill it
from the whole session (a well-oriented **Objective**; **Output Format**; **Boundaries**; **Context &
Decisions** carrying the full substance; **Artifacts** inline or pointed-to; **Effort Guidance**; **Not
Evaluated** — keep your own verdict out), then build it:

```bash
cog context-brief template --out "<RUN_DIR>/brief-body.md"
# fill <RUN_DIR>/brief-body.md per the contract, then:
cog context-brief build --request "<RUN_DIR>/request.md" --body "<RUN_DIR>/brief-body.md" --out "<RUN_DIR>/brief.md"
```

`build` attaches the request verbatim and fails closed unless every section is filled. Carry
`<RUN_DIR>/brief.md` as the worker's complete context in both routes below.

- **`needs-plan` → Codex plans (`/plan-oneshot`).** Write `<RUN_DIR>/prepare-prompt.md` with the
  write orientation from `cog codex-runner orientation write`, `$plan-oneshot`, `--output
  <RUN_DIR>/prepared-plan.md`, and `<RUN_DIR>/brief.md` as the complete context (the validated context
  brief built above). Launch the durable
  Codex job and poll-and-classify (exit code is the signal: 0 ok, 1 failed, 75 still running; re-run
  finalize while it exits 75; duration is never judged):

  ```bash
  cog codex-runner run-exec --mode danger --access write --effort high --prompt <RUN_DIR>/prepare-prompt.md --output <RUN_DIR>/prepare-codex-output.md --events <RUN_DIR>/prepare-events.jsonl --stderr <RUN_DIR>/prepare-stderr.log --state <RUN_DIR>/prepare.longrun.json
  cog codex-runner finalize --state <RUN_DIR>/prepare.longrun.json --max-wall 300
  ```

- **`good-input` → Claude reviews (`/review-plan-oneshot`, cross-engine).**
  Delegate to a Claude subagent through the Agent tool that reads
  `$HOME/.claude/skills/review-plan-oneshot/SKILL.md` and follows its Orchestrator Invocation Contract
  with three absolute paths — plan-path (the supplied plan path, or `<RUN_DIR>/request.md` for
  inline-plan prompt input), request-path `<RUN_DIR>/brief.md` (the validated context brief), output-path
  `<RUN_DIR>/prepared-plan.md`.

Verify `<RUN_DIR>/prepared-plan.md` exists and is non-empty before Stage 2.

## Stage 2: Implement With Codex

Write `<RUN_DIR>/execution-prompt.md` with the write orientation, the prepared plan from
`<RUN_DIR>/prepared-plan.md` verbatim (when it is an annotated review, implement the reconciled plan —
apply APPROVED/MODIFIED/ADDED, skip REMOVED), the original request or supplied-plan context verbatim
and in full, the active repository constraints, and a required final report covering files changed,
deviations, commands run, and unresolved risks. The stage prompt is the best-constructed input per the
context-brief standard: attach the original input as-is and carry the full substance. Launch the durable Codex job and poll-and-classify:

```bash
cog codex-runner run-exec --mode danger --access write --effort medium --prompt <RUN_DIR>/execution-prompt.md --output <RUN_DIR>/execution-report.md --events <RUN_DIR>/execution-events.jsonl --stderr <RUN_DIR>/execution-stderr.log --state <RUN_DIR>/execution.longrun.json
cog codex-runner finalize --state <RUN_DIR>/execution.longrun.json --max-wall 300
```

Verify `<RUN_DIR>/execution-report.md` exists and is non-empty.

## Summary

Emit the executor summary:

```bash
cog executor summary --run-dir <RUN_DIR> --executor executor-oneshot --engine codex --route <needs-plan|good-input> --prepare <done|failed> --execution <done|failed> --json
```

Stop the chain on any failed stage, preserve the run directory artifacts, and still emit the summary
when enough stage status is known.

## Match-outcome telemetry

When the input was a queued plan-vault round (the `-ar <path>` resolves under a plan vault), record a
match-outcome so routing can be calibrated ([ADR-0058](../../docs/decisions/0058-match-outcome-telemetry-and-calibration-loop.md)).
Resolve the join key from the round path — it stays producer-blind — then record the outcome at the
`executor-oneshot` floor rung (no marginal-value field):

```bash
cog match-telemetry round-key --round-path <input-round-path> --json   # -> project_key, plan_slug, round_id
cog match-telemetry record --kind outcome \
  --project-key <project_key> --plan-slug <plan_slug> --round-id <round_id> \
  --actual-executor executor-oneshot --result <pass|fail> [--reverted] [--retries <n>] \
  [--loc-changed <n>] [--files <n>] [--note <text>] --json
```

Skip telemetry for non-round inputs. Attach `--note` only when the objective signals look conflicting
or questionable — never as a routine per-run rating.

## Guardrails

- Codex runs are cog-owned durable jobs: `run-exec` launches, then poll-and-classify with
  `cog codex-runner finalize --max-wall <secs>`.
- Use native Codex effort through `--effort`; never use legacy profiles.
- Do not run git commands.
- Keep deterministic mechanics behind `cog executor`, `cog assess-input`, `cog codex-runner`,
  `/plan-oneshot`, and `/review-plan-oneshot`.
