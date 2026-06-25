---
name: executor-vetted
description: >
  Execute one prompt or implementation plan through the Claude vetted executor
  flow: evaluate the input, prepare a vetted plan with dual-engine planning
  (generate when thin, multi-review when already detailed), then implement it
  natively in session.
model: opus
effort: low
argument-hint: "<prompt-or-plan-path>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Agent Grep Glob
---

<!-- trigger-tests: "executor-vetted", "execute one prompt through Claude vetted flow", "execute one plan through Claude vetted flow" -->
<!-- cog-skill: input-fidelity -->

# Executor Vetted

Execute one prompt or one implementation plan through the gated 2-stage executor flow: an
input-evaluation gate guarantees a vetted plan via dual-engine planning, then Claude implements it
natively in the current session. This skill owns sequencing and judgment. Run directory setup, input
classification, the quality verdict, producer resolution, canonical artifact paths, and executor
summaries stay behind `cog`. This is a Claude-only orchestrator: its multi producers run Claude and
Codex together, so it has no Codex twin.

## Inputs

`$ARGUMENTS` is either a prompt/task description or an existing readable regular `.md` plan path.

Delegate classification and run setup to `cog executor`:

```bash
cog executor init --executor executor-vetted --engine claude --input <prompt-or-plan> --json
```

Use the run directory and canonical artifact paths it returns (`prepared-plan.md`,
`stage2-execution.md`, `executor-summary.json`). For prompt input it writes `request.md`; for plan
input it writes `plan-source` with the supplied plan path.

## Input Evaluation (gate)

Determine whether the input already carries a good plan or needs one built. Delegate the verdict to the
canonical `assess-input` skill through the **Agent tool** (`subagent_type: general-purpose`): the
delegation prompt instructs the subagent to read `$HOME/.claude/skills/assess-input/SKILL.md` and
follow it, passing `--run-dir <run-dir>` and the original input verbatim and in full. Read the route
from `<run-dir>/assess-input.json` and confirm with `cog assess-input validate
<run-dir>/assess-input.json`. Resolve the prepare-stage producer:

```bash
cog executor prepare-step --executor executor-vetted --engine claude --route <needs-plan|good-input> --json
```

Both producers are dual-engine Claude coordinators delegated through the Agent tool. A dual-engine plan
(two strong models drafting independently, then a synthesized best-of-both) is itself the vetting, so
neither route needs a separate review pass.

## Stage 1: Prepare The Plan

Write the prepared plan to `<run-dir>/prepared-plan.md`.

- **`needs-plan` → generate (`/plan-multi`).** Delegate to a foreground Claude subagent through the
  Agent tool (`subagent_type: general-purpose`) that reads `$HOME/.claude/skills/plan-multi/SKILL.md`
  and follows it, passing `--output <run-dir>/prepared-plan.md` and the original request as
  orientation. The delegation prompt is an enrichment-only superset of the original input: include the
  original request verbatim and in full, plus relevant repo constraints, and never replace it with a
  summary. The subagent runs non-interactively, treating every interview decision as a best default,
  and runs both engines (not `--solo`). It returns the output path.

- **`good-input` → multi-review (`/review-plan-multi`).** Delegate to a foreground Claude subagent
  through the Agent tool that reads `$HOME/.claude/skills/review-plan-multi/SKILL.md` and follows it,
  passing the original input as its plan-plus-context argument (the supplied plan path for plan input,
  or `<run-dir>/request.md` for prompt input). The subagent runs both engines and returns the absolute
  path of its definitive vetted review. Adopt that review as the prepared plan:

  ```bash
  cog executor adopt-prepared --run-dir <run-dir> --from <returned-review-path> --json
  ```

After Stage 1, verify that `<run-dir>/prepared-plan.md` exists and is non-empty before continuing.

## Stage 2: Implement

Implement natively in the current Claude session. Read and follow `<run-dir>/prepared-plan.md`; when it
is an annotated review, implement the reconciled plan it specifies (apply APPROVED/MODIFIED/ADDED
guidance, skip REMOVED).

Carry only relevant session context:

- The prepared plan, verbatim.
- The original request or supplied-plan source context, verbatim and in full, with only enriching
  repo constraints added.
- A short statement that the prepared plan supersedes any earlier plan.
- Current session constraints: do not run git commands unless explicitly authorized, follow
  `AGENTS.md` and `CLAUDE.md`, and stay inside the prepared plan.
- A required final implementation report covering files changed, commands run, deviations, and
  unresolved risks.

After implementation, write the final implementation report to `<run-dir>/stage2-execution.md`. Verify
that it exists and is non-empty.

## Summary

Emit an executor summary after Stage 2 or after a terminal stage failure:

```bash
cog executor summary --run-dir <run-dir> --executor executor-vetted --engine claude --route <needs-plan|good-input> --stage1 <done|failed> --stage2 <done|failed> --json
```

Status rules:

- The prepare stage always runs; report `--stage1 done` on success.
- If Stage 1 fails, do not run Stage 2; emit the summary with failure statuses.
- If Stage 2 fails, still emit the summary with `--stage2 failed`.

## Error Handling

At every boundary, verify the durable postcondition before advancing:

- Gate: `<run-dir>/assess-input.json` exists and validates; the route is `needs-plan` or `good-input`.
- Stage 1: `prepared-plan.md` exists and is non-empty.
- Plan input: the supplied plan path exists and is readable before review or implementation.
- Stage 2: `stage2-execution.md` exists and is non-empty.
- Summary: `executor-summary.json` is written by `cog executor summary`.

On failure, stop the chain, preserve the run directory artifacts, and still emit the executor summary
using the status rules above. Do not infer status from prose when a `cog` command reports structured
output.

## Guardrails

- Keep the gate, plan preparation, Claude implementation, and orchestration foreground; never
  background them.
- Native Codex effort only, via `--effort`, inside the delegated multi coordinators.
- Do not run git commands unless explicitly authorized.
- Deterministic mechanics stay behind `cog executor`, `cog assess-input`, `/plan-multi`, and
  `/review-plan-multi`.
- This skill executes one prompt or plan.
