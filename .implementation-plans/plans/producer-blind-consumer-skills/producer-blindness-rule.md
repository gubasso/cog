# Producer-Blindness: Fix Leaks, Codify the Rule, Enforce in skill-lint

> Plan: producer-blind-consumer-skills | Round: 1 of 1 | Complexity: L | Generated: 2026-06-22 | Repo: /workspaces/cog

## Context

In this repo (`cog`, a Bash CLI plus shipped Claude/Codex skills), a **consumer** skill must depend only on the structural input contract it reads, never on the identity of the skill that produced that input. `runner-queue` drives the `.implementation-plans/` directory to completion no matter which skill produced the queue, yet its opening sentence says _"Drive a plan-writer implementation queue…"_ — coupling the consumer to one producer. The same leak exists in `review-findings` (Claude and Codex), which names `review-code-deep` / `review-loop` as the producers of its findings instead of describing the findings contract structurally.

A related cluster of cross-skill couplings violates the existing self-containment / twin-meta rules: `plan-one-lean` says "reuse the plan-writer interview pattern" (the pattern is already inlined right below it), `plan-writer` names its coordinator `plan-writer-multi`, and the Codex `plan-writer` carries "Codex twin of the Claude plan-writer skill" / "Same contract as the Claude plan-writer skill" twin meta plus a coordinator name.

The validation half of the rule is already satisfied (`runner-queue` delegates all input parsing to `cog` subcommands). This round (1) removes the prose coupling, (2) codifies the golden rule as a new ADR plus a `skill-contract.md` section and a `CLAUDE.md`/`AGENTS.md` non-negotiable, and (3) enforces it deterministically with a new `cog skill-lint` rule (`producer-blindness`) driven by a code-side consumer→producer map (no in-skill marker — `runner-queue/SKILL.md` is exactly at the 500-line lint cap).

## Previous Rounds

This is the first and only round — no prior rounds.

## Scope of This Round

IN scope:

- Producer-blindness prose fixes in `runner-queue` and `review-findings` (Claude + Codex).
- Adjacent coupling cleanup in `plan-one-lean` (Claude), `plan-writer` (Claude), and `plan-writer` (Codex).
- New ADR `docs/decisions/0026-consumer-skill-producer-blindness.md`, a "Producer-blind consumers" section in `docs/reference/skill-contract.md`, an entry in `docs/README.md`, and a non-negotiable line in `CLAUDE.md` and `AGENTS.md`.
- A new `producer-blindness` rule in `lib/commands/cmd_skill_lint.sh` plus tests in `test/integration/cmd_skill_lint.bats`.

OUT of scope:

- `cog research-shelf … --consuming-skills` metadata (producer-side `cog` field, not consumer prose).
- `/executor-*` references in `runner-queue` (output edge), executor→planner delegations, `plan-writer-multi` naming its `plan-writer` workers, and `plan-one-lean-codex`/`executor-lean-codex` delegation launchers — all legitimate and unchanged.
- Any git operations (no staging/committing).
- Fixing the broken stowed `~/.local/bin/cog` install (separate environment issue).

## Current State

### Key Files

- `/workspaces/cog/skills/claude/runner-queue/SKILL.md` — exactly **500 lines** (at the lint cap). The leak is the opening body line:

  ```text
  Drive a plan-writer implementation queue to completion. This skill runs **inline** in the
  ```

- `/workspaces/cog/skills/claude/review-findings/SKILL.md` — description line and body name the producer:

  ```text
  reports, review-code-deep JSON, review comments, or review-loop triage.
  ```

  ```text
  `review-findings` is the triage source of truth for review findings. It accepts freeform findings
  and the `review-code-deep` JSON schema:
  ```

- `/workspaces/cog/skills/codex/review-findings/SKILL.md` — same description line; body has:

  ```text
  and the `review-code-deep` JSON schema:
  ```

- `/workspaces/cog/skills/claude/plan-one-lean/SKILL.md` — the interview bullets are already inlined right under this lead-in:

  ```text
  Use `AskUserQuestion` for the interview loop. Reuse the `plan-writer` interview pattern:
  ```

- `/workspaces/cog/skills/claude/plan-writer/SKILL.md` — coordinator naming in the "Orchestrator Invocation Contract (coordinator mode)" section:

  ```text
  The coordinator-mode contract lives in `references/orchestrator-invocation-contract.md`. Read that
  reference when this skill is invoked non-interactively by a coordinator such as `plan-writer-multi`.
  Normal interactive `/plan-writer` use ignores coordinator mode.
  ```

- `/workspaces/cog/skills/codex/plan-writer/SKILL.md` — twin/coordinator meta in the `description:` frontmatter, the trigger-tests comment, the H1, and the body. Relevant current excerpts:

  ```text
    Codex twin of the Claude `plan-writer` skill. Single-pass generator that turns
  ...
    the `plan-writer-multi` coordinator as the parallel second engine. Triggers:
  ```

  ```text
  <!-- trigger-tests: "plan-writer for this brief", "draft an implementation plan from this context", "plan-writer-multi codex worker" -->

  # Plan Writer — Codex twin

  Same contract as the Claude `plan-writer` skill: turn a self-contained context brief into an
  ```

  ```text
  The `plan-writer-multi` coordinator invokes this twin with a prompt that opens with the `$plan-writer`
  ```

- `/workspaces/cog/lib/commands/cmd_skill_lint.sh` — 629 lines. The per-file dispatcher `__cog_skill_lint_scan_file` (near line 616) calls each `__cog_skill_lint_check_*` function. The finding helper signature is:

  ```bash
  __cog_skill_lint_finding "$file" "$line" "<rule-id>" "<message>" "<fix hint>"
  ```

  Marker/name helpers live in `cog::fn::skill::*` (e.g. `cog::fn::skill::frontmatter_name "$file"`). Existing prose-scanning rules (e.g. `__cog_skill_lint_scan_prose_file` near line 537) already track fenced-code-block state so code samples are not scanned — mirror that fence handling.

- `/workspaces/cog/test/integration/cmd_skill_lint.bats` — integration tests for the lint rules.

### Existing Patterns

- ADRs: `docs/decisions/NNNN-title.md`; latest is `0025`, so the new one is `0026`. Accepted ADRs are never deleted; cross-link related ADRs.
- Markdown: every fenced code block must declare a language (markdownlint MD040); use `text` when none applies. Headings need surrounding blank lines (MD022). Body prose wraps near 100 columns.
- `cog::fn::skill::frontmatter_name "$file"` returns the skill `name:`; lint default file set covers `skills/claude`, `skills/codex`, and `.claude/skills` (see `__cog_skill_lint_add_default_files`).
- Run the repo CLI as `./bin/cog` from `/workspaces/cog`. The stowed `~/.local/bin/cog` is broken.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml` (`/workspaces/cog/.implementation-plans/plans/producer-blind-consumer-skills/queue-rounds.yaml`), set this round's (`item: producer-blindness-rule`) `status` to `doing`.

### Step 1: Producer-blindness prose fixes (core)

Edit `skills/claude/runner-queue/SKILL.md`. Replace the line:

```text
Drive a plan-writer implementation queue to completion. This skill runs **inline** in the
```

with:

```text
Drive a queued implementation plan under `.implementation-plans/` to completion. This skill runs **inline** in the
```

This is the only change to this file. **Do not add any line** — after editing, confirm `wc -l skills/claude/runner-queue/SKILL.md` is still ≤ 500.

Edit `skills/claude/review-findings/SKILL.md`:

- Description line, replace:

  ```text
  reports, review-code-deep JSON, review comments, or review-loop triage.
  ```

  with:

  ```text
  reports, structured findings JSON, review comments, or triage from any review pass.
  ```

- Body, replace:

  ```text
  and the `review-code-deep` JSON schema:
  ```

  with:

  ```text
  and the shared structured-findings contract:
  ```

Edit `skills/codex/review-findings/SKILL.md`: apply the same two replacements (the description line is identical; the body line is `and the \`review-code-deep\` JSON schema:`).

### Step 2: Adjacent cross-skill coupling cleanup

Edit `skills/claude/plan-one-lean/SKILL.md`. Replace:

```text
Use `AskUserQuestion` for the interview loop. Reuse the `plan-writer` interview pattern:
```

with:

```text
Use `AskUserQuestion` for the interview loop, following this interview pattern:
```

(Leave the inlined interview bullets that follow unchanged.)

Edit `skills/claude/plan-writer/SKILL.md`. Replace:

```text
reference when this skill is invoked non-interactively by a coordinator such as `plan-writer-multi`.
Normal interactive `/plan-writer` use ignores coordinator mode.
```

with:

```text
reference when this skill is invoked non-interactively in coordinator mode. Normal interactive use
ignores coordinator mode.
```

Edit `skills/codex/plan-writer/SKILL.md`, making each replacement:

- Description, replace `Codex twin of the Claude \`plan-writer\` skill. Single-pass generator that turns`with`Single-pass generator that turns`.
- Description, replace `the \`plan-writer-multi\` coordinator as the parallel second engine. Triggers:`with`a dual-engine coordinator as the parallel second engine. Triggers:`.
- Trigger-tests comment, replace `"plan-writer-multi codex worker"` with `"dual-engine codex plan worker"`.
- H1 heading, replace `# Plan Writer — Codex twin` with `# Plan Writer (Codex)`.
- Body, replace `Same contract as the Claude \`plan-writer\` skill: turn a self-contained context brief into an`with`Turn a self-contained context brief into an`.
- Body, replace `The \`plan-writer-multi\` coordinator invokes this twin with a prompt that opens with the \`$plan-writer\``
  with `A dual-engine coordinator invokes this skill with a prompt that opens with the \`$plan-writer\``.

Keep the `$plan-writer` self-invocation token and the `executor-prex Executor Factor` sizing reference unchanged — those are not producer-of-input leaks.

### Step 3: New ADR — `docs/decisions/0026-consumer-skill-producer-blindness.md`

Create the ADR following the format of an existing accepted ADR (read `docs/decisions/0025-*.md` for the house style). State the decision: a consumer skill depends only on its structural input contract (e.g. the `.implementation-plans/` directory structure, the shared structured-findings contract) and is blind to which skill produced that input; all input validation/parsing is delegated to `cog`; enforced by the `producer-blindness` rule in `cog skill-lint` via a curated consumer→producer map. Record context (the `runner-queue`/`review-findings` leaks), the decision, consequences, and cross-links to ADRs `0008` (skill/script boundary), `0011` (directory plan-queue format), `0016` (prefix taxonomy), `0019` (lean positive prose), `0021` (twin naming), `0024`/`0025` (self-containment / SoT delegation). Every fenced block declares a language.

### Step 4: Document the rule in the reference + index + non-negotiables

- `docs/reference/skill-contract.md` — add a "Producer-blind consumers" section (mirror the existing "Plan-mode gate" / "Prefix taxonomy" sections) describing: the rule, that enforcement is the `producer-blindness` lint rule keyed off the consumer→producer map, and the current entries (`runner-queue` → `plan-writer`, `plan-writer-multi`; `review-findings` → `review-code-deep`, `review-loop`).
- `docs/README.md` — add `0026` to the decisions index (match the surrounding list format).
- `CLAUDE.md` — add one `Non-negotiable:` paragraph mirroring the existing entries, pointing at ADR `0026` and `docs/reference/skill-contract.md` ("Producer-blind consumers").
- `AGENTS.md` — add a matching short guideline (under "Skill and Script Responsibility Boundary" or a new adjacent subsection), pointing at ADR `0026`.

### Step 5: Add the `producer-blindness` lint rule

Edit `lib/commands/cmd_skill_lint.sh`:

1. Add a curated map function near the other helpers:

   ```bash
   # Consumer skill name -> space-separated producer names it must not name in prose.
   __cog_skill_lint_producer_blind_producers() {
     case "$1" in
       runner-queue) printf '%s' "plan-writer plan-writer-multi" ;;
       review-findings) printf '%s' "review-code-deep review-loop" ;;
       *) printf '%s' "" ;;
     esac
   }
   ```

2. Add the check function `__cog_skill_lint_check_producer_blind "$file"` that:
   - resolves the skill name with `cog::fn::skill::frontmatter_name "$file"`;
   - looks up forbidden producers via `__cog_skill_lint_producer_blind_producers "$name"`; returns 0 immediately when the list is empty;
   - scans the file line by line, tracking fenced-code-block state exactly like `__cog_skill_lint_scan_prose_file` so names inside code fences are ignored; for each non-fenced line containing a forbidden producer name as a whole word, emit:

     ```bash
     __cog_skill_lint_finding "$file" "$line_no" "producer-blindness" \
       "names producer skill '<producer>'; a consumer must be blind to its input's producer" \
       "describe the structural input contract (e.g. .implementation-plans/ or the findings contract); do not name the producer skill"
     ```

   - returns non-zero if any finding was emitted.
3. Wire the check into `__cog_skill_lint_scan_file` alongside the other `if ! __cog_skill_lint_check_*` calls, following the same `failed=1` accumulation pattern.

Match a producer name as a whole token (word-boundary), so unrelated substrings do not false-match, and so the reworded skills (which no longer contain the names in prose) stay clean.

### Step 6: Tests for the new rule

Edit `test/integration/cmd_skill_lint.bats`, following the existing test style (temp fixture skill + `run` the lint command + assert on output/status). Add cases:

- A fixture skill named `runner-queue` (or `review-findings`) whose prose contains a forbidden producer name → expect a `producer-blindness` finding and non-zero status.
- The same forbidden name appearing only inside a fenced code block → no `producer-blindness` finding (clean).
- A fixture skill NOT in the map that names a producer → no `producer-blindness` finding (the rule is scoped to mapped consumers only).

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: producer-blindness-rule`) `status` to `done`.
2. All rounds are now done, so in the top-level `/workspaces/cog/.implementation-plans/queue-plans.yaml` set this plan's (`item: producer-blind-consumer-skills`) `status` to `done`. Leave the plan directory in place.

## Acceptance Criteria

- [ ] `rg -n "plan-writer" skills/claude/runner-queue/SKILL.md` returns nothing in prose (the only match, if any, would be inside a fenced example — there are none after the fix).
- [ ] `rg -n "review-code-deep|review-loop" skills/claude/review-findings/SKILL.md skills/codex/review-findings/SKILL.md` returns nothing in prose.
- [ ] `skills/codex/plan-writer/SKILL.md` no longer contains the strings "Codex twin", "Same contract as the Claude", or "plan-writer-multi"; `plan-one-lean` and Claude `plan-writer` no longer name their related skills as described in Step 2.
- [ ] `wc -l skills/claude/runner-queue/SKILL.md` is ≤ 500.
- [ ] `docs/decisions/0026-consumer-skill-producer-blindness.md` exists; `docs/README.md`, `docs/reference/skill-contract.md`, `CLAUDE.md`, and `AGENTS.md` reference the rule.
- [ ] `./bin/cog skill-lint` passes (zero findings) over all shipped skills, including the reworded ones, AND the new `producer-blindness` rule is exercised by the bats cases.
- [ ] `just test` (unit + integration) passes; `just lint` (`pre-commit run --all-files`) passes.
- [ ] This plan's `queue-rounds.yaml` shows round `producer-blindness-rule` as `done`.
- [ ] The top-level `.implementation-plans/queue-plans.yaml` shows this plan as `done`.

## Next Round

This is the final round.
