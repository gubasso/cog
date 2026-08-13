---
name: review-plan-oneshot-codex
description: >
  Review one implementation plan with Codex under the hood, while Claude gates
  the plan input, orchestrates the runner call, and surfaces the saved annotated
  review. Use when the user says "review-plan-oneshot-codex", "have Codex review
  this plan", or wants a single independent Codex plan review. Accepts a plan
  file, a plan directory, or inline plan text from the session.
model: opus
effort: low
argument-hint: "<plan-file | plan-dir | inline plan+context>"
disable-model-invocation: true
allowed-tools: Bash Read Write AskUserQuestion
---

<!-- trigger-tests: "review-plan-oneshot-codex", "have Codex review this plan", "review this plan with codex only" -->
<!-- cog-skill: input-fidelity -->

# Review Plan One Codex

Review one implementation plan before implementation by delegating the whole reviewing turn to Codex's `$review-plan-oneshot` skill. Claude owns only input handling, the plan gate, Codex preflight, brief construction, runner invocation, postcondition checks, and reporting the saved review path. Every review axis and every annotation is Codex's call.

**Context-brief gate.** Before dispatching to any fresh-context worker, build and validate its input brief per `$(cog skill-refs path orchestration/context-brief-gate.md)` — build it with `cog context-brief build --request` and confirm it with `cog context-brief validate`.

## Inputs

`$ARGUMENTS` is the plan to review, in any of three forms:

- A plan **file** path.
- A plan **directory** of markdown sources.
- **Inline** text carrying the plan (and often its context) from the session.

Required. If `$ARGUMENTS` is empty, ask the user for the plan before proceeding. This skill depends only on the plan structure it reads; it is blind to which skill produced the plan.

## Phase 1: Setup And The Plan Gate

Create the run directory and bind it once; use the returned literal in every later command.

```bash
RUN_DIR="$(cog rundir review-plan-oneshot-codex | sed -n 's/^RUN_DIR=//p')"
[ -n "$RUN_DIR" ] || { echo "ERROR: cog rundir did not emit RUN_DIR" >&2; exit 1; }
```

When `$ARGUMENTS` is not an existing path, write the inline text verbatim to `<RUN_DIR>/raw-input.txt` first.

**Plan-input gate.** Confirm the input is a reviewable plan per `$(cog skill-refs path plan-quality/plan-input-gate.md)` before building anything and before any Codex dispatch:

```bash
cog plan-gate check <plan-file | plan-dir>            # path input
cog plan-gate check --input-file <RUN_DIR>/raw-input.txt   # inline input
```

On `insufficient`, stop: report the gate's reason and ask the user to build a plan first. Do not review, and do not write the plan yourself.

## Phase 2: Build The Worker's Inputs

Produce the pair of artifacts the Codex reviewer consumes.

**`<RUN_DIR>/plan-under-review.md`** — the consolidated plan content:

- File input — use the plan file's content.
- Directory input — read the gate's passing sources plus the other markdown files in listed order and consolidate them, preserving each file's heading and content.
- Inline input — separate the plan portion of `<RUN_DIR>/raw-input.txt` into the consolidated file.

**`<RUN_DIR>/request.md`** — the goal and context the plan is reviewed **against**. Write the user's original request verbatim and in full to `<RUN_DIR>/objective.txt`, then build the brief per `$(cog skill-refs path orchestration/context-brief-contract.md)`: scaffold the authored body, fill it from the whole session (a well-oriented **Objective**; **Output Format**; **Boundaries**; **Context & Decisions** carrying the full substance; **Artifacts** inline or pointed-to; **Effort Guidance**; **Not Evaluated**), then build it:

```bash
cog context-brief template --out "<RUN_DIR>/request-body.md"
# fill <RUN_DIR>/request-body.md per the contract, then:
cog context-brief build --request "<RUN_DIR>/objective.txt" --body "<RUN_DIR>/request-body.md" --out "<RUN_DIR>/request.md"
cog context-brief validate "<RUN_DIR>/request.md"
```

`build` attaches the request verbatim and fails closed unless every section is filled.

**Keep your own verdict out of both files.** Any critique or proposed fix you inject biases the reviewer and turns an independent Codex opinion into a rubber stamp on yours.

## Phase 3: Preflight And Dispatch

Gate Codex before writing the prompt with `cog codex-runner gate sandbox <RUN_DIR>/preflight.json`. Fail closed on failure and report the preflight path.

Write `<RUN_DIR>/review-prompt.md` with:

- The literal first line `$review-plan-oneshot`.
- The write orientation from `cog codex-runner orientation write`.
- The three absolute paths its Orchestrator Invocation Contract expects, in order: `<RUN_DIR>/plan-under-review.md`, `<RUN_DIR>/request.md`, `<RUN_DIR>/review.md`.
- The instruction that Codex saves the annotated review through `cog plan-review` and validates it before returning.

The Codex worker writes its artifact through `cog plan-review`, so it runs write-capable at `high` effort, matching its own documented invocation contract. Launch the durable job, then poll-and-classify with one verb, `cog codex-runner finalize --max-wall <secs>`. The exit code is the signal (0 = ok · 1 = failed · 75 = still running); re-run finalize while it exits 75. Duration is never judged.

```bash
cog codex-runner run-exec --mode danger --access write --effort high --prompt <RUN_DIR>/review-prompt.md --output <RUN_DIR>/review-codex-output.md --events <RUN_DIR>/review-events.jsonl --stderr <RUN_DIR>/review-stderr.log --state <RUN_DIR>/review.longrun.json
# Re-run while it exits 75 (still running).
cog codex-runner finalize --state <RUN_DIR>/review.longrun.json --max-wall 300 > <RUN_DIR>/review-runner.json
```

Branch on the runner's structured status and `cog codex-runner explain-status <status>` for quota and error handling.

## Phase 4: Confirm

Treat the review artifact, not the runner output, as authoritative:

```bash
cog plan-review validate <RUN_DIR>/review.md --json
```

A review clobbered by a last-message pointer fails validation deterministically.

## Final Response

Print the top-level verdict, the saved review path, and the count of `APPROVED` / `MODIFIED` / `REMOVED` / `ADDED` annotations. If Codex fails, report the runner JSON path, the stderr path, the status, and whether the review artifact exists.

## Guardrails

- The Codex run is a cog-owned durable job (`run-exec` + `finalize --max-wall`); the exit code is the signal and duration is never judged.
- Use native effort through `--effort`; never use legacy profiles.
- Review one plan only; do not implement it.
- Scratch stays under `RUN_DIR`; artifact paths passed to the runner are absolute.
- Do not run git commands.
- For a dual-engine cross-check that also runs Claude and reconciles both reviews, use `/review-plan-multi`.
