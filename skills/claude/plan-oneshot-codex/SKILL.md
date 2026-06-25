---
name: plan-oneshot-codex
description: >
  Build one lean implementation plan with Codex under the hood, while Claude
  orchestrates the runner call and surfaces the saved plan path.
model: opus
effort: low
argument-hint: "[--output <abs.md>] [--research-root <dir>] <orientation/focus/goal>"
disable-model-invocation: true
allowed-tools: Bash Read Write AskUserQuestion
---

<!-- trigger-tests: "plan-oneshot-codex", "have Codex write one lean plan", "plan with Codex under the hood" -->
<!-- cog-skill: plan-emitter -->
<!-- cog-skill: input-fidelity -->

# Plan One Lean Codex

Build one lean implementation plan by delegating the full planning turn to Codex's `$plan-oneshot`
skill. Claude owns only argument handling, Codex preflight, runner invocation, postcondition checks,
and reporting the saved plan path.

## Inputs

`$ARGUMENTS` accepts the same shape as `$plan-oneshot`:

- Optional leading `--output <abs.md>` - save to this absolute markdown path.
- Optional leading `--research-root <dir>` - pass through to the Codex planner.
- Required orientation, focus, or goal text.

If the orientation is missing or materially ambiguous, ask one focused clarification before creating
the Codex prompt.

## Orchestration

Create a workflow run directory with `cog rundir plan-oneshot-codex`. Use the returned `RUN_DIR`
literal in every later command. If the user supplied `--output`, use it as the plan path; otherwise
use `<RUN_DIR>/stage1-plan.md`.

Gate Codex before writing the prompt with `cog codex-runner gate sandbox <RUN_DIR>/preflight.json`.
Stop on failure and report the preflight path.

Write `<RUN_DIR>/stage1-prompt.md` with:

- The literal first line `$plan-oneshot`.
- The write orientation from `cog codex-runner orientation write`.
- `--output <plan-path>` plus any forwarded `--research-root`.
- The complete user orientation, verbatim and in full, plus only enriching constraints.
- The instruction that Codex must save exactly one lean plan through `cog plan-doc`, print the plan,
  and report assumptions, ambiguities, dependencies, and risks.

The prompt is an enrichment-only superset of the original input and must not replace the user
orientation with a summary.

Launch the durable Codex job, then poll-and-classify it with one verb, `cog codex-runner finalize
--max-wall <secs>`. The exit code is the signal (0 = ok · 1 = failed · 75 = still running);
re-run finalize while it exits 75. Duration is never judged.

```bash
cog codex-runner run-exec --mode danger --access write --effort high --prompt <RUN_DIR>/stage1-prompt.md --output <RUN_DIR>/stage1-codex-output.md --events <RUN_DIR>/stage1-events.jsonl --stderr <RUN_DIR>/stage1-stderr.log --thread last --state <RUN_DIR>/stage1.longrun.json
# Re-run while it exits 75 (still running); exit code is the signal (0 = ok, 1 = failed, 75 = still running). Duration is never judged.
cog codex-runner finalize --state <RUN_DIR>/stage1.longrun.json --max-wall 300 > <RUN_DIR>/stage1-runner.json
```

`finalize` writes the runner JSON to `<RUN_DIR>/stage1-runner.json`. Treat the plan path, not the
runner output, as the authoritative artifact. Verify the plan path exists and is non-empty before
reporting success.

## Final Response

Print the saved plan path and a concise status summary. If Codex fails, report the runner JSON path,
stderr path, status, and whether the plan artifact exists.

## Guardrails

- The Codex run is a cog-owned durable job (`run-exec` + `finalize --max-wall`); the exit code is the signal (0 = ok, 1 = failed, 75 = still running) and duration is never judged.
- Use native effort through `--effort`; never use legacy profiles.
- Do not run git commands.
- Deterministic runner mechanics stay behind `cog rundir` and `cog codex-runner`.
