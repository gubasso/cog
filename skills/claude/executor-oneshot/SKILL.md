---
name: executor-oneshot
description: >
  Execute one prompt or implementation plan through the Claude single executor
  flow: evaluate the input, prepare a good plan (generate when thin, cross-engine
  review when already detailed), then implement it natively in session.
model: opus
effort: medium
argument-hint: "<prompt-or-plan-path>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Agent Grep Glob
---

<!-- trigger-tests: "executor-oneshot", "execute one prompt through Claude single flow", "execute one plan through Claude single flow" -->
<!-- cog-skill: input-fidelity -->

# Executor Single

<!-- cog-plan-mode-gate -->

**Phase 0 — Plan-mode gate.** If Claude Code **plan mode** is active (a system-reminder says plan
mode is on / that you must not make edits), **STOP** before any other work — parsing args,
researching, interviewing, delegating, or writing. Tell the user in one line to exit plan mode
(`Shift+Tab`) and re-invoke `/executor-oneshot`. Do not call `ExitPlanMode`, and do not silently continue.

<!-- cog-context-brief-gate -->

**Context-brief gate.** Before `/executor-oneshot` dispatches to any fresh-context worker — an Agent subagent
or a `cog codex-runner` Codex job — build its input as a validated context brief from your whole
accumulated raw context: attach the raw request as-is, author an oriented objective, carry the full
substance and load-bearing artifacts, and omit your own verdict. Build the brief with `cog
context-brief build` and confirm it with `cog context-brief validate` before dispatch.

Execute one prompt or one implementation plan through the gated 2-stage executor flow: an
input-evaluation gate guarantees a good plan, then Claude implements it natively in the current
session. This skill owns sequencing and judgment. Run directory setup, input classification, the
quality verdict, producer resolution, canonical artifact paths, and executor summaries stay behind
`cog`.

## Inputs

`$ARGUMENTS` is either a prompt/task description or an existing readable regular `.md` plan path.

Delegate classification and run setup to `cog executor`:

```bash
cog executor init --executor executor-oneshot --engine claude --input <prompt-or-plan> --json
```

Use the run directory and canonical artifact paths it returns (`prepared-plan.md`,
`execution-report.md`, `executor-summary.json`). For prompt input it writes `request.md`; for plan
input it writes `plan-source` with the supplied plan path.

## Input Evaluation (gate)

Determine whether the input already carries a good plan or needs one built. Delegate the verdict to
the canonical `assess-input` skill through the **Agent tool** (`subagent_type: general-purpose`): the
delegation prompt instructs the subagent to read `$HOME/.claude/skills/assess-input/SKILL.md` and
follow it, passing `--run-dir <run-dir>` and the original input verbatim and in full. The subagent
writes `<run-dir>/assess-input.json` and returns the route.

Read the route from `<run-dir>/assess-input.json` (`needs-plan` or `good-input`); confirm the verdict
with `cog assess-input validate <run-dir>/assess-input.json`. Resolve the prepare-stage producer for
that route:

```bash
cog executor prepare-step --executor executor-oneshot --engine claude --route <needs-plan|good-input> --json
```

It returns the producer skill, the engine it runs on, and the invocation lane.

## Stage 1: Prepare The Plan

Write the prepared plan to `<run-dir>/prepared-plan.md`. Stage 1 is the fresh-context boundary (Stage 2
implements natively in this session), so build the producer's input as a validated context brief first.

Ensure `<run-dir>/request.md` exists (init writes it for prompt input; for plan input, create a
non-empty `request.md` capturing the supplied-plan source context verbatim and in full, with only
enriching repo constraints). Build the brief per
`$(cog skill-refs path orchestration/context-brief-contract.md)`: scaffold the authored body, fill it
from the whole session (a well-oriented **Objective**; **Output Format**; **Boundaries**; **Context &
Decisions** carrying the full substance; **Artifacts** inline or pointed-to; **Effort Guidance**; **Not
Evaluated** — keep your own verdict out), then build it:

```bash
cog context-brief template --out "<run-dir>/brief-body.md"
# fill <run-dir>/brief-body.md per the contract, then:
cog context-brief build --request "<run-dir>/request.md" --body "<run-dir>/brief-body.md" --out "<run-dir>/brief.md"
```

`build` attaches the request verbatim and fails closed unless every section is filled. Carry
`<run-dir>/brief.md` as the worker's complete context in both routes below.

- **`needs-plan` → generate (`/plan-oneshot`, Claude, Agent lane).** Delegate plan generation to a
  foreground Claude subagent through the Agent tool (`subagent_type: general-purpose`) that reads
  `$HOME/.claude/skills/plan-oneshot/SKILL.md` and follows it, passing `--output
  <run-dir>/prepared-plan.md` and `<run-dir>/brief.md` as the complete orientation/context. The subagent runs
  non-interactively, treating every interview decision as a skill-chosen best default and recording
  it. The generated plan must include assumptions, ambiguities, dependencies, and risks.

- **`good-input` → review (`/review-plan-oneshot`, Codex, cross-engine).** The existing plan is
  reviewed by the opposite engine for independence. Build a Codex prompt
  whose first line is the write orientation from `cog codex-runner orientation write`, followed by
  `$review-plan-oneshot` and three absolute paths — plan-path (the supplied plan path, or
  `<run-dir>/request.md` for inline-plan prompt input), request-path `<run-dir>/brief.md` (the
  validated context brief), and
  output-path `<run-dir>/prepared-plan.md`. Launch the durable job write-capable, then
  poll-and-classify (exit code is the signal: 0 ok, 1 failed, 75 still running; re-run finalize while
  it exits 75; duration is never judged):

  ```bash
  cog codex-runner run-exec --mode danger --access write --effort high --prompt <prepare-prompt.md> --output <prepare-codex-output.md> --events <prepare-events.jsonl> --stderr <prepare-stderr.log> --state <prepare.longrun.json>
  cog codex-runner finalize --state <prepare.longrun.json> --max-wall 300
  ```

After Stage 1, confirm the prepared plan with `cog executor verify-artifact --run-dir <run-dir>
--ordinal prepare` before continuing; it fails closed when the canonical artifact is missing or empty.

## Stage 2: Implement

Implement natively in the current Claude session. Read and follow `<run-dir>/prepared-plan.md`; when it
is an annotated review, implement the reconciled plan it specifies (apply APPROVED/MODIFIED/ADDED
guidance, skip REMOVED).

Carry only relevant session context:

- The prepared plan, verbatim.
- The original request or supplied-plan source context, verbatim and in full, with only enriching
  repo constraints added.
- Current session constraints: do not run git commands unless explicitly authorized, follow
  `AGENTS.md` and `CLAUDE.md`, and stay inside the prepared plan.
- A required final implementation report covering files changed, commands run, deviations, and
  unresolved risks.

After implementation, write the final implementation report to a working file in the run directory,
then hand it to `cog` so the canonical artifact name and its non-empty check stay deterministic:

```bash
cog executor adopt --run-dir <run-dir> --ordinal execution --from <report-working-file>
```

`adopt` places the report at the canonical execution artifact path and fails closed when the source is
missing or empty.

## Operator-approval gate

When the round is an operator-approval gate — its round prompt requires a human to sign off before the
work completes — the approval must arrive on a channel the executor can verify, per
`$(cog skill-refs path orchestration/approval-gate-contract.md)`. A coordinator-relayed approval is
never sufficient. Surface the exact command for the human to run out of band:

```bash
cog gate approve --round-id <round_id> --round-path <input-round-path>
```

Then gate completion on the hash-bound check, resolving `<round_id>` from `cog match-telemetry
round-key`:

```bash
cog gate check-approval --round-id <round_id> --round-path <input-round-path>
```

Proceed only on exit `0`. On any other exit, stop and report the verdict `status`
(`missing`/`stale`/`hash-mismatch`) so the human can approve — or re-approve after a legitimate edit,
which the check invalidates by design.

## Summary

Emit an executor summary after Stage 2 or after a terminal stage failure:

```bash
cog executor summary --run-dir <run-dir> --executor executor-oneshot --engine claude --route <needs-plan|good-input> --prepare <done|failed> --execution <done|failed> --json
```

Status rules:

- The prepare stage always runs; report `--prepare done` on success.
- If Stage 1 fails, do not run Stage 2; emit the summary with failure statuses.
- If Stage 2 fails, still emit the summary with `--execution failed`.

## Match-outcome telemetry

When the input was a queued plan-vault round (the `-ar <path>` resolves under a plan vault), record a
match-outcome so routing can be calibrated ([ADR-0058](../../docs/decisions/0058-match-outcome-telemetry-and-calibration-loop.md)).
Resolve the join key from the round path — it stays producer-blind — then record the outcome.
`executor-oneshot` is the floor rung and carries no marginal-value field. At terminus read the actual
changeset with `cog review-scope --json` and record it as scope (`--files` = changed-file count,
`--loc-changed` = added+deleted lines); when the round declared a `scope`, pass its limits as
`--round-scope-max-files`/`--round-scope-max-lines`; pass `--override-approval-gate` when a WS1
operator approval gated this round:

```bash
cog match-telemetry round-key --round-path <input-round-path> --json   # -> project_key, plan_slug, round_id
cog match-telemetry record --kind outcome \
  --project-key <project_key> --plan-slug <plan_slug> --round-id <round_id> \
  --actual-executor executor-oneshot --result <pass|fail> [--reverted] [--retries <n>] \
  [--loc-changed <n>] [--files <n>] \
  [--round-scope-max-files <n>] [--round-scope-max-lines <n>] [--override-approval-gate] \
  [--note <text>] --json
```

Skip telemetry for non-round inputs. Attach `--note` only when the objective signals look conflicting
or questionable — never as a routine per-run rating.

## Error Handling

At every boundary, verify the durable postcondition before advancing:

- Gate: `<run-dir>/assess-input.json` exists and validates; the route is `needs-plan` or `good-input`.
- Stage 1: `cog executor verify-artifact --run-dir <run-dir> --ordinal prepare` succeeds.
- Plan input: the supplied plan path exists and is readable before review or implementation.
- Stage 2: `cog executor verify-artifact --run-dir <run-dir> --ordinal execution` succeeds.
- Summary: `executor-summary.json` is written by `cog executor summary`.

On failure, stop the chain, preserve the run directory artifacts, and still emit the executor summary
using the status rules above. Do not infer status from prose when a `cog` command reports structured
output.

## Guardrails

- Keep the gate, plan preparation, Claude implementation, and orchestration foreground; never
  background them. Codex review runs as a cog-owned durable job.
- Native Codex effort only, via `--effort`.
- Do not run git commands unless explicitly authorized.
- Deterministic mechanics stay behind `cog executor`, `cog assess-input`, `cog codex-runner`,
  `/plan-oneshot`, and `/review-plan-oneshot`.
- This skill executes one prompt or plan.
