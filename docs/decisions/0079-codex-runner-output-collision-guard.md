# ADR-0079: Guard codex-runner --output against clobbering durable prompt artifacts

## Context and Problem Statement

`cog codex-runner run-exec/run-resume --output <path>` maps to Codex's `--output-last-message`, which Codex overwrites with the agent's closing message ([`lib/functions/fn_codex.sh`](../../lib/functions/fn_codex.sh)). When the same run's prompt also embeds a durable artifact write to that same path — e.g. `$plan-oneshot
--output $RUN_DIR/prepared-plan.md`, which makes the inner agent run `cog plan-doc save --output
$RUN_DIR/prepared-plan.md` — the closing message clobbers the saved plan. Two adjacent `--output` tokens mean entirely different things, nothing detected the collision, and the read-back only checked non-empty, so a clobbered pointer passed. An orchestrator conflated the two at runtime and no layer stopped it (the `prepared-plan.md` holding an 8-line "the plan is saved here…" pointer incident).

## Considered Options

- Fix the skill prose in each affected skill to use distinct files (already true; does not make it deterministic — nothing stops the next conflation).
- A single runtime fail-closed guard at the `cog codex-runner` chokepoint.
- Runtime guard **plus** a static skill-lint rule **plus** read-back validation.

## Decision Outcome

Chosen option: **runtime guard plus static lint plus read-back**. The runtime guard in `run-exec`/ `run-resume` scans the prompt for `--output` targets and refuses to launch on exact absolute-path equality with the runner's own `--output` (`realpath -m`, no eval) — catching the resolved-path case for every skill routing through the chokepoint at once. The `codex-runner-output-collision` skill-lint rule catches the authored/unexpanded-`$RUN_DIR` case at authoring time. Stage read-backs use `cog
plan-doc validate` instead of a bare non-empty check, so a clobbered pointer fails deterministically.

## Consequences

- Good: the clobber is impossible to execute; protection is central, not per-skill prose.
- Good: authoring-time and read-back nets prevent silent reintroduction.
- Bad: equality-scoped by design — a symlinked run dir is a rare false-negative, never a false-positive (acceptable for a fail-closed guard); the lint ignores `<…>` placeholder tokens, so it only catches concrete/`$VAR` spellings, with the runtime guard covering the rest.

## Status

Implemented — [`lib/commands/cmd_codex_runner.sh`](../../lib/commands/cmd_codex_runner.sh) (`__cog_codex_runner_guard_output_collision`) and [`lib/commands/cmd_skill_lint.sh`](../../lib/commands/cmd_skill_lint.sh) (`codex-runner-output-collision`). Companion to [ADR-0061](./0061-rundir-scratch-artifact-convention.md).
