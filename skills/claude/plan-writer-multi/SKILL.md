---
name: plan-writer-multi
description: >
  Dual-engine implementation-plan coordinator. Claude and Codex each independently
  draft a plan in parallel from one identical raw context brief, then the main-thread
  Claude reviews both and synthesizes a single definitive plan under
  .implementation-plans/. Use when the user says "plan-writer-multi", "dual-engine
  plan", "plan with codex", "two plans then synthesize", or wants a second
  independent engine cross-checking the plan. Optional flags:
  --executor <prex|single-pass|limited> (shared executor sizing, default prex) and
  --solo (skip Codex; Claude-only).
argument-hint: "[--executor <prex|single-pass|limited>] [--solo] <orientation/focus/goal>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Grep Glob Agent AskUserQuestion
---

<!-- trigger-tests: "plan-writer-multi", "dual-engine plan", "plan with codex", "two plans then synthesize" -->

# Plan Writer Multi

Coordinate **two independent plan-writers** — Claude and Codex — running in parallel from the
**same raw context**, then review both drafts and synthesize one definitive implementation plan under
`.implementation-plans/plans/`. A second engine, blind to the other's reasoning, surfaces alternative
approaches and round decompositions and catches blind spots the first engine misses.

This skill runs **inline** (no fork): only the main thread can read the live conversation, interview
the user, and act as the neutral judge. It **delegates** generation to two non-interactive workers
and keeps all interaction and all repo writes to itself.

```text
inline: gather raw context → research → INTERVIEW → build RAW BRIEF → preflight
            │
            ├──(Agent fork)── Claude plan-writer (orchestrator mode) → claude-draft.md
            └──(Bash)──────── Codex  plan-writer twin (orchestrator)  → codex-draft.md
            │
inline: review + compare both → reconcile Layer 1 directory split and Layer 2 round split
        (re-interview if needed)
        → write definitive plan to .implementation-plans/ → confirm
```

## Boundaries (delegation, not dispatch)

- The two workers are the single-pass plan-writers, invoked in **orchestrator mode**:
  - Claude: **Agent** tool (`subagent_type: general-purpose`) reading
    `$HOME/.claude/skills/plan-writer/SKILL.md` → "Orchestrator Invocation Contract (coordinator
    mode)". Always use the absolute `$HOME/.claude/...` path.
  - Codex: `codex-session exec` with a prompt opening with the `$plan-writer` mention.
- **Never use the `Skill` tool** for these — nested `Skill` calls inline the child and stall the
  orchestrator. See `$DOCS_NOTES_REPO/tech/tools/claude-code/skills-and-orchestration.md`
  (§Dispatch vs Delegation).
- Orchestration plumbing (proof-of-delegation, sandbox detection, parallel dispatch, graceful
  degradation) mirrors `ask` (Step 2b) and `prex`; for this extraction round it stays prose and is
  explicitly deferred to Round 12 `lib/codex.sh`. The contracts live in
  `$DOCS_NOTES_REPO/tech/tools/claude-code/orchestration/orchestration-patterns.md`.
- Read `$DOCS_NOTES_REPO/tech/tools/claude-code/codex-conventions.md` before any Codex command.

## Reference resolution

`DOCS_NOTES="${DOCS_NOTES_REPO:-}"`. If unset, warn and continue (degraded sizing). When set, the
plan-rounds references are at `$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/`.

## Inputs

- `$ARGUMENTS` — free-text **orientation** (the angle/focus/goal) plus optional flags. Required. If
  empty, ask the user for an orientation before proceeding.

## Phase 1: Setup

Parse flags deterministically, then create the run directory. Substitute the literal `$ARGUMENTS`.

```bash
cog plan-writer-multi-setup "$ARGUMENTS"
```

The command parses the flags (`--executor <prex|single-pass|limited>`, `--solo`), validates them,
maps the executor to its effort factor, creates the run dir, resolves the repo root, and writes the
orientation verbatim to `$RUN_DIR/orientation.txt`. It emits `RUN_DIR=`, `EXECUTOR=`, `EF=`, `SOLO=`,
`REPO_ROOT=`, and `ORIENTATION_FILE=` lines, and exits 2 on a bad/unknown flag, an invalid executor,
or an empty orientation (surface that error to the user).

Shell state does not persist between Bash calls — substitute the literal `RUN_DIR`/`EXECUTOR`/`EF`
values into later commands, and read the orientation from `$RUN_DIR/orientation.txt`. When
`$DOCS_NOTES_REPO` is set, read the three plan-rounds references (`plan-lifecycle.md`,
`complexity-heuristic.md`, `round-templates.md`) now — the synthesis in Phase 8 needs them.

## Phases 2–4: Gather context, research, interview (inline)

Follow the stock `plan-writer` Phases 2–4 (`$HOME/.claude/skills/plan-writer/SKILL.md`):

- **Phase 2 — Gather raw context**: walk the conversation for problem, decisions (with reasoning),
  code explored, current state, requirements, rejected alternatives, resolved/open questions. Keep
  the user's own words; do not pre-collapse into your own interpretation (see Phase 5).
- **Phase 3 — Research codebase**: read the relevant files; collect absolute paths + quoted
  excerpts (signatures, key lines), repo conventions (`CLAUDE.md`), and similar prior art.
- **Phase 4 — Interview**: this coordinator is the **only** place the user is asked anything. Use
  `AskUserQuestion`; present concrete options with trade-offs; adapt batching; record "you decide"
  as a skill-chosen default. Settle scope, approach, and any sizing intent. The `--executor`/EF is
  already fixed from Phase 1 and is a **shared** input to both workers.

## Phase 5: Build the RAW context brief

Write `$RUN_DIR/plan-brief.md` — the **single, identical input** both workers receive. It must be as
**raw and high-fidelity as what you yourself hold** ("as if prompting Codex directly"), so both
engines start neutral. Compose it, in order:

1. **Orientation / user prompts — verbatim** (the `$ARGUMENTS` orientation and the relevant user
   turns, quoted).
2. **Relevant conversation content — minimally paraphrased** (quote the user's words and key
   exchanges; do not compress into your interpretation).
3. **Interview Q&A — verbatim** (each question + the user's raw answer).
4. **Codebase research — raw excerpts** (absolute paths + quoted code/signatures), not summaries.
5. **Hard constraints + the executor line**: include `Executor: <EXECUTOR> (EF <EF>)` so both
   workers size against the same factor.

**Do NOT put your own proposed approach/solution in the brief** — that would bias the workers and
defeat the independent second opinion. The brief is _raw context + requirements + decisions_, never a
pre-baked plan. Scope to relevance, but favor fidelity over brevity.

If `--solo` (`SOLO=1`), skip Phase 6 and the Codex half of Phase 7; go straight to the Claude draft
then Phase 8.

## Phase 6: Preflight (gated)

Resolve Codex readiness and sandbox mode with `cog codex-runner gate sandbox` — a single
deterministic Bash call, no subagent. The `sandbox` gate is a superset of codex
availability/health, so one call resolves everything Phase 7 needs. This phase **degrades**, never
hard-fails: a missing helper or a failed gate simply sets the degrade flag (the gate's non-zero exit
is the signal; the decision stays here).

This readiness check remains best-effort. Phase 7 delegates the actual Codex command construction,
execution, and output classification to `cog codex-runner`.

```bash
if cog codex-runner gate sandbox "$RUN_DIR/preflight.json" >/dev/null 2>&1; then
  SANDBOX_MODE="$(jq -r '.codex_session.sandbox_mode' "$RUN_DIR/preflight.json")"
  echo "SANDBOX_MODE=$SANDBOX_MODE"
else
  echo "PREFLIGHT_DEGRADED=1 (codex-session unavailable/unhealthy or missing cog)"
fi
```

If the gate exits non-zero (helper missing, codex unavailable/unhealthy, or a malformed fragment),
set the **degrade flag** (treat Codex as unavailable for Phase 7) and note the reason. Do not
hard-fail — the workflow still produces a Claude-only plan. If `SANDBOX_MODE=fallback`, tell the user
in one line.

## Phase 7: Parallel dual-draft dispatch

### 7a — Pre-snapshot and build the Codex prompt

```bash
cog codex-runner snapshot-pre "$RUN_DIR" "$RUN_DIR/drafts-pre.snap" \
  > "$RUN_DIR/drafts-pre-snapshot.json"
rm -f "$RUN_DIR/claude-draft.md" "$RUN_DIR/codex-draft.md" "$RUN_DIR/drafts-proof.diff"

cat > "$RUN_DIR/codex-plan-prompt.txt" <<EOF
\$plan-writer

$(cat "$RUN_DIR/plan-brief.md")

You are running as the Codex parallel plan-writer for the plan-writer-multi
coordinator. The text above is a self-contained raw context brief — treat it as
your sole context. Classify complexity (use the Executor/EF stated in the brief)
and produce ONE implementation-plan draft as your final message. Read-only: do
not modify files, do not interview, do not ask questions.
EOF
```

(The unquoted heredoc inlines the brief verbatim; `\$plan-writer` stays literal. Brief content is
data — it is not re-evaluated.)

### 7b — Dispatch both concurrently (one assistant message, two tool calls)

Issue **both** in a single message so they run in parallel. Skip the Codex (Bash) call when the
degrade flag is set or `--solo`.

1. **Agent** (`subagent_type: general-purpose`, description `Draft plan (Claude)`), literal `RUN_DIR`:

   ```text
   Read the skill file at $HOME/.claude/skills/plan-writer/SKILL.md and follow its
   "Orchestrator Invocation Contract (coordinator mode)". Your two path arguments are:

     1. brief-path:  <RUN_DIR>/plan-brief.md
     2. output-path: <RUN_DIR>/claude-draft.md

   Read the brief, classify complexity, and Write your plan draft to the output path.
   Return a one-line confirmation containing the output path. Do not write to
   .implementation-plans/ or modify any repository files outside the output path.
   ```

2. **Bash** — `cog codex-runner run-exec`, **foreground** (`run_in_background`
   false/omitted), **timeout `600000`**, literal `RUN_DIR`/`SANDBOX_MODE`. The runner owns
   native/fallback command construction,
   `< /dev/null`, direct stderr capture, JSONL events, `--output-last-message`, and
   empty/SIGTERM/non-zero/quota classification.

   ```bash
   RUNNER_MODE="$SANDBOX_MODE"
   [ "$RUNNER_MODE" = "native" ] || RUNNER_MODE="fallback"
   cog codex-runner run-exec \
     --mode "$RUNNER_MODE" \
     --profile medium \
     --prompt "$RUN_DIR/codex-plan-prompt.txt" \
     --output "$RUN_DIR/codex-draft.md" \
     --events "$RUN_DIR/codex-events.jsonl" \
     --stderr "$RUN_DIR/codex-stderr.log" \
     > "$RUN_DIR/codex-runner.json"
   ```

### 7c — Collect and validate

```bash
cog codex-runner snapshot-post "$RUN_DIR" \
  "$RUN_DIR/drafts-pre.snap" \
  "$RUN_DIR/drafts-post.snap" \
  "$RUN_DIR/drafts-proof.diff" \
  > "$RUN_DIR/drafts-post-snapshot.json"

# Claude draft is REQUIRED (fail closed): proof diff present + non-empty draft.
cog codex-runner verify-proof \
  --proof "$RUN_DIR/drafts-proof.diff" \
  --artifact "$RUN_DIR/claude-draft.md" \
  > "$RUN_DIR/drafts-verify.json" || exit 1

# Codex draft is best-effort — degrade gracefully.
if [ ! -s "$RUN_DIR/codex-draft.md" ] ||
   ! jq -e '.status == "ok"' "$RUN_DIR/codex-runner.json" >/dev/null 2>&1; then
  echo "codex-unavailable"
fi
```

If the Claude-draft Agent fails proof, stop and ask the user (retry/abort) — do not silently inline.
If the Codex draft is unavailable (degrade flag, `--solo`, empty output, or SIGTERM), proceed with
the Claude draft alone and remember to prepend the degradation note in Phase 9.

## Phase 8: Synthesize the definitive plan

Read both drafts (`claude-draft.md` and, if present, `codex-draft.md`). You are the **neutral judge**
with the live conversation context neither worker fully has. Review and compare them against a rubric
distilled from `plan-reviewer` and
`$DOCS_NOTES_REPO/tech/tools/claude-code/orchestration/verdict-model.md`:

- correctness, completeness vs the brief, feasibility, **Layer 1 / Layer 2 decomposition quality**,
  risk coverage, idiomatic fit to repo conventions, currency.

### Scope-driven decomposition check

Round count is scope-driven and uncapped. Compare drafts on Layer 1 domain/scope decomposition and
Layer 2 per-directory round decomposition. Do not reject or down-weight a draft merely because it
proposes XL or many rounds under `prex`.

Steelman **both** drafts; adopt the stronger elements of each; on any disagreement — especially the
complexity grade, directory split, or round split — decide using the conversation context you alone
hold, and **re-interview the user** (`AskUserQuestion`) to confirm the directory and round split
before writing. The final plan is yours — not a mechanical merge.

Then **write the canonical output yourself**, following stock `plan-writer` Phases 5–6 and the shared
`round-templates.md`. The coordinator owns final writes; both workers remain read-only with respect
to `.implementation-plans/`.

- Derive the slug from the orientation through `cog plan-slug` and run the Phase 1b
  collision check — do not silently overwrite. The helper owns `[a-z0-9-]`, max-length, and
  the reserved-name set owned by `cog plan-slug`; the coordinator owns collision judgment.
- Classify the final grade (axes ÷ EF) as a sizing signal. Select one or more flat sibling plan
  directories via Layer 1, then split each directory into uncapped rounds via Layer 2. Once the
  Layer 1 split is known, run the Phase 1b collision check for **every** sibling directory it will
  register (`$PLANS_DIR/<sibling-slug>/`), not just the base slug — do not silently overwrite any
  existing non-empty sibling directory.
- Bootstrap `.implementation-plans/README.md` + top-level `queue-plans.yaml` through
  `cog plan-init` and `cog queue-bootstrap`. Write a complete plan directory for **each** Layer 1
  sibling (its own `README.md`, optional `STRATEGY.md`, and round files), then register
  each plan directory through `cog queue-append` (append-only, with a `prompt:` field). For each
  sibling directory, bootstrap and append the inner `queue-rounds.yaml` through the same helper.
  Every plan/round file is self-contained and carries the `Executor: <EXECUTOR> (EF <EF>)` line.
  Include the one-round-per-`/prex`-session execution-discipline section.

```bash
cog plan-slug --text "$(cat "$RUN_DIR/orientation.txt")" --json
cog plan-init --repo-root "$REPO_ROOT" --json
cog queue-bootstrap --schema plans --queue "$PLAN_ROOT/queue-plans.yaml" --json
cog queue-append --schema plans --queue "$PLAN_ROOT/queue-plans.yaml" \
  --item "$QUEUE_ITEM" --status todo --depends-on "$DEPENDS_ON_CSV" \
  --prompt "$PROMPT" --notes "$NOTES" --json
```

For each sibling directory:

```bash
cog queue-bootstrap --schema rounds --queue "$PLANS_DIR/$SLUG/queue-rounds.yaml" --json
cog queue-append --schema rounds --queue "$PLANS_DIR/$SLUG/queue-rounds.yaml" \
  --item "$TOPIC" --status todo --depends-on "$ROUND_DEPENDS_ON_CSV" \
  --prompt "/prex -ar .implementation-plans/plans/$SLUG/$TOPIC.md" \
  --notes "$ROUND_NOTES" --json
```

Append one `queue-plans.yaml` entry per sibling directory. Use `depends_on` between top-level
entries where the domain split has ordering, and use
`/prex -ar @.implementation-plans/plans/<slug>/` as the top-level prompt form.

If the plan's rounds implement into a **satellite git repo** other than the one holding the plan
(for example, extracting code into a target project or writing into a SoT docs repo), add an optional
top-level `repos:` list to the inner `queue-rounds.yaml` — one absolute path per satellite, placed
**before** `rounds:`. `/plan-queue-runner` then guards every declared repo's clean tree and commits
each one via `/gc -a --repo <sat>...`, so the round's artifacts are committed, not just the
`queue-rounds.yaml` status flip.

When degraded (Codex unavailable), synthesis is over the Claude draft alone.

## Phase 9: Confirm

Report (do not dump full file contents unless asked):

1. Plan directory or directories, file count, approx line count.
2. Adjusted grade, Layer 1 directory count, and Layer 2 round count per directory.
3. The exact `/prex -ar` execution command(s) and the one-round-per-session reminder for directories.
4. One-line **synthesis provenance**: drafted independently by Claude and Codex (or Claude-only if
   degraded), plus any notable element adopted from the Codex draft.

If Codex was unavailable, prepend exactly one line:

```text
(codex cross-check unavailable: <short reason>)
```

Scratch artifacts (brief, both drafts, events, proofs) stay in `$RUN_DIR`.

## Guardrails

- Inline coordinator: only this skill talks to the user; the two workers are non-interactive.
- Only this skill writes to `.implementation-plans/`; the workers are read-only w.r.t. the repo and
  emit drafts to scratch paths only.
- Use the **Agent** tool (never `Skill`) for delegation; absolute `$HOME/.claude/skills/...` paths.
- Codex calls go through `cog codex-runner run-exec` with `--profile medium`, read-only
  native/fallback sandboxing, `< /dev/null`, stderr→log, and Bash timeout `600000`, in the
  **foreground** (`run_in_background` false/omitted) — never background a Codex call; a backgrounded
  run is reaped ~5s after the turn in a headless host. Never call `codex exec` bare; never
  `--approval-policy`/`-a`.
- Never hard-fail on Codex unavailability — degrade to a Claude-only plan with the note.
- Do not run git commands. Do not overwrite `.implementation-plans/README.md`; append-only on
  `queue-plans.yaml`.
- The Claude draft is required; fail closed (ask the user) if its delegation proof is missing.
- For single-engine planning without Codex, prefer plain `/plan-writer`; `--solo` here exists for
  graceful, uniform degradation within the coordinator.
