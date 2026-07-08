# Checkpoints And Handoff

This reference defines the coordinator-owned per-phase interviews, the milestone checkpoints, the
`--auto` mode, the queue handoff, and the final run report. The coordinator runs native in the
caller's session, so every interview and checkpoint reaches the operator directly.

## Per-Phase Interviews

Before building each phase's brief, interview the operator to direct that phase's decisions. Ask
focused, option-driven questions with `AskUserQuestion`; confirm rather than re-ask whatever the
original request already settled. Every answer lands in that phase's brief under *Context &
Decisions* — it steers workers without ever routing source knowledge to a blind worker.

Interview banks by phase:

- **Inputs** — the source paths and each source's purpose (specific-feature or general-inspiration,
  confirmed from context and asked only when unclear), target path, target objective, target
  reference-doc paths, acceptance priorities, whether the target needs a `bootstrap` scaffold,
  execution scope (`runner-plan`/`runner-all`), and interactive-versus-`--auto` mode.
- **Extraction** — per-source scope: for each specific-feature source, which behaviors matter most,
  which areas are out of scope, and how deeply to capture edge cases; for each general-inspiration
  source, which architectural qualities to abstract behind the leakage firewall.
- **Solution** — architecture and stack options, which acceptance priorities dominate design
  tradeoffs, and target module boundaries.
- **Setup** — confirmation that the printed setup steps are complete (see Setup Checkpoint).
- **Handoff** — execution scope and the final go/no-go.

## Checkpoint Contract

Every milestone checkpoint follows one shape:

1. Write a checkpoint report to `$RUN_DIR/checkpoint-<role>.md` — one of
   `checkpoint-inputs.md`, `checkpoint-capability.md`, `checkpoint-solution.md`,
   `checkpoint-setup.md`, `checkpoint-handoff.md`. Each report records:
   - the phase just completed and the worker verdict;
   - key artifacts and a bundle summary, with paths;
   - leakage and scan status where relevant;
   - decisions taken this phase;
   - open questions and risks;
   - the proposed next phase.
2. Present a concise summary of that report to the operator.
3. Ask one `AskUserQuestion`. The menu always offers **Continue**, **Adjust**, **Redirect**, and
   **Abort**, and adds **coordinator-generated options** authored from the live run context whenever
   they help — a decision gate, extra questions for the operator, a command for the operator to run
   and paste back, or any other option that unblocks the run.

Response handling:

- **Continue** — proceed to the next phase.
- **Adjust** — collect the operator's notes, fold them into this phase's brief under *Context &
  Decisions*, and re-run this phase. This drives the extraction↔review and planning↔review loops.
- **Redirect** — revise the global direction (acceptance priorities, target stack, or execution
  scope) and re-enter from the affected earlier phase.
- **Abort** — write the final run report with current state and stop; artifacts remain under
  `RUN_DIR`.

## Milestone Checkpoints

The run stops at five milestones:

1. **Inputs** — after the opening interview, before capability extraction.
2. **Capability** — after capability review approves and `cog spec-leakage-scan` of the merged bundle
   against the union `source-leakage-denylist.txt` reports clean, before solution planning. The
   `checkpoint-capability.md` report records the per-source contribution summary and the union
   denylist path.
3. **Solution** — after solution review approves, before bootstrap and setup.
4. **Setup** — after target scaffold, before handoff (see Setup Checkpoint).
5. **Handoff** — before runner dispatch: confirm execution scope and go/no-go.

## Setup Checkpoint

After target scaffold completes and before queue execution, print exact numbered setup steps for the
operator. Include:

1. commands the operator must run;
2. files or environment variables the operator must create;
3. the expected postcondition;
4. the validation command the coordinator runs after confirmation.

Resume only after the operator confirms the setup is done. On resume, validate the postcondition
before continuing. If validation fails, report the failed postcondition and ask for correction.

## Auto Mode (`-a`/`--auto`)

In `--auto` mode the coordinator runs back to back: at each checkpoint it records the default
decision (Continue) with a one-line rationale in the checkpoint report and proceeds without stopping,
and each per-phase interview uses best-default choices recorded the same way. Hard blockers still
stop the run even in `--auto`:

- the leakage scan is not clean;
- a review verdict is still `revise` after the loop is exhausted;
- a setup postcondition fails.

The final run report enumerates every recorded auto-decision.

## Queue Handoff

Use the approved solution bundle as the implementation input for the plan-to-queue tail:

- run `plan-builder-to-queue-vetted-multi` as the plan-to-queue tail — its dual-engine generation
  and dual-engine review fit a blind greenfield reimplementation;
- preserve requirement IDs in queue prompts;
- use `cog round-split coverage` against `requirement-trace.yaml` before runner dispatch;
- dispatch `runner-plan` or `runner-all` according to the chosen execution scope.

## Final Report

The run report under `RUN_DIR` records:

- every source path with its declared purpose, and the target path;
- the union `source-leakage-denylist.txt` path;
- public capability bundle path;
- approved solution bundle path;
- leakage scan report paths;
- checkpoint report paths and, for `--auto` runs, the auto-decision log;
- setup postcondition and validation result;
- queue path and runner result;
- unresolved questions, waivers, and risks.
