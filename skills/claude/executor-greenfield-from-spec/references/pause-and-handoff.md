# Pause And Handoff

This reference defines the coordinator-owned manual setup pause and implementation tail.

## Setup Pause

After target scaffold completes and before queue execution, print exact numbered setup steps for the
user. Include:

1. commands the user must run;
2. files or environment variables the user must create;
3. the expected postcondition;
4. the validation command the coordinator will run after confirmation.

Stop with one `AskUserQuestion` confirmation. Resume only after the user confirms the setup is done.
On resume, validate the postcondition before continuing. If validation fails, report the failed
postcondition and ask for correction.

## Queue Handoff

Use the approved solution bundle as the implementation input for the plan-to-queue tail:

- run `plan-builder-to-queue-vetted-multi` as the plan-to-queue tail — its dual-engine generation
  and dual-engine review fit a blind greenfield reimplementation;
- preserve requirement IDs in queue prompts;
- use `cog round-split coverage` against `requirement-trace.yaml` before runner dispatch;
- dispatch `runner-plan` or `runner-all` according to the user's chosen execution scope.

## Report

The run report under `RUN_DIR` records:

- source path and target path;
- public capability bundle path;
- approved solution bundle path;
- leakage scan report paths;
- setup postcondition and validation result;
- queue path and runner result;
- unresolved questions, waivers, and risks.
