---
name: executor-greenfield-from-spec
description: >
  Run a blind greenfield-from-spec pipeline: extract a sanitized capability
  contract from a source, review it for leakage, hydrate a target solution spec,
  review it, scaffold the target, and hand implementation to the queue runners.
argument-hint: "<source-path> <target-path> <reimplementation intent and target reference paths>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Agent Skill AskUserQuestion
---

<!-- trigger-tests: "greenfield from spec", "blind greenfield reimplementation", "from-scratch target from source capability", "executor-greenfield-from-spec" -->
<!-- cog-skill: input-fidelity -->

# Greenfield From Spec Executor

<!-- cog-plan-mode-gate -->

**Phase 0 — Plan-mode gate.** If Claude Code **plan mode** is active (a system-reminder says plan
mode is on / that you must not make edits), **STOP** before any other work — parsing args,
researching, interviewing, delegating, or writing. Tell the user in one line to exit plan mode
(`Shift+Tab`) and re-invoke `/executor-greenfield-from-spec`. Do not call `ExitPlanMode`, and do not silently continue.

<!-- cog-context-brief-gate -->

**Context-brief gate.** Before `/executor-greenfield-from-spec` dispatches to any fresh-context worker — an Agent subagent
or a `cog codex-runner` Codex job — build its input as a validated context brief from your whole
accumulated raw context: attach the raw request as-is, author an oriented objective, carry the full
substance and load-bearing artifacts, and omit your own verdict. Build the brief with `cog
context-brief build` and confirm it with `cog context-brief validate` before dispatch.

Run a source-aware coordinator that gives every downstream worker only sanitized artifacts. The
coordinator owns the interview, artifact routing, leakage loop, target setup pause, and final
handoff. Workers own extraction, review, solution planning, and solution review in fresh context.

Read these references before dispatch:

- `$(cog skill-refs path spec-pipeline/capability-spec-contract.md)`
- `$(cog skill-refs path spec-pipeline/solution-spec-contract.md)`
- `$(cog skill-refs path spec-pipeline/leakage-policy.md)`
- `references/worker-dispatch.md`
- `references/pause-and-handoff.md`

## Inputs

The workflow needs:

1. A readable source project path.
2. A distinct target project path.
3. A free-form target objective.
4. User-supplied target reference-doc paths for stack, architecture, conventions, and project
   constraints.

Ask one focused question when any required input is missing or ambiguous. Confirm that source and
target paths differ before creating artifacts.

## Run Directory

Create scratch space before writing intermediate artifacts:

```bash
cog require rundir context-brief spec-leakage-scan skill-refs round-req round-split
cog rundir greenfield-from-spec
```

Use the printed `RUN_DIR=<path>` literally in later commands. Keep the private bundle, context
briefs, worker outputs, leakage reports, setup notes, and run report under that run directory.
Deliverables go to the target project only when the implementation tail writes them.

## Workflow

1. Interview once for source path, target path, target stack direction, reference-doc paths, and
   acceptance priorities.
2. Build and validate a context brief for the capability extractor. This is the only worker brief
   that may name the source path.
3. Dispatch the capability extractor as a fresh-context Agent worker.
4. Run `cog spec-leakage-scan` on the public capability bundle with the private denylist.
5. Build and validate a context brief for capability review; include the public bundle and private
   denylist path.
6. Dispatch capability review. Loop extraction and review until the public bundle is complete and
   leakage-free.
7. Build and validate a context brief for solution planning. Include only the public capability
   bundle, target path, target stack direction, and user reference-doc paths.
8. Dispatch solution planning.
9. Build and validate a context brief for solution review. Include the solution bundle, the public
   capability bundle, and the denylist path only for behavioral-section leakage checks.
10. Dispatch solution review. Loop solution planning and review until the bundle is approved.
11. Dispatch `bootstrap` for target environment scaffold when the target needs setup.
12. Run the human setup pause in `references/pause-and-handoff.md`.
13. Hand the approved solution bundle to the plan-to-queue tail and run the selected runner.
14. Write a run report under `RUN_DIR` with artifact paths, review verdicts, leakage scan results,
   setup postcondition, runner result, and remaining risks.

## Context Brief Mechanics

For each fresh-context worker, write the raw request and authored body under `RUN_DIR`, then build and
validate the brief:

```bash
cog context-brief build --request "$RUN_DIR/raw-request.md" --body "$RUN_DIR/brief-body.md" --out "$RUN_DIR/worker-brief.md"
cog context-brief validate "$RUN_DIR/worker-brief.md"
```

The brief carries the raw request, objective, boundaries, decisions, artifact paths, effort guidance,
and not-evaluated list. It omits this coordinator's verdict so each review remains independent.

## Leakage Rule

Only the capability extractor may know the source exists. The solution planner receives the public
capability bundle and target references only. It never receives the private bundle, source tests,
source commands, source roots, or source observation notes.

## Completion

Finish by reporting:

- target project path;
- public capability bundle path;
- approved solution bundle path;
- leakage scan report paths;
- runner result;
- manual setup postcondition;
- remaining risks and follow-ups.
