---
name: review-plan-multi
description: >
  Dual-engine plan-review coordinator. Claude and Codex each independently review the
  same plan in parallel from one identical raw request brief, then the main-thread Claude
  reconciles both annotated reviews into a single vetted review saved through cog
  plan-review. Use when the user says "review-plan-multi", "dual-engine plan review",
  "review this plan with codex", "two reviews then synthesize", or wants a second
  independent engine cross-checking a plan review. Accepts a plan file or inline
  plan+context text. Optional flag: --solo (skip Codex; Claude-only).
argument-hint: "[--solo] <plan-file | inline plan+context>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Grep Glob Agent AskUserQuestion
---

<!-- trigger-tests: "review-plan-multi", "dual-engine plan review", "review this plan with codex", "two reviews then synthesize" -->
<!-- cog-skill: plan-emitter -->
<!-- cog-skill: input-fidelity -->

# Review Plan Multi

Coordinate **two independent plan reviewers** — Claude and Codex — reviewing the **same plan** in parallel from the **same raw request brief**, then reconcile both annotated reviews into one definitive vetted review saved through `cog plan-review`. A second engine, blind to the other's reasoning, surfaces risks, missing steps, and alternative judgments the first engine misses.

This skill runs **inline** (no fork): only the main thread can read the live conversation, build the request brief, and act as the neutral judge. It **delegates** each review to a non-interactive worker and keeps all interaction and the final write to itself.

**Context-brief gate.** Before dispatching to any fresh-context worker, build and validate its input brief per `$(cog skill-refs path orchestration/context-brief-gate.md)` — build it with `cog context-brief build --request` and confirm it with `cog context-brief validate`.

```text
inline: read the plan input (file | inline text) → build PLAN-UNDER-REVIEW + raw REQUEST brief → preflight
            │
            ├──(Agent fork)── Claude review-plan-oneshot → claude-review.md   (via cog plan-review)
            └──(Bash)──────── Codex  review-plan-oneshot → codex-review.md    (via cog plan-review)
            │
inline: read + compare both annotated reviews → steelman → verify disagreements against the plan/code
        → reconcile one verdict → write the definitive vetted review through cog plan-review → confirm
```

## Boundaries (delegation, not dispatch)

- The two workers are the single-plan reviewers, invoked with the three-absolute-path Orchestrator Invocation Contract (`<plan-path> <request-path> <output-path>`):
  - Claude: **Agent** tool (`subagent_type: general-purpose`) reading `$HOME/.claude/skills/review-plan-oneshot/SKILL.md`. Always use the absolute `$HOME/.claude/...` path.
  - Codex: `cog codex-runner run-exec` with a prompt opening with the `$review-plan-oneshot` mention.
- **Never use the `Skill` tool** for these — nested `Skill` calls inline the child and stall the orchestrator. See `$(cog skill-refs path skills-and-orchestration.md)` (§Dispatch vs Delegation).
- Orchestration plumbing (proof-of-delegation, parallel dispatch, graceful degradation) mirrors `plan-multi`. The contracts live in `$(cog skill-refs path orchestration/orchestration-patterns.md)`.
- Each Codex worker writes its review artifact through `cog plan-review`, so it runs write-capable: prepend the orientation from `cog codex-runner orientation write` and launch with `--mode danger --access write --effort high`. Branch on the runner's structured status and `cog codex-runner explain-status <status>` for quota/error handling.

## Reference resolution

The verdict model and orchestration references ship with `cog` and resolve in-repo (or from the XDG deploy) via `cog skill-refs path <area>/<file>.md`; the resolver always succeeds, so no graceful-degrade fallback is needed for these references.

## Inputs

- `$ARGUMENTS` — the plan to review plus the optional `--solo` flag. The plan input may be a single plan file or inline text that mixes the request/context with a full plan. Required. If empty, ask the user for a plan before proceeding. The skill is blind to which skill produced the plan.

## Phase 1: Setup

Parse flags and classify the plan input deterministically, then create the run directory. Substitute the literal `$ARGUMENTS`.

```bash
cog review-plan-multi-setup "$ARGUMENTS"
```

The command parses `--solo`, classifies the input form, creates the run dir, resolves the repo root, and pre-computes every scratch path. It emits `RUN_DIR=`, `MODE=` (`file|inline`), `SOLO=`, `REPO_ROOT=`, `REQUEST_FILE=`, `PLAN_UNDER_REVIEW=`, `CLAUDE_REVIEW=`, `CODEX_REVIEW=`, `FINAL_REVIEW=`, and the mode-specific `PLAN_PATH=` (file) or `RAW_INPUT_FILE=` (inline). It exits 2 on an unknown flag, a directory argument, or empty input (surface that error to the user).

Shell state does not persist between Bash calls — substitute the literal path values into later commands.

**Plan-input gate.** With the classified input in hand, confirm it is a reviewable plan per `$(cog skill-refs path plan-quality/plan-input-gate.md)` before building anything or dispatching either worker. Pass the form the setup command reported:

```bash
cog plan-gate check <PLAN_PATH>                     # MODE=file
cog plan-gate check --input-file <RAW_INPUT_FILE>   # MODE=inline
```

On `insufficient`, stop and ask the user to build a plan first; do not run the dual review.

## Phase 2: Build the plan-under-review and the raw request brief

Produce the **single, identical pair of inputs** both workers receive.

**`PLAN_UNDER_REVIEW`** — the consolidated plan content to review:

- `MODE=file` — the plan is `PLAN_PATH`; use it directly as `PLAN_UNDER_REVIEW` (copy or reference).
- `MODE=inline` — read `RAW_INPUT_FILE`; separate the plan portion into `PLAN_UNDER_REVIEW`.

**`REQUEST_FILE`** — the goal and context the plan is reviewed **against**, built as a best-constructed context brief per `$(cog skill-refs path orchestration/context-brief-contract.md)`. First write the user's original request/goal (the intent the plan is reviewed against, drawn from the input and conversation) to `$RUN_DIR/objective.txt`. Scaffold the authored body:

```bash
cog context-brief template --out "$RUN_DIR/request-body.md"
```

Fill `$RUN_DIR/request-body.md`: a well-oriented **Objective**; **Output Format** (an annotated plan review); **Boundaries / Scope** (review only, do not implement); **Context & Decisions** (decisions and reasoning, interview Q&A, the user's words — summarize narrative for clarity but carry the full substance); **Artifacts & Pointers** (relevant codebase facts as absolute paths and quoted excerpts); **Effort Guidance**; and **Not Evaluated**. Then assemble:

```bash
cog context-brief build --request "$RUN_DIR/objective.txt" --body "$RUN_DIR/request-body.md" --out "$REQUEST_FILE"
```

`build` attaches the request verbatim and fails closed unless every section is filled. `PLAN_UNDER_REVIEW` stays a separate file — the material under review, not part of the brief.

**Keep your own verdict out of both files.** The brief is raw context + requirements; the plan is the material under review. Injecting your own critique or proposed fixes biases the workers and defeats the independent second opinion.

If `--solo` (`SOLO=1`), skip Phase 3 and the Codex half of Phase 4; go straight to the Claude review then Phase 5.

## Phase 3: Preflight (gated)

Resolve Codex readiness with `cog codex-runner gate sandbox` — a single deterministic Bash call, no subagent. This phase **degrades**, never hard-fails: a missing helper or a failed gate sets the degrade flag (treat Codex as unavailable for Phase 4) and notes the reason.

```bash
if cog codex-runner gate sandbox "$RUN_DIR/preflight.json" >/dev/null 2>&1; then
  echo "CODEX_READY=1"
else
  echo "PREFLIGHT_DEGRADED=1 (codex-session unavailable/unhealthy or missing cog)"
fi
```

## Phase 4: Parallel dual-review dispatch

### 4a — Pre-snapshot and build the Codex prompt

```bash
cog codex-runner snapshot-pre "$RUN_DIR" "$RUN_DIR/reviews-pre.snap" \
  > "$RUN_DIR/reviews-pre-snapshot.json"
rm -f "$RUN_DIR/claude-review.md" "$RUN_DIR/codex-review.md" "$RUN_DIR/reviews-proof.diff"

cat > "$RUN_DIR/codex-review-prompt.txt" <<EOF
$(cog codex-runner orientation write)

\$review-plan-oneshot $RUN_DIR/plan-under-review.md $RUN_DIR/request.md $RUN_DIR/codex-review.md

You are running as the Codex parallel reviewer for the review-plan-multi
coordinator. Review the plan at the first path against the request/context at
the second path, and save the annotated review to the third path through
cog plan-review. Treat those files as your sole context. Review only; do not
implement the plan and do not modify repository files outside the review output.
EOF
```

(The unquoted heredoc inlines the orientation and the literal paths; `\$review-plan-oneshot` stays literal so the worker skill loads deterministically. Substitute the literal `RUN_DIR` value.)

### 4b — Dispatch both concurrently (one assistant message, two tool calls)

Issue **both** in a single message so they run in parallel. Skip the Codex (Bash) call when the degrade flag is set or `--solo`.

1. **Agent** (`subagent_type: general-purpose`, description `Review plan (Claude)`), literal `RUN_DIR`:

   ```text
   Read the skill file at $HOME/.claude/skills/review-plan-oneshot/SKILL.md and follow its
   Orchestrator Invocation Contract. Your three absolute path arguments are:

     1. plan-path:   <RUN_DIR>/plan-under-review.md
     2. request-path:<RUN_DIR>/request.md
     3. output-path: <RUN_DIR>/claude-review.md

   Review the plan against the request and save the annotated review to the output path
   through cog plan-review. Return a one-line confirmation containing the output path. Do
   not implement the plan or modify any repository files outside the output path.
   ```

2. **Bash** — `cog codex-runner run-exec --state`, literal `RUN_DIR`. The Codex reviewer writes its artifact, so it runs write-capable (`--mode danger --access write --effort high`). `run-exec` launches a cog-owned durable job and returns immediately, so it runs concurrently with the Claude-review Agent.

   ```bash
   cog codex-runner run-exec \
     --mode danger \
     --access write \
     --effort high \
     --prompt "$RUN_DIR/codex-review-prompt.txt" \
     --output "$RUN_DIR/codex-review-last.txt" \
     --events "$RUN_DIR/codex-events.jsonl" \
     --stderr "$RUN_DIR/codex-stderr.log" \
     --state "$RUN_DIR/codex.longrun.json"
   ```

   After the Claude-review Agent returns, poll-and-classify the Codex job with one verb, `cog codex-runner finalize --max-wall <secs>`. The exit code is the signal (0 = ok · 1 = failed · 75 = still running); re-run finalize while it exits 75. Duration is never judged.

   ```bash
   # Re-run while it exits 75 (still running); exit code is the signal (0 = ok, 1 = failed, 75 = still running). Duration is never judged.
   cog codex-runner finalize --state "$RUN_DIR/codex.longrun.json" --max-wall 300 \
     > "$RUN_DIR/codex-runner.json"
   ```

### 4c — Collect and validate

```bash
cog codex-runner snapshot-post "$RUN_DIR" \
  "$RUN_DIR/reviews-pre.snap" \
  "$RUN_DIR/reviews-post.snap" \
  "$RUN_DIR/reviews-proof.diff" \
  > "$RUN_DIR/reviews-post-snapshot.json"

# Claude review is REQUIRED (fail closed): proof diff present + non-empty review.
cog codex-runner verify-proof \
  --proof "$RUN_DIR/reviews-proof.diff" \
  --artifact "$RUN_DIR/claude-review.md" \
  > "$RUN_DIR/reviews-verify.json" || exit 1

# Codex review is best-effort — degrade gracefully.
if [ ! -s "$RUN_DIR/codex-review.md" ] ||
   ! jq -e '.status == "ok"' "$RUN_DIR/codex-runner.json" >/dev/null 2>&1; then
  echo "codex-unavailable"
fi
```

If the Claude-review Agent fails proof, stop and ask the user (retry/abort) — do not silently inline. If the Codex review is unavailable (degrade flag, `--solo`, empty output, or SIGTERM), proceed with the Claude review alone and remember to prepend the degradation note in Phase 6.

## Phase 5: Synthesize the definitive vetted review

Validate each worker artifact that exists, then read both:

```bash
cog plan-review validate "$RUN_DIR/claude-review.md" --json
cog plan-review validate "$RUN_DIR/codex-review.md" --json   # only if present
```

You are the **neutral judge** with the live conversation context neither worker fully has. Steelman **both** reviews against the rubric in `$(cog skill-refs path orchestration/verdict-model.md)`: correctness, completeness vs the request, feasibility, security, idiomatic fit, currency, and testability. On any disagreement — especially a flagged blocking issue — verify against the actual plan and code (read-only) and against primary sources per `$(cog skill-refs path research/primary-source-verification.md)` before deciding; prefer evidence observed now over either reviewer's assertion.

**Verdict reconciliation.** Using the `cog plan-review` artifact vocabulary (`APPROVED | MODIFIED`), the final top-level verdict is the **more severe** of the two: `APPROVED` only when both reviewers approve and you find no blocking issue; otherwise `MODIFIED`. Merge the per-item annotations (`APPROVED / MODIFIED / REMOVED / ADDED`) by union, de-duplicating overlapping findings and keeping the stricter classification on conflict. The final review is yours — not a mechanical merge.

Then **write the canonical output yourself** into the `cog plan-review` scaffold:

```bash
cog plan-review orchestrator "$RUN_DIR/plan-under-review.md" "$RUN_DIR/request.md" "$RUN_DIR/final-review.md" --json
```

Fill the synthesized prose into the existing scaffold sections, preserving every scaffold heading and the `APPROVED/MODIFIED/REMOVED/ADDED` vocabulary, then validate:

```bash
cog plan-review validate "$RUN_DIR/final-review.md" --json
```

If validation fails, fix the headings or required vocabulary and validate again. When degraded (Codex unavailable), synthesis is over the Claude review alone.

## Phase 6: Confirm

Report (do not dump full file contents unless asked):

1. The final **verdict** and the `FINAL_REVIEW` path.
2. Finding counts by annotation (APPROVED / MODIFIED / REMOVED / ADDED) and any blocking risks.
3. One-line **synthesis provenance**: reviewed independently by Claude and Codex (or Claude-only if degraded), plus any notable finding adopted from the Codex review.

If Codex was unavailable, prepend exactly one line:

```text
(codex cross-check unavailable: <short reason>)
```

Scratch artifacts (brief, plan-under-review, both reviews, events, proofs) stay in `$RUN_DIR`.

## Guardrails

- Inline coordinator: only this skill talks to the user; the two workers are non-interactive.
- Only this skill writes the final vetted review; the workers write their own review artifacts to scratch paths only and leave the repo otherwise untouched.
- Use the **Agent** tool (never `Skill`) for delegation; absolute `$HOME/.claude/skills/...` paths.
- Codex calls go through `cog codex-runner run-exec --state` with `--mode danger --access write
  --effort high` and the `write` orientation. cog runs Codex as a durable job; poll-and-classify it with one verb, `cog codex-runner finalize --max-wall <secs>` — the exit code is the signal (0 = ok, 1 = failed, 75 = still running), re-run finalize while it exits 75, and duration is never judged. Keep the orchestrator's own tool calls foreground; never call `codex exec` bare; never `--approval-policy`/`-a`.
- Never hard-fail on Codex unavailability — degrade to a Claude-only vetted review with the note.
- The Claude review is required; fail closed (ask the user) if its delegation proof is missing.
- Do not run git commands.
- For single-engine plan review without Codex, prefer plain `/review-plan-oneshot`; `--solo` here exists for graceful, uniform degradation within the coordinator.
