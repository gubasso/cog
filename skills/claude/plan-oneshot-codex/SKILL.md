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

Build one lean implementation plan by delegating the full planning turn to Codex's `$plan-oneshot` skill. Claude owns only argument handling, Codex preflight, runner invocation, postcondition checks, and reporting the saved plan path.

**Context-brief gate.** Before dispatching to any fresh-context worker, build and validate its input brief per `$(cog skill-refs path orchestration/context-brief-gate.md)` — build it with `cog context-brief build --request` and confirm it with `cog context-brief validate`.

## Inputs

`$ARGUMENTS` accepts the same shape as `$plan-oneshot`:

- Optional leading `--output <abs.md>` - save to this absolute markdown path.
- Optional leading `--research-root <dir>` - pass through to the Codex planner.
- Required orientation, focus, or goal text.

If the orientation is missing or materially ambiguous, ask one focused clarification before creating the Codex prompt.

## Orchestration

Create a workflow run directory with `cog rundir plan-oneshot-codex`. Use the returned `RUN_DIR` literal in every later command. If the user supplied `--output`, use it as the plan path; otherwise use `<RUN_DIR>/plan.md`.

Gate Codex before writing the prompt with `cog codex-runner gate sandbox <RUN_DIR>/preflight.json`. Stop on failure and report the preflight path.

Build the Codex worker's input as a validated context brief. Write the complete user orientation verbatim and in full to `<RUN_DIR>/request.md`, then build the brief per `$(cog skill-refs path orchestration/context-brief-contract.md)`: scaffold the authored body, fill it from the whole session (a well-oriented **Objective**; **Output Format**; **Boundaries**; **Context & Decisions** carrying the full substance; **Artifacts** inline or pointed-to; **Effort Guidance**; **Not Evaluated** — keep your own verdict out), then build it:

```bash
cog context-brief template --out "<RUN_DIR>/brief-body.md"
# fill <RUN_DIR>/brief-body.md per the contract, then:
cog context-brief build --request "<RUN_DIR>/request.md" --body "<RUN_DIR>/brief-body.md" --out "<RUN_DIR>/brief.md"
```

`build` attaches the orientation verbatim and fails closed unless every section is filled.

Write `<RUN_DIR>/plan-prompt.md` with:

- The literal first line `$plan-oneshot`.
- The write orientation from `cog codex-runner orientation write`.
- `--output <plan-path>` plus any forwarded `--research-root`.
- The validated context brief `<RUN_DIR>/brief.md` as the complete orientation/context.
- The instruction that Codex must save exactly one lean plan through `cog plan-doc`, print the plan, and report assumptions, ambiguities, dependencies, and risks.

Launch the durable Codex job, then poll-and-classify it with one verb, `cog codex-runner finalize
--max-wall <secs>`. The exit code is the signal (0 = ok · 1 = failed · 75 = still running); re-run finalize while it exits 75. Duration is never judged.

```bash
cog codex-runner run-exec --mode danger --access write --effort medium --prompt <RUN_DIR>/plan-prompt.md --output <RUN_DIR>/plan-codex-output.md --events <RUN_DIR>/plan-events.jsonl --stderr <RUN_DIR>/plan-stderr.log --thread last --state <RUN_DIR>/plan.longrun.json
# Re-run while it exits 75 (still running); exit code is the signal (0 = ok, 1 = failed, 75 = still running). Duration is never judged.
cog codex-runner finalize --state <RUN_DIR>/plan.longrun.json --max-wall 300 > <RUN_DIR>/plan-runner.json
```

`finalize` writes the runner JSON to `<RUN_DIR>/plan-runner.json`. Treat the plan path, not the runner output, as the authoritative artifact. Confirm the saved plan with `cog plan-doc validate
<plan-path>` before reporting success — a plan clobbered by a last-message pointer fails validation deterministically.

## Final Response

Print the saved plan path and a concise status summary. If Codex fails, report the runner JSON path, stderr path, status, and whether the plan artifact exists.

## Guardrails

- The Codex run is a cog-owned durable job (`run-exec` + `finalize --max-wall`); the exit code is the signal (0 = ok, 1 = failed, 75 = still running) and duration is never judged.
- Use native effort through `--effort`; never use legacy profiles.
- Do not run git commands.
- Deterministic runner mechanics stay behind `cog rundir` and `cog codex-runner`.
