---
name: executor-greenfield-from-spec
description: >
  Run an operator-driven blind greenfield-from-spec pipeline: extract a sanitized
  capability contract from one or more purpose-tagged sources, review it for leakage,
  hydrate a target solution spec, review it, scaffold the target, and hand
  implementation to the queue runners. Each source carries a declared purpose — a
  specific-feature source or an abstracted general-inspiration source — and the
  coordinator confirms each purpose from context and interviews when it is unclear.
  Interviews the operator before each phase and stops at each milestone checkpoint to
  report and take direction; `-a`/`--auto` records default decisions and runs the whole
  pipeline back to back unattended.
argument-hint: "<source-path>... <target-path> <per-source purpose + reimplementation intent + target reference paths> [-a|--auto]"
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
coordinator owns the per-phase interviews, artifact routing, leakage loop, milestone checkpoints,
target setup, and final handoff. It accepts one or more purpose-tagged sources — specific-feature
sources and abstracted general-inspiration sources — and folds a single capability extractor over all
of them. Workers own extraction, review, solution planning, and solution review in fresh context.

This coordinator is operator-driven: it interviews the operator before each phase and stops at each
milestone checkpoint to report and take direction. `-a`/`--auto` records default decisions and runs
the pipeline back to back, stopping only on hard blockers.

Read these references before dispatch:

- `$(cog skill-refs path spec-pipeline/capability-spec-contract.md)`
- `$(cog skill-refs path spec-pipeline/solution-spec-contract.md)`
- `$(cog skill-refs path spec-pipeline/leakage-policy.md)`
- `references/worker-dispatch.md`
- `references/checkpoints.md`

## Inputs

The workflow needs:

1. One or more readable source project paths, each with a declared purpose: a specific-feature source
   (extract a particular capability) or a general-inspiration source (architecture and patterns,
   carried only as abstracted expectations). Resolve each source's purpose from context first, and
   interview when it is unclear.
2. A distinct target project path.
3. A free-form target objective.
4. User-supplied target reference-doc paths for stack, architecture, conventions, and project
   constraints.
5. Acceptance priorities that rank the target's success criteria.
6. Whether the target environment needs a `bootstrap` scaffold.
7. Execution scope for the queue tail: `runner-plan` for one plan or `runner-all` for the whole queue.

`$ARGUMENTS` may also carry `-a` or `--auto`. By default the run is interactive: the coordinator
interviews the operator before each phase and stops at each milestone checkpoint. `--auto` records
default decisions and runs the pipeline back to back, stopping only on the hard blockers in
`references/checkpoints.md`.

Ask one focused question when any required input is missing or ambiguous. Confirm that every source
path is readable and distinct from the target path before creating artifacts.

## Run Directory

Create scratch space before writing intermediate artifacts:

```bash
cog require rundir context-brief spec-leakage-scan skill-refs round-req round-split
cog rundir greenfield-from-spec
```

Use the printed `RUN_DIR=<path>` literally in later commands. Keep the private bundle, context
briefs, worker outputs, leakage reports, setup notes, and run report under that run directory. The
private bundle holds the union `source-leakage-denylist.txt` and optional per-source
`source-leakage-denylist-<slug>.txt` traceability files. Deliverables go to the target project only
when the implementation tail writes them.

## Workflow

Each phase runs its per-phase interview, does its work, then reports and takes direction at a
milestone checkpoint. `references/checkpoints.md` defines the interview banks, the checkpoint
contract (report shape, dynamic menu, response handling), and `--auto` behavior.

**Inputs phase.**

1. Run the Inputs interview for the source paths and each source's purpose, target path, target stack
   direction, reference-doc paths, acceptance priorities, bootstrap need, and execution scope.
2. Run the Inputs checkpoint before extraction.

**Capability phase.**

3. Run the Extraction interview for per-source purpose and scope, then build and validate a context
   brief for the capability extractor with all sources and their per-source purpose map. This is the
   only worker brief that may name the source paths.
4. Dispatch the single capability extractor as a fresh-context Agent worker over all sources; it emits
   one merged public bundle and the union `source-leakage-denylist.txt`.
5. Run `cog spec-leakage-scan` on the merged public bundle with the union `source-leakage-denylist.txt`.
6. Build and validate a context brief for capability review; include the public bundle and private
   denylist path. Dispatch capability review, and loop extraction and review until the public bundle
   is complete and leakage-free.
7. Run the Capability checkpoint before solution planning.

**Solution phase.**

8. Run the Solution interview, then build and validate a context brief for solution planning. Include
   only the public capability bundle, target path, target stack direction, and user reference-doc
   paths. Dispatch solution planning.
9. Build and validate a context brief for solution review. Include the solution bundle, the public
   capability bundle, and the denylist path only for behavioral-section leakage checks. Dispatch
   solution review, and loop solution planning and review until the bundle is approved.
10. Run the Solution checkpoint before bootstrap and setup.

**Setup phase.**

11. Dispatch `bootstrap` for target environment scaffold when the target needs setup.
12. Run the Setup checkpoint in `references/checkpoints.md`.

**Handoff phase.**

13. Run the Handoff checkpoint, then hand the approved solution bundle to
    `plan-builder-to-queue-vetted-multi` as the plan-to-queue tail and run the selected runner
    (`runner-plan` or `runner-all`) per the chosen execution scope.
14. Write a run report under `RUN_DIR` with artifact paths, review verdicts, leakage scan results,
    checkpoint report paths, the auto-decision log for `--auto` runs, setup postcondition, runner
    result, and remaining risks.

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

Only the capability extractor may know the sources exist. Inspiration-source architecture survives
only as abstracted, sanitized capability, nonfunctional, and structural expectations; the solution
planner designs its own architecture and receives no source architecture from any source, whether
specific-feature or general-inspiration. The solution planner receives the public capability bundle
and target references only. It never receives the private bundle, source tests, source commands,
source roots, or source observation notes.

## Completion

Finish by reporting:

- every source path with its declared purpose;
- target project path;
- public capability bundle path;
- approved solution bundle path;
- leakage scan report paths;
- checkpoint report paths under `RUN_DIR`, and the auto-decision log for `--auto` runs;
- runner result;
- manual setup postcondition;
- remaining risks and follow-ups.
