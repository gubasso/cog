---
name: plan-multi
description: >
  Dual-engine lean-plan coordinator. Claude and Codex each independently draft one lean
  implementation plan in parallel from one identical raw context brief, then the main-thread Claude
  reviews both and synthesizes a single best-of-both lean plan saved through cog plan-doc. Use when
  the user says "plan-multi", "dual-engine lean plan", "one plan with codex", "two lean plans then
  synthesize", or wants a second independent engine cross-checking a lean plan. Optional flags:
  --output <abs.md>, --research-root <dir>, --solo (skip Codex; Claude-only).
argument-hint: "[--output <abs.md>] [--research-root <dir>] [--solo] <orientation/focus/goal>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Grep Glob Agent AskUserQuestion
---

<!-- trigger-tests: "plan-multi", "dual-engine lean plan", "one plan with codex", "two lean plans then synthesize" -->
<!-- cog-skill: plan-emitter -->
<!-- cog-skill: input-fidelity -->

# Plan Multi

Coordinate two independent lean planners from one identical raw brief, then synthesize one validated
lean plan through `cog plan-doc`. The workers are `/plan-oneshot` instances; the coordinator builds
their complete input and owns the final plan.

**Context-brief gate.** Before dispatching to any fresh-context worker, build and validate its input
brief per `$(cog skill-refs path orchestration/context-brief-gate.md)` — build it with
`cog context-brief build --request` and confirm it with `cog context-brief validate`.

## Inputs

`$ARGUMENTS` accepts:

- Optional `--output <abs.md>`: final synthesized lean-plan path.
- Optional `--research-root <dir>`: research shelf root passed through to research and final save.
- Optional `--solo`: skip Codex and run the Claude planner only.
- Required orientation, focus, or goal text.

## Phase 1: Setup

Parse flags and create run state:

```bash
cog plan-multi-setup "$ARGUMENTS"
```

Capture `RUN_DIR`, `SOLO`, `REPO_ROOT`, `ORIENTATION_FILE`, `OUTPUT`, `RESEARCH_ROOT`,
`BRIEF_FILE`, `CLAUDE_PLAN`, and `CODEX_PLAN`. Shell state does not persist; substitute literal paths
into later Bash calls.

## Phases 2-4: Gather, research, interview

Follow `/plan-oneshot` Phases 2-4 inline:

- Read the research shelf with `cog research-shelf`; pass `--root "$RESEARCH_ROOT"` when
  `RESEARCH_ROOT` is non-empty.
- Research the repo with Read/Grep/Glob/Bash. Capture absolute paths and quoted code or signatures.
- Interview with `AskUserQuestion` only in this coordinator. If the task is already fully specified,
  record that no interview was needed.

Workers must not ask the user anything.

## Phase 5: Build the context brief

Build `BRIEF_FILE`, the single identical input for both workers, as a best-constructed context brief
per `$(cog skill-refs path orchestration/context-brief-contract.md)`. Scaffold the authored sections:

```bash
cog context-brief template --out "$RUN_DIR/brief-body.md"
```

Fill `$RUN_DIR/brief-body.md`: a well-oriented **Objective** drawn from the whole session; **Output
Format** (one lean implementation-plan draft); **Boundaries / Scope** (including hard constraints such
as no git commands unless explicitly authorized); **Context & Decisions** (quoted conversation,
interview Q&A, decisions and rationale — summarize narrative for clarity but carry the full substance);
**Artifacts & Pointers** (codebase research as raw excerpts with absolute paths, plus any
session-generated plan); **Effort Guidance**; and **Not Evaluated**. Keep your own proposed approach,
plan, verdict, or solution out — bias isolation is the single deliberate omission.

```bash
cog context-brief build --request "$ORIENTATION_FILE" --body "$RUN_DIR/brief-body.md" --out "$BRIEF_FILE"
```

`build` attaches the orientation verbatim as the Original Request and fails closed unless every section
is filled.

If `SOLO=1`, skip Phase 6 and the Codex half of Phase 7.

## Phase 6: Preflight

Gate Codex readiness with a degrading check:

```bash
if cog codex-runner gate sandbox "$RUN_DIR/preflight.json" >/dev/null 2>&1; then
  SANDBOX_MODE="$(jq -r '.codex_session.sandbox_mode' "$RUN_DIR/preflight.json")"
  echo "SANDBOX_MODE=$SANDBOX_MODE"
else
  echo "PREFLIGHT_DEGRADED=1 (codex-session unavailable/unhealthy or missing cog)"
fi
```

On failure, mark Codex unavailable and continue Claude-only. If `SANDBOX_MODE=fallback`, tell the
user in one line.

## Phase 7: Parallel drafts

### 7a: Prepare dispatch artifacts

Take a pre-snapshot, remove stale draft/proof files, and write the Codex prompt:

```bash
cog codex-runner snapshot-pre "$RUN_DIR" "$RUN_DIR/drafts-pre.snap" > "$RUN_DIR/drafts-pre-snapshot.json"
rm -f "$CLAUDE_PLAN" "$CODEX_PLAN" "$RUN_DIR/drafts-proof.diff"
```

The Codex prompt file must open with `$(cog codex-runner orientation write)`, mention
`$plan-oneshot`, pass `--output <CODEX_PLAN>` plus `--research-root <RESEARCH_ROOT>` when set, and
inline `BRIEF_FILE` as the sole self-contained context. Tell Codex to research as needed, not
interview, and save exactly one lean plan through `cog plan-doc`.

### 7b: Dispatch both workers

In one assistant message, issue both calls so they run concurrently. Skip Codex when degraded or
`SOLO=1`.

Claude Agent prompt:

```text
Read $HOME/.claude/skills/plan-oneshot/SKILL.md and follow it end-to-end. Use the brief at
<BRIEF_FILE> as the complete orientation/context. Pass --output <CLAUDE_PLAN> and, when set,
--research-root <RESEARCH_ROOT>. Do not interview; the brief is fully specified, so pick
conservative defaults and record assumptions. Save one lean plan to the output path and write
nothing outside that output path. Return one line with the path.
```

Codex launch:

```bash
cog codex-runner run-exec \
  --mode danger \
  --access write \
  --effort high \
  --prompt "$RUN_DIR/codex-plan-prompt.txt" \
  --output "$RUN_DIR/codex-plan-last.txt" \
  --events "$RUN_DIR/codex-events.jsonl" \
  --stderr "$RUN_DIR/codex-stderr.log" \
  --state "$RUN_DIR/codex.longrun.json"
```

After the Agent returns, poll-and-classify with `cog codex-runner finalize --state
"$RUN_DIR/codex.longrun.json" --max-wall 300`, re-running while it exits 75. Duration is never
judged.

### 7c: Verify proof

```bash
cog codex-runner snapshot-post "$RUN_DIR" "$RUN_DIR/drafts-pre.snap" "$RUN_DIR/drafts-post.snap" "$RUN_DIR/drafts-proof.diff" > "$RUN_DIR/drafts-post-snapshot.json"
cog codex-runner verify-proof --proof "$RUN_DIR/drafts-proof.diff" --artifact "$CLAUDE_PLAN" > "$RUN_DIR/drafts-verify.json"
```

The Claude draft is required; if proof or draft is missing, stop and ask retry or abort. The Codex
draft is best-effort; if the runner is non-ok, SIGTERM, or `CODEX_PLAN` is missing/empty, continue
Claude-only and remember the reason.

## Phase 8: Synthesize the lean plan

Read `CLAUDE_PLAN` and any usable `CODEX_PLAN`. As neutral judge, steelman both against the
`/plan-oneshot` lean-plan requirements and the verdict model from
`$(cog skill-refs path orchestration/verdict-model.md)`: correctness, completeness, feasibility,
repo fit, currency, and testability. Verify disagreements against the actual codebase before
deciding; prefer current evidence over either draft.

Write the final plan yourself:

```bash
cog plan-slug --text "$(cat "$ORIENTATION_FILE")" --json
cog plan-doc save --title "$TITLE" --repo-root "$REPO_ROOT" --output "$OUTPUT" --json
cog plan-doc validate "$OUTPUT" --json
```

`cog plan-doc save` creates the scaffold and returns the output path (`PLAN_DOC_PATH`); it does not
accept generated plan content on stdin. After it returns, write the synthesized lean-plan content into
that returned absolute path, then validate. Pass `--research-root "$RESEARCH_ROOT"` to
`cog plan-doc save` when set. Preserve the required `plan-doc` headings. If validation fails, fix the
generated plan headings and validate again. When degraded, synthesize over the Claude plan alone.

## Phase 9: Confirm

Print the final lean plan, report `OUTPUT`, assumptions, ambiguities, and synthesis provenance:
independent Claude and Codex drafts, or Claude-only if degraded. If Codex was unavailable, prepend:

```text
(codex cross-check unavailable: <short reason>)
```

Scratch artifacts remain in `RUN_DIR`.

## Guardrails

- The coordinator is the only user-interactive component.
- Workers write only their scratch draft paths; only the coordinator writes `OUTPUT`.
- Use Agent for Claude delegation; never use Skill.
- Use `cog codex-runner run-exec --state`; never use bare `codex exec`.
- Use `--mode danger --access write --effort high` for the Codex plan worker.
- Do not run git commands.
- Do not create `.implementation-plans/`, queues, or plan directories.
- For single-engine lean planning, prefer `/plan-oneshot`; `--solo` exists for uniform degradation.
