---
name: executor-oneshot
description: >
  Execute one prompt or implementation plan through the Claude single executor
  flow: evaluate the input, prepare a good plan (generate in session when thin,
  cross-engine review when already detailed), then implement it natively.
model: opus
effort: medium
argument-hint: "<prompt-or-plan-path>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Grep Glob
---

<!-- trigger-tests: "executor-oneshot", "execute one prompt through Claude single flow", "execute one plan through Claude single flow" -->
<!-- cog-skill: input-fidelity -->

# Executor Single

**Phase 0 — Plan-mode gate.** If Claude Code plan mode is active, STOP before any other work and follow `$(cog skill-refs path orchestration/plan-mode-gate.md)`.

Execute one prompt or one implementation plan through the gated 2-stage executor flow: an input-evaluation gate guarantees a good plan, then Claude implements it natively. The gate and Stage 2 always run **in this context**, and so does Stage 1 on the `needs-plan` route — the session already holds the request, the research, and the decisions, so the plan is produced where it is implemented. The one fresh-context boundary is the cross-engine Codex plan review on the `good-input` route. This skill owns sequencing and judgment; run setup, input classification, verdict persistence, artifact paths, and summaries stay behind `cog`.

**Context-brief gate.** That Codex review is the only dispatch to a fresh-context worker; build and validate its input brief per `$(cog skill-refs path orchestration/context-brief-gate.md)` inside that branch — build it with `cog context-brief build --request` and confirm it with `cog context-brief validate`. No other route pays for a brief.

## Inputs

`$ARGUMENTS` is either a prompt/task description or an existing readable regular `.md` plan path.

Delegate classification and run setup to `cog executor`:

```bash
cog executor init --executor executor-oneshot --engine claude --input <prompt-or-plan> --json
```

Use the run directory and canonical artifact paths it returns (`prepared-plan.md`, `execution-report.md`, `executor-summary.json`). For prompt input it writes `request.md`; for plan input it writes `plan-source` with the supplied plan path.

## Input evaluation (gate)

Judge the route here, in this context. The input is already present, so the verdict costs one command and one judgment call.

Write the original input verbatim to `<run-dir>/assess-input-source.md`, identify every readable plan file it references, and gather the deterministic signals:

```bash
cog assess-input facts --input-file <run-dir>/assess-input-source.md --file <each referenced plan> --json
```

Apply the rubric at `$(cog skill-refs path orchestration/input-quality-rubric.md)` to the input and those signals. Higher heading coverage and scope-proportional depth favor `good-input`; near-zero plan structure favors `needs-plan`. When genuinely uncertain, choose `needs-plan`. Persist the verdict so the call stays auditable and tunable:

```bash
cog assess-input record --run-dir <run-dir> --route <needs-plan|good-input> --confidence <high|medium|low> --rationale "<one line>" --signal max_heading_count=<n> --signal plan_files=<n> --json
```

`record` writes `<run-dir>/assess-input.json` and fails closed, so its own output is the confirmation.

## Stage 1: Prepare the plan

Both routes write the prepared plan to `<run-dir>/prepared-plan.md`.

### `needs-plan` — generate in session

Read `$HOME/.claude/skills/plan-oneshot/SKILL.md` and follow it **in this context**, passing `--output <run-dir>/prepared-plan.md` and an orientation drawn from the whole session. The generated plan must include assumptions, ambiguities, dependencies, and risks.

Run it non-interactively: this executor never blocks the human, so `plan-oneshot`'s `AskUserQuestion` interview and its final "ready to generate?" confirmation are both satisfied by the cross-engine procedure instead. Resolve every interview decision through the **other engine** — see [Cross-engine decisions](#cross-engine-decisions) below — then treat the settled decisions as the readiness confirmation and generate.

### `good-input` — cross-engine Codex review

The existing plan is reviewed by the opposite engine for independence. This is the fresh-context boundary, so build the validated brief first.

Ensure `<run-dir>/request.md` exists (init writes it for prompt input; for plan input, create a non-empty `request.md` capturing the supplied-plan source context verbatim and in full, with only enriching repo constraints). Then build the brief per `$(cog skill-refs path orchestration/context-brief-contract.md)`: scaffold the authored body, fill it from the whole session (a well-oriented **Objective**; **Output Format**; **Boundaries**; **Context & Decisions** carrying the full substance; **Artifacts** inline or pointed-to; **Effort Guidance**; **Not Evaluated** — keep your own verdict out), then build it:

```bash
cog context-brief template --out "<run-dir>/brief-body.md"
# fill <run-dir>/brief-body.md per the contract, then:
cog context-brief build --request "<run-dir>/request.md" --body "<run-dir>/brief-body.md" --out "<run-dir>/brief.md"
```

`build` attaches the request verbatim and fails closed unless every section is filled.

Write `<run-dir>/prepare-prompt.md` with the write orientation from `cog codex-runner orientation write` on its first line, followed by `$review-plan-oneshot` and three absolute paths — plan-path (the supplied plan path, or `<run-dir>/request.md` for inline-plan prompt input), request-path `<run-dir>/brief.md`, and output-path `<run-dir>/prepared-plan.md`. Launch the durable job write-capable, then poll-and-classify (exit code is the signal: 0 ok, 1 failed, 75 still running; re-run finalize while it exits 75; duration is never judged):

```bash
cog codex-runner run-exec --mode danger --access write --effort medium --prompt <run-dir>/prepare-prompt.md --output <run-dir>/prepare-codex-output.md --events <run-dir>/prepare-events.jsonl --stderr <run-dir>/prepare-stderr.log --state <run-dir>/prepare.longrun.json
cog codex-runner finalize --state <run-dir>/prepare.longrun.json --max-wall 300
```

### Boundary check

Confirm the prepared plan with `cog executor verify-artifact --run-dir <run-dir> --ordinal prepare` before continuing; it fails closed when the canonical artifact is missing or empty.

## Cross-engine decisions

Interview decisions on the `needs-plan` route are answered by the engine that is **not** producing the plan. Claude produces the plan here, so Codex answers. The human is never blocked.

Enumerate the decisions that materially change the plan — scope, approach, testing. When there are none, skip this section entirely; a fully-specified input costs nothing here. Otherwise write them to `<run-dir>/consult-questions.md`, numbered, each with its candidate options and trade-offs. That file is the best-constructed input per `$(cog skill-refs path orchestration/context-brief-contract.md)`: the questions plus the substance needed to answer them, opening with the read-only orientation from `cog codex-runner orientation read-only` and naming `$ask` so the Codex skill loads. Run one short read-only consult and classify it the same way:

```bash
cog codex-runner run-exec --mode danger --access read-only --effort low --prompt <run-dir>/consult-questions.md --output <run-dir>/consult-answers.md --events <run-dir>/consult-events.jsonl --stderr <run-dir>/consult-stderr.log --state <run-dir>/consult.longrun.json
cog codex-runner finalize --state <run-dir>/consult.longrun.json --max-wall 300
```

Adopt the answers as the recorded decisions and continue generating. A failed or unavailable consult degrades rather than hard-fails: pick the best default for each open decision and record it as a skill-chosen default with the reason the consult was unavailable.

Persist every question, the answer taken, and the engine that answered it to `<run-dir>/decisions.md`, and surface the same as a short **Decisions** block in the final response.

## Stage 2: Implement

Implement natively in the current Claude session. Read and follow `<run-dir>/prepared-plan.md`; when it is an annotated review, implement the reconciled plan it specifies (apply APPROVED/MODIFIED/ADDED guidance, skip REMOVED).

Carry the prepared plan verbatim, the original request or supplied-plan source context verbatim and in full with only enriching repo constraints added, and the active session constraints: run no git command unless explicitly authorized, follow `AGENTS.md` and `CLAUDE.md`, and stay inside the prepared plan.

After implementation, write the final implementation report — files changed, commands run, deviations, unresolved risks — to a working file in the run directory, then hand it to `cog` so the canonical artifact name and its non-empty check stay deterministic:

```bash
cog executor adopt --run-dir <run-dir> --ordinal execution --from <report-working-file>
```

`adopt` places the report at the canonical execution artifact path and fails closed when the source is missing or empty.

## Operator-approval gate

When the round is an operator-approval gate — its round prompt requires a human to sign off before the work completes — the approval must arrive on a channel the executor can verify, per `$(cog skill-refs path orchestration/approval-gate-contract.md)`. A coordinator-relayed approval is never sufficient. Surface the exact command for the human to run out of band, then gate completion on the hash-bound check, resolving `<round_id>` from `cog match-telemetry round-key`:

```bash
cog gate approve --round-id <round_id> --round-path <input-round-path>
cog gate check-approval --round-id <round_id> --round-path <input-round-path>
```

Proceed only on exit `0`. On any other exit, stop and report the verdict `status` (`missing`/`stale`/`hash-mismatch`) so the human can approve — or re-approve after a legitimate edit, which the check invalidates by design.

## Summary

Emit an executor summary after Stage 2 or after a terminal stage failure:

```bash
cog executor summary --run-dir <run-dir> --executor executor-oneshot --engine claude --route <needs-plan|good-input> --prepare <done|failed> --execution <done|failed> --json
```

The prepare stage always runs; report `--prepare done` on success. If Stage 1 fails, skip Stage 2 and emit the summary with failure statuses. If Stage 2 fails, still emit the summary with `--execution failed`.

## Match-outcome telemetry

When the input was a queued plan-vault round (the `-ar <path>` resolves under a plan vault), record a match-outcome so routing can be calibrated ([ADR-0015](../../../docs/decisions/ADR-0015-executor-capability-and-telemetry.md)). Resolve the join key from the round path — it stays producer-blind — then record the outcome. `executor-oneshot` is the floor rung and carries no marginal-value field. At terminus read the actual changeset with `cog review-scope --json` and record it as scope (`--files` = changed-file count, `--loc-changed` = added+deleted lines); when the round declared a `scope`, pass its limits as `--round-scope-max-files`/`--round-scope-max-lines`; pass `--override-approval-gate` when a WS1 operator approval gated this round:

```bash
cog match-telemetry round-key --round-path <input-round-path> --json   # -> project_key, plan_slug, round_id
cog match-telemetry record --kind outcome \
  --project-key <project_key> --plan-slug <plan_slug> --round-id <round_id> \
  --actual-executor executor-oneshot --result <pass|fail> [--reverted] [--retries <n>] \
  [--loc-changed <n>] [--files <n>] \
  [--round-scope-max-files <n>] [--round-scope-max-lines <n>] [--override-approval-gate] \
  [--note <text>] --json
```

Skip telemetry for non-round inputs. Attach `--note` only when the objective signals look conflicting or questionable — never as a routine per-run rating.

## Error handling

Verify the durable postcondition at each boundary before advancing: a route of `needs-plan` or `good-input` from `cog assess-input record`; a readable supplied plan path before review or implementation; `cog executor verify-artifact` for both the `prepare` and `execution` ordinals; and `executor-summary.json` from `cog executor summary`.

On failure, stop the chain, preserve the run directory artifacts, and still emit the executor summary using the status rules above. Do not infer status from prose when a `cog` command reports structured output.

## Guardrails

- Keep the gate, plan preparation, Claude implementation, and orchestration foreground; never background them. Codex runs are cog-owned durable jobs.
- Native Codex effort only, via `--effort`.
- Run no git command unless explicitly authorized.
- Deterministic mechanics stay behind `cog executor`, `cog assess-input`, and `cog codex-runner`; the plan comes from `/plan-oneshot` and its cross-engine review from `/review-plan-oneshot`.
- This skill executes one prompt or plan.
