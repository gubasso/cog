---
name: executor-vetted
description: >
  Execute one prompt or implementation plan through the Claude vetted executor
  flow: evaluate the input, prepare a vetted plan with dual-engine planning
  (generate when thin, multi-review when already detailed), then implement it
  natively in session.
model: opus
effort: medium
argument-hint: "<prompt-or-plan-path>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Agent Grep Glob
---

<!-- trigger-tests: "executor-vetted", "execute one prompt through Claude vetted flow", "execute one plan through Claude vetted flow" -->
<!-- cog-skill: input-fidelity -->

# Executor Vetted

**Phase 0 — Plan-mode gate.** If Claude Code plan mode is active, STOP before any other work and follow `$(cog skill-refs path orchestration/plan-mode-gate.md)`.

Execute one prompt or one implementation plan through the gated 2-stage executor flow: `plan-vetted` produces a vetted plan via an input-evaluation gate plus dual-engine planning, then Claude implements it natively in the current session. This skill owns sequencing and judgment. Run directory setup, canonical artifact paths, and executor summaries stay behind `cog`; the input verdict and producer resolution stay inside the delegated vetted-plan producer. This is a Claude-only orchestrator: its producer runs Claude and Codex together, so it has no Codex twin.

## Inputs

`$ARGUMENTS` is either a prompt/task description or an existing readable regular `.md` plan path.

Delegate classification and run setup to `cog executor`:

```bash
cog executor init --executor executor-vetted --engine claude --input <prompt-or-plan> --json
```

Use the run directory and canonical artifact paths it returns (`prepared-plan.md`, `execution-report.md`, `executor-summary.json`). For prompt input it writes `request.md`; for plan input it writes `plan-source` with the supplied plan path.

## Stage 1: Prepare The Plan

Delegate the input-evaluation gate plus vetted-plan production to `plan-vetted`. Inline-chain it in the current context (read `$HOME/.claude/skills/plan-vetted/SKILL.md` and follow it), passing the original input plus `--output <run-dir>/prepared-plan.md`. The delegation input is the best-constructed input per `$(cog skill-refs path orchestration/context-brief-contract.md)`: attach the original request as-is, add relevant repo constraints, and carry the full substance that bears on the work. `plan-vetted` evaluates the input, generates a plan (`needs-plan`) or multi-reviews it (`good-input`), and writes the vetted plan to the `--output` path. It returns the output path and the route.

A dual-engine plan (two strong models drafting independently, then a synthesized best-of-both) is itself the vetting, so neither route needs a separate review pass.

After Stage 1, record the returned route for the summary and confirm the prepared plan with `cog
executor verify-artifact --run-dir <run-dir> --ordinal prepare` before continuing; it fails closed when the canonical artifact is missing or empty.

## Stage 2: Implement

Implement natively in the current Claude session. Read and follow `<run-dir>/prepared-plan.md`; when it is an annotated review, implement the reconciled plan it specifies (apply APPROVED/MODIFIED/ADDED guidance, skip REMOVED).

Carry only relevant session context:

- The prepared plan, verbatim.
- The original request or supplied-plan source context, verbatim and in full, with only enriching repo constraints added.
- A short statement that the prepared plan supersedes any earlier plan.
- Current session constraints: do not run git commands unless explicitly authorized, follow `AGENTS.md` and `CLAUDE.md`, and stay inside the prepared plan.
- A required final implementation report covering files changed, commands run, deviations, and unresolved risks.

After implementation, write the final implementation report to a working file in the run directory, then hand it to `cog` so the canonical artifact name and its non-empty check stay deterministic:

```bash
cog executor adopt --run-dir <run-dir> --ordinal execution --from <report-working-file>
```

`adopt` places the report at the canonical execution artifact path and fails closed when the source is missing or empty.

## Summary

Emit an executor summary after Stage 2 or after a terminal stage failure:

```bash
cog executor summary --run-dir <run-dir> --executor executor-vetted --engine claude --route <needs-plan|good-input> --prepare <done|failed> --execution <done|failed> --json
```

Status rules:

- The prepare stage always runs; report `--prepare done` on success.
- If Stage 1 fails, do not run Stage 2; emit the summary with failure statuses.
- If Stage 2 fails, still emit the summary with `--execution failed`.

## Match-outcome telemetry

When the input was a queued plan-vault round (the `-ar <path>` resolves under a plan vault), record a match-outcome so routing can be calibrated ([ADR-0015](../../../docs/decisions/ADR-0015-executor-capability-and-telemetry.md)). Resolve the join key from the round path — it stays producer-blind. The `executor-vetted` marginal-value checkpoint is the **cross-engine delta count**: the distinct corrections or additions the second engine contributed to the dual-engine synthesis (zero deltas means the vetting earned nothing — over-powered by one rung):

```bash
cog match-telemetry round-key --round-path <input-round-path> --json   # -> project_key, plan_slug, round_id
cog match-telemetry record --kind outcome \
  --project-key <project_key> --plan-slug <plan_slug> --round-id <round_id> \
  --actual-executor executor-vetted --result <pass|fail> [--reverted] [--retries <n>] \
  [--loc-changed <n>] [--files <n>] --cross-engine-deltas <n> [--note <text>] --json
```

Skip telemetry for non-round inputs. Attach `--note` only when the objective signals look conflicting or questionable — never as a routine per-run rating.

## Error Handling

At every boundary, verify the durable postcondition before advancing:

- Stage 1: `cog executor verify-artifact --run-dir <run-dir> --ordinal prepare` succeeds; the returned route is `needs-plan` or `good-input`.
- Plan input: the supplied plan path exists and is readable before review or implementation.
- Stage 2: `cog executor verify-artifact --run-dir <run-dir> --ordinal execution` succeeds.
- Summary: `executor-summary.json` is written by `cog executor summary`.

On failure, stop the chain, preserve the run directory artifacts, and still emit the executor summary using the status rules above. Do not infer status from prose when a `cog` command reports structured output.

## Guardrails

- Keep the gate, plan preparation, Claude implementation, and orchestration foreground; never background them.
- Native Codex effort only, via `--effort`, inside the delegated producers.
- Do not run git commands unless explicitly authorized.
- Deterministic mechanics stay behind `cog executor`; the vetted plan comes from `/plan-vetted`.
- This skill executes one prompt or plan.
